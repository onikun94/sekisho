import type { MiddlewareHandler } from 'hono';
import { ApiError } from '../errors';
import type { Env, RateLimiterBinding } from '../env';
import type { AuthVariables } from './auth';

const warnedMissingBindings = new Set<string>();

/**
 * Workers Rate Limiting binding による連打抑制。
 * binding が未設定の環境(ローカルテスト等)では警告だけ出して素通しする。
 * 計画どおり、正確な利用回数の管理には使わない(それはD1で行う)。
 */
async function enforceLimit(limiter: RateLimiterBinding | undefined, bindingName: string, key: string): Promise<void> {
  if (!limiter) {
    if (!warnedMissingBindings.has(bindingName)) {
      warnedMissingBindings.add(bindingName);
      console.warn(`${bindingName} binding is not configured; rate limiting is disabled`);
    }
    return;
  }
  const { success } = await limiter.limit({ key });
  if (!success) {
    throw new ApiError(429, 'rate_limited', 'too many requests');
  }
}

/** 認証前エンドポイント用: 接続元IPをキーにする。 */
export function rateLimitByIp(): MiddlewareHandler<{ Bindings: Env }> {
  return async (c, next) => {
    const key = c.req.header('CF-Connecting-IP') ?? 'unknown';
    await enforceLimit(c.env.AUTH_RATE_LIMITER, 'AUTH_RATE_LIMITER', key);
    return next();
  };
}

/** 認証後エンドポイント用: ユーザーIDをキーにする。requireAuth の後に配置すること。 */
export function rateLimitByUser(): MiddlewareHandler<{ Bindings: Env; Variables: AuthVariables }> {
  return async (c, next) => {
    await enforceLimit(c.env.USER_RATE_LIMITER, 'USER_RATE_LIMITER', c.get('userId'));
    return next();
  };
}
