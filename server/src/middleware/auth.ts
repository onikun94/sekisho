import type { MiddlewareHandler } from 'hono';
import { verifyAccessToken } from '../lib/session';
import { unauthorized } from '../errors';
import type { Env } from '../env';

export interface AuthVariables {
  userId: string;
  sessionId: string;
}

/**
 * Bearer アクセストークンを検証し、userId / sessionId をコンテキストへ格納する。
 * 削除済みユーザーのトークンは拒否する。
 */
export const requireAuth: MiddlewareHandler<{ Bindings: Env; Variables: AuthVariables }> = async (c, next) => {
  const header = c.req.header('Authorization');
  if (!header?.startsWith('Bearer ')) {
    throw unauthorized();
  }
  const { userId, sessionId } = await verifyAccessToken(c.env, header.slice('Bearer '.length));

  const user = await c.env.DB.prepare('SELECT id FROM users WHERE id = ? AND deleted_at IS NULL')
    .bind(userId)
    .first<{ id: string }>();
  if (!user) {
    throw unauthorized();
  }

  c.set('userId', userId);
  c.set('sessionId', sessionId);
  await next();
};
