import { Hono } from 'hono';
import { appleClientConfigFromEnv, revokeAppleRefreshToken } from '../lib/apple';
import { requireAuth, type AuthVariables } from '../middleware/auth';
import { rateLimitByUser } from '../middleware/rate-limit';
import type { Env } from '../env';

export const accountRoutes = new Hono<{ Bindings: Env; Variables: AuthVariables }>();

/**
 * アカウント削除。
 * 1. Apple の refresh token を失効させる(取得済みの場合)。
 * 2. セッション・通知トークンなどユーザーデータを削除する。
 * 3. users 行は外部キー整合性のため匿名化して残す(apple_subject を破棄し PII を消す)。
 * リーグはサーバーが自動編成するため、所有権の引き継ぎ処理は不要。
 */
accountRoutes.delete('/', requireAuth, rateLimitByUser(), async (c) => {
  const userId = c.get('userId');

  const user = await c.env.DB.prepare('SELECT apple_refresh_token FROM users WHERE id = ?')
    .bind(userId)
    .first<{ apple_refresh_token: string | null }>();

  const appleConfig = appleClientConfigFromEnv(c.env);
  if (user?.apple_refresh_token && appleConfig) {
    try {
      await revokeAppleRefreshToken({ refreshToken: user.apple_refresh_token, config: appleConfig });
    } catch (error) {
      // 失効に失敗してもアカウント削除自体は続行する(Apple側で再試行手段がないため)。
      console.warn('Apple token revocation failed during account deletion', error);
    }
  }

  const now = new Date().toISOString();
  await c.env.DB.batch([
    c.env.DB.prepare('DELETE FROM auth_sessions WHERE user_id = ?').bind(userId),
    c.env.DB.prepare('DELETE FROM device_tokens WHERE user_id = ?').bind(userId),
    c.env.DB.prepare('DELETE FROM ai_insights WHERE user_id = ?').bind(userId),
    c.env.DB.prepare('DELETE FROM subscription_states WHERE user_id = ?').bind(userId),
    c.env.DB.prepare('DELETE FROM daily_results WHERE user_id = ?').bind(userId),
    c.env.DB.prepare('DELETE FROM league_members WHERE user_id = ?').bind(userId),
    c.env.DB.prepare(
      "UPDATE users SET apple_subject = 'deleted:' || id, anonymous_handle = NULL, mascot_id = NULL, timezone = NULL, goal_tier = NULL, apple_refresh_token = NULL, deleted_at = ? WHERE id = ?",
    ).bind(now, userId),
  ]);

  return c.body(null, 204);
});
