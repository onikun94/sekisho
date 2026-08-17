import { env } from 'cloudflare:workers';
import { afterAll, beforeAll, describe, expect, it, vi } from 'vitest';
import app from '../src/index';
import { clearAppleJwksCache } from '../src/lib/apple';
import { createAppleTestSigner, defaultClaims, signIdentityToken, type AppleTestSigner } from './helpers/apple-test-keys';

let signer: AppleTestSigner;

beforeAll(async () => {
  signer = await createAppleTestSigner();
  clearAppleJwksCache();
  // Apple JWKS へのアウトバウンド fetch をモックする(それ以外の外部リクエストは失敗させる)。
  vi.spyOn(globalThis, 'fetch').mockImplementation(async (input, init) => {
    const request = new Request(input, init);
    if (request.url === 'https://appleid.apple.com/auth/keys') {
      return Response.json(signer.jwks);
    }
    throw new Error(`Unexpected outbound request: ${request.method} ${request.url}`);
  });
});

afterAll(() => {
  vi.restoreAllMocks();
});

// レート制限(IPキー)にテスト間で引っかからないよう、既定では呼び出しごとに一意のIPを使う。
let ipCounter = 0;
function uniqueIp(): string {
  ipCounter += 1;
  return `10.0.${Math.floor(ipCounter / 256)}.${ipCounter % 256}`;
}

async function postJson(path: string, body: unknown, headers: Record<string, string> = {}, ip?: string) {
  return app.request(
    path,
    {
      method: 'POST',
      headers: { 'content-type': 'application/json', 'CF-Connecting-IP': ip ?? uniqueIp(), ...headers },
      body: JSON.stringify(body),
    },
    env,
  );
}

async function signIn(options: { subject?: string; rawNonce?: string } = {}) {
  const rawNonce = options.rawNonce ?? 'raw-nonce-123';
  const claims = await defaultClaims({ bundleId: env.APPLE_BUNDLE_ID, rawNonce, subject: options.subject });
  const identityToken = await signIdentityToken(signer, claims);
  return postJson('/v1/auth/apple', {
    identityToken,
    authorizationCode: 'dummy-authorization-code',
    rawNonce,
  });
}

describe('POST /v1/auth/apple', () => {
  it('有効なidentity tokenでユーザーが作成されトークンが返る', async () => {
    const response = await signIn();
    expect(response.status).toBe(200);
    const body = (await response.json()) as {
      accessToken: string;
      accessTokenExpiresAt: string;
      refreshToken: string;
      user: { id: string; anonymousHandle: string | null };
    };
    expect(body.accessToken.split('.')).toHaveLength(3);
    expect(body.refreshToken.length).toBeGreaterThan(20);
    expect(new Date(body.accessTokenExpiresAt).getTime()).toBeGreaterThan(Date.now());
    // 匿名ハンドルはリーグ参加時にサーバーが生成する(Phase 2)ため、この時点ではnull。
    expect(body.user.anonymousHandle).toBeNull();

    const row = await env.DB.prepare('SELECT apple_subject, anonymous_handle FROM users WHERE id = ?')
      .bind(body.user.id)
      .first<{ apple_subject: string; anonymous_handle: string | null }>();
    expect(row?.apple_subject).toBe('apple-subject-0001');
    expect(row?.anonymous_handle).toBeNull();
  });

  it('同じapple_subjectでの再サインインは同一ユーザーを返す', async () => {
    const first = (await (await signIn()).json()) as { user: { id: string } };
    const second = (await (await signIn()).json()) as { user: { id: string } };
    expect(second.user.id).toBe(first.user.id);
  });

  it('nonceが一致しない場合は401', async () => {
    const claims = await defaultClaims({ bundleId: env.APPLE_BUNDLE_ID, rawNonce: 'expected-nonce' });
    const identityToken = await signIdentityToken(signer, claims);
    const response = await postJson('/v1/auth/apple', {
      identityToken,
      authorizationCode: 'code',
      rawNonce: 'different-nonce',
    });
    expect(response.status).toBe(401);
    const body = (await response.json()) as { error: { code: string } };
    expect(body.error.code).toBe('invalid_nonce');
  });

  it('audienceが異なる場合は401', async () => {
    const claims = await defaultClaims({
      bundleId: env.APPLE_BUNDLE_ID,
      rawNonce: 'nonce',
      overrides: { aud: 'com.example.other-app' },
    });
    const identityToken = await signIdentityToken(signer, claims);
    const response = await postJson('/v1/auth/apple', {
      identityToken,
      authorizationCode: 'code',
      rawNonce: 'nonce',
    });
    expect(response.status).toBe(401);
  });

  it('期限切れのidentity tokenは401', async () => {
    const claims = await defaultClaims({
      bundleId: env.APPLE_BUNDLE_ID,
      rawNonce: 'nonce',
      overrides: { exp: Math.floor(Date.now() / 1000) - 60 },
    });
    const identityToken = await signIdentityToken(signer, claims);
    const response = await postJson('/v1/auth/apple', {
      identityToken,
      authorizationCode: 'code',
      rawNonce: 'nonce',
    });
    expect(response.status).toBe(401);
  });

  it('必須フィールドが欠けている場合は400', async () => {
    const response = await postJson('/v1/auth/apple', { identityToken: 'x' });
    expect(response.status).toBe(400);
  });
});

describe('POST /v1/auth/refresh', () => {
  it('リフレッシュトークンがローテーションされ、旧トークンは失効する', async () => {
    const signInBody = (await (await signIn()).json()) as { refreshToken: string };

    const refreshed = await postJson('/v1/auth/refresh', { refreshToken: signInBody.refreshToken });
    expect(refreshed.status).toBe(200);
    const refreshedBody = (await refreshed.json()) as { accessToken: string; refreshToken: string };
    expect(refreshedBody.refreshToken).not.toBe(signInBody.refreshToken);

    // 旧トークンは使えない
    const reused = await postJson('/v1/auth/refresh', { refreshToken: signInBody.refreshToken });
    expect(reused.status).toBe(401);

    // 新トークンは使える
    const again = await postJson('/v1/auth/refresh', { refreshToken: refreshedBody.refreshToken });
    expect(again.status).toBe(200);
  });

  it('未知のリフレッシュトークンは401', async () => {
    const response = await postJson('/v1/auth/refresh', { refreshToken: 'unknown-token' });
    expect(response.status).toBe(401);
  });
});

describe('POST /v1/auth/logout', () => {
  it('ログアウト後はリフレッシュトークンが無効になる', async () => {
    const body = (await (await signIn()).json()) as { accessToken: string; refreshToken: string };

    const logout = await postJson(
      '/v1/auth/logout',
      { refreshToken: body.refreshToken },
      { Authorization: `Bearer ${body.accessToken}` },
    );
    expect(logout.status).toBe(204);

    const refresh = await postJson('/v1/auth/refresh', { refreshToken: body.refreshToken });
    expect(refresh.status).toBe(401);
  });

  it('アクセストークンなしのログアウトは401', async () => {
    const response = await postJson('/v1/auth/logout', { refreshToken: 'x' });
    expect(response.status).toBe(401);
  });
});

describe('レート制限', () => {
  it('同一IPからの連打は429になる', async () => {
    const ip = '203.0.113.99';
    let lastStatus = 0;
    for (let i = 0; i < 11; i++) {
      const response = await postJson('/v1/auth/refresh', { refreshToken: 'does-not-matter' }, {}, ip);
      lastStatus = response.status;
    }
    expect(lastStatus).toBe(429);
  });
});
