import { randomToken, sha256Hex } from './encoding';
import { signJwtHS256, verifyJwtHS256 } from './jwt';
import { unauthorized } from '../errors';
import type { Env } from '../env';

export const ACCESS_TOKEN_TTL_SECONDS = 15 * 60;
const REFRESH_TOKEN_TTL_DAYS = 60;
const JWT_ISSUER = 'sekisho-api';
const JWT_AUDIENCE = 'sekisho-ios';

export interface IssuedTokens {
  accessToken: string;
  /** ISO 8601 (UTC) */
  accessTokenExpiresAt: string;
  refreshToken: string;
}

export async function issueAccessToken(env: Env, userId: string, sessionId: string): Promise<{ token: string; expiresAt: string }> {
  const nowSeconds = Math.floor(Date.now() / 1000);
  const exp = nowSeconds + ACCESS_TOKEN_TTL_SECONDS;
  const token = await signJwtHS256(
    { iss: JWT_ISSUER, aud: JWT_AUDIENCE, sub: userId, sid: sessionId, iat: nowSeconds, exp },
    env.AUTH_JWT_SECRET,
  );
  return { token, expiresAt: new Date(exp * 1000).toISOString() };
}

/** アクセストークンを検証し、userId / sessionId を返す。失敗時は 401 を投げる。 */
export async function verifyAccessToken(env: Env, token: string): Promise<{ userId: string; sessionId: string }> {
  const payload = await verifyJwtHS256(token, env.AUTH_JWT_SECRET);
  if (!payload || payload['iss'] !== JWT_ISSUER || payload['aud'] !== JWT_AUDIENCE) {
    throw unauthorized();
  }
  const userId = payload['sub'];
  const sessionId = payload['sid'];
  if (typeof userId !== 'string' || typeof sessionId !== 'string') {
    throw unauthorized();
  }
  return { userId, sessionId };
}

/** 新しいセッションを作成し、アクセストークンとリフレッシュトークンを発行する。 */
export async function createSession(env: Env, userId: string): Promise<IssuedTokens> {
  const sessionId = crypto.randomUUID();
  const refreshToken = randomToken(32);
  const now = new Date();
  const expiresAt = new Date(now.getTime() + REFRESH_TOKEN_TTL_DAYS * 24 * 60 * 60 * 1000);

  await env.DB.prepare(
    'INSERT INTO auth_sessions (id, user_id, refresh_token_hash, expires_at, created_at) VALUES (?, ?, ?, ?, ?)',
  )
    .bind(sessionId, userId, await sha256Hex(refreshToken), expiresAt.toISOString(), now.toISOString())
    .run();

  const access = await issueAccessToken(env, userId, sessionId);
  return { accessToken: access.token, accessTokenExpiresAt: access.expiresAt, refreshToken };
}

/**
 * リフレッシュトークンをローテーションする。
 * 提示されたトークンのハッシュが有効なセッションと一致した場合のみ、新しいトークン一式を返す。
 */
export async function rotateSession(env: Env, refreshToken: string): Promise<IssuedTokens & { userId: string }> {
  const hash = await sha256Hex(refreshToken);
  const nowIso = new Date().toISOString();
  const session = await env.DB.prepare(
    'SELECT id, user_id FROM auth_sessions WHERE refresh_token_hash = ? AND revoked_at IS NULL AND expires_at > ?',
  )
    .bind(hash, nowIso)
    .first<{ id: string; user_id: string }>();
  if (!session) {
    throw unauthorized('invalid_refresh_token');
  }

  const newRefreshToken = randomToken(32);
  const newExpiresAt = new Date(Date.now() + REFRESH_TOKEN_TTL_DAYS * 24 * 60 * 60 * 1000);
  await env.DB.prepare('UPDATE auth_sessions SET refresh_token_hash = ?, expires_at = ? WHERE id = ?')
    .bind(await sha256Hex(newRefreshToken), newExpiresAt.toISOString(), session.id)
    .run();

  const access = await issueAccessToken(env, session.user_id, session.id);
  return {
    accessToken: access.token,
    accessTokenExpiresAt: access.expiresAt,
    refreshToken: newRefreshToken,
    userId: session.user_id,
  };
}

/** 指定ユーザーのリフレッシュトークンを失効させる。 */
export async function revokeSession(env: Env, userId: string, refreshToken: string): Promise<void> {
  const hash = await sha256Hex(refreshToken);
  await env.DB.prepare(
    'UPDATE auth_sessions SET revoked_at = ? WHERE refresh_token_hash = ? AND user_id = ? AND revoked_at IS NULL',
  )
    .bind(new Date().toISOString(), hash, userId)
    .run();
}
