import { describe, expect, it } from 'vitest';
import { Hono } from 'hono';
import { rateLimitByUser } from '../src/middleware/rate-limit';
import { ApiError } from '../src/errors';
import type { Env } from '../src/env';
import type { AuthVariables } from '../src/middleware/auth';

// requireAuth 相当のスタブと組み合わせて、ミドルウェア単体の挙動を検証する。
function buildApp(limitResult: { success: boolean }, recordedKeys: string[]) {
  const app = new Hono<{ Bindings: Env; Variables: AuthVariables }>();
  app.onError((error, c) =>
    error instanceof ApiError
      ? c.json({ error: { code: error.code } }, error.status as 429)
      : c.json({ error: { code: 'internal_error' } }, 500),
  );
  app.use('*', async (c, next) => {
    c.set('userId', 'user-42');
    c.set('sessionId', 'session-1');
    await next();
  });
  app.get('/protected', rateLimitByUser(), (c) => c.json({ ok: true }));
  return {
    app,
    env: {
      USER_RATE_LIMITER: {
        limit: async ({ key }: { key: string }) => {
          recordedKeys.push(key);
          return limitResult;
        },
      },
    } as unknown as Env,
  };
}

describe('rateLimitByUser', () => {
  it('ユーザーIDをキーとしてbindingを呼び、成功なら通過する', async () => {
    const keys: string[] = [];
    const { app, env } = buildApp({ success: true }, keys);
    const response = await app.request('/protected', {}, env);
    expect(response.status).toBe(200);
    expect(keys).toEqual(['user-42']);
  });

  it('制限超過なら429を返す', async () => {
    const keys: string[] = [];
    const { app, env } = buildApp({ success: false }, keys);
    const response = await app.request('/protected', {}, env);
    expect(response.status).toBe(429);
    const body = (await response.json()) as { error: { code: string } };
    expect(body.error.code).toBe('rate_limited');
  });

  it('bindingが未設定なら素通しする', async () => {
    const app = new Hono<{ Bindings: Env; Variables: AuthVariables }>();
    app.use('*', async (c, next) => {
      c.set('userId', 'user-42');
      c.set('sessionId', 'session-1');
      await next();
    });
    app.get('/protected', rateLimitByUser(), (c) => c.json({ ok: true }));
    const response = await app.request('/protected', {}, {} as Env);
    expect(response.status).toBe(200);
  });
});
