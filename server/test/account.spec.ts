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

async function signIn() {
  const rawNonce = 'account-test-nonce';
  const claims = await defaultClaims({ bundleId: env.APPLE_BUNDLE_ID, rawNonce, subject: 'apple-subject-delete-me' });
  const identityToken = await signIdentityToken(signer, claims);
  const response = await app.request(
    '/v1/auth/apple',
    {
      method: 'POST',
      headers: { 'content-type': 'application/json' },
      body: JSON.stringify({ identityToken, authorizationCode: 'code', rawNonce }),
    },
    env,
  );
  return (await response.json()) as { accessToken: string; refreshToken: string; user: { id: string } };
}

describe('DELETE /v1/account', () => {
  it('アカウント削除でセッションが消えユーザーが匿名化される', async () => {
    const session = await signIn();

    const response = await app.request(
      '/v1/account',
      { method: 'DELETE', headers: { Authorization: `Bearer ${session.accessToken}` } },
      env,
    );
    expect(response.status).toBe(204);

    // users 行は匿名化されて deleted_at が付く
    const user = await env.DB.prepare('SELECT apple_subject, anonymous_handle, deleted_at FROM users WHERE id = ?')
      .bind(session.user.id)
      .first<{ apple_subject: string; anonymous_handle: string | null; deleted_at: string | null }>();
    expect(user?.deleted_at).not.toBeNull();
    expect(user?.apple_subject).toBe(`deleted:${session.user.id}`);
    expect(user?.anonymous_handle).toBeNull();

    // セッションは削除済み
    const sessionCount = await env.DB.prepare('SELECT COUNT(*) AS count FROM auth_sessions WHERE user_id = ?')
      .bind(session.user.id)
      .first<{ count: number }>();
    expect(sessionCount?.count).toBe(0);

    // 削除後はアクセストークンもリフレッシュトークンも使えない
    const authedAgain = await app.request(
      '/v1/account',
      { method: 'DELETE', headers: { Authorization: `Bearer ${session.accessToken}` } },
      env,
    );
    expect(authedAgain.status).toBe(401);

    const refresh = await app.request(
      '/v1/auth/refresh',
      {
        method: 'POST',
        headers: { 'content-type': 'application/json' },
        body: JSON.stringify({ refreshToken: session.refreshToken }),
      },
      env,
    );
    expect(refresh.status).toBe(401);
  });

  it('削除後の再サインインは新規ユーザーになる', async () => {
    const first = await signIn();
    await app.request(
      '/v1/account',
      { method: 'DELETE', headers: { Authorization: `Bearer ${first.accessToken}` } },
      env,
    );

    const second = await signIn();
    expect(second.user.id).not.toBe(first.user.id);
  });

  it('アクセストークンなしでは401', async () => {
    const response = await app.request('/v1/account', { method: 'DELETE' }, env);
    expect(response.status).toBe(401);
  });
});
