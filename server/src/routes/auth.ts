import { Hono } from 'hono';
import { appleClientConfigFromEnv, exchangeAuthorizationCode, verifyAppleIdentityToken } from '../lib/apple';
import { createSession, rotateSession, revokeSession } from '../lib/session';
import { requireAuth, type AuthVariables } from '../middleware/auth';
import { rateLimitByIp, rateLimitByUser } from '../middleware/rate-limit';
import { badRequest } from '../errors';
import type { Env } from '../env';

interface AppleSignInBody {
  identityToken: string;
  authorizationCode: string;
  rawNonce: string;
}

async function readJsonBody(request: Request): Promise<Record<string, unknown>> {
  try {
    const body = await request.json();
    if (typeof body !== 'object' || body === null) throw new Error();
    return body as Record<string, unknown>;
  } catch {
    throw badRequest('invalid_body', 'request body must be a JSON object');
  }
}

function requireString(body: Record<string, unknown>, field: string): string {
  const value = body[field];
  if (typeof value !== 'string' || value.length === 0) {
    throw badRequest('invalid_body', `${field} is required`);
  }
  return value;
}

export const authRoutes = new Hono<{ Bindings: Env; Variables: AuthVariables }>();

authRoutes.post('/apple', rateLimitByIp(), async (c) => {
  const raw = await readJsonBody(c.req.raw);
  const body: AppleSignInBody = {
    identityToken: requireString(raw, 'identityToken'),
    authorizationCode: requireString(raw, 'authorizationCode'),
    rawNonce: requireString(raw, 'rawNonce'),
  };

  const identity = await verifyAppleIdentityToken({
    identityToken: body.identityToken,
    rawNonce: body.rawNonce,
    bundleId: c.env.APPLE_BUNDLE_ID,
  });

  // apple_subject でユーザーを取得または作成する。
  // ON CONFLICT で同一アカウントの同時サインイン競合を吸収する(既存行があれば挿入しない)。
  // 削除済みアカウントは apple_subject を匿名化しているため、再サインインは新規ユーザーになる。
  // 表示名は自由入力を持たせず、匿名ハンドルはリーグ参加時にサーバーが生成する(Phase 2)。
  await c.env.DB.prepare(
    'INSERT INTO users (id, apple_subject, created_at) VALUES (?, ?, ?) ON CONFLICT(apple_subject) DO NOTHING',
  )
    .bind(crypto.randomUUID(), identity.subject, new Date().toISOString())
    .run();
  const user = await c.env.DB.prepare(
    'SELECT id, anonymous_handle FROM users WHERE apple_subject = ? AND deleted_at IS NULL',
  )
    .bind(identity.subject)
    .first<{ id: string; anonymous_handle: string | null }>();
  if (!user) {
    // 挿入直後に消えることは通常なく、到達するのは想定外の状態のみ。
    throw new Error('failed to create or fetch user');
  }

  // アカウント削除時の失効処理に備えて authorization code を refresh token へ交換しておく。
  // Apple 側の secrets が未設定、または交換に失敗してもサインイン自体は成立させる。
  const appleConfig = appleClientConfigFromEnv(c.env);
  if (appleConfig) {
    try {
      const exchanged = await exchangeAuthorizationCode({ code: body.authorizationCode, config: appleConfig });
      if (exchanged) {
        await c.env.DB.prepare('UPDATE users SET apple_refresh_token = ? WHERE id = ?')
          .bind(exchanged.refreshToken, user.id)
          .run();
      }
    } catch (error) {
      console.warn('Apple authorization code exchange failed', error);
    }
  } else if (c.env.ENVIRONMENT === 'production') {
    console.error('Apple client secrets are not configured; token revocation on account deletion will be skipped');
  }

  const tokens = await createSession(c.env, user.id);
  return c.json(
    {
      accessToken: tokens.accessToken,
      accessTokenExpiresAt: tokens.accessTokenExpiresAt,
      refreshToken: tokens.refreshToken,
      user: { id: user.id, anonymousHandle: user.anonymous_handle },
    },
    200,
  );
});

authRoutes.post('/refresh', rateLimitByIp(), async (c) => {
  const raw = await readJsonBody(c.req.raw);
  const refreshToken = requireString(raw, 'refreshToken');
  const tokens = await rotateSession(c.env, refreshToken);
  return c.json(
    {
      accessToken: tokens.accessToken,
      accessTokenExpiresAt: tokens.accessTokenExpiresAt,
      refreshToken: tokens.refreshToken,
    },
    200,
  );
});

authRoutes.post('/logout', requireAuth, rateLimitByUser(), async (c) => {
  const raw = await readJsonBody(c.req.raw);
  const refreshToken = requireString(raw, 'refreshToken');
  await revokeSession(c.env, c.get('userId'), refreshToken);
  return c.body(null, 204);
});
