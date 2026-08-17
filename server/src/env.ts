/**
 * Worker の環境バインディング。
 * wrangler.jsonc の vars / d1_databases / secrets と対応する。
 */
export interface Env {
  DB: D1Database;
  ENVIRONMENT: 'development' | 'production';
  /** Sign in with Apple の audience 検証に使う iOS アプリの bundle id。 */
  APPLE_BUNDLE_ID: string;

  // --- Secrets (wrangler secret put / .dev.vars) ---
  /** アクセストークン(JWT HS256)の署名鍵。 */
  AUTH_JWT_SECRET: string;
  /** 以下3つは Apple トークン交換・失効処理用。未設定の場合その処理はスキップされる。 */
  APPLE_TEAM_ID?: string;
  APPLE_KEY_ID?: string;
  /** PKCS#8 PEM 形式の p8 秘密鍵。 */
  APPLE_PRIVATE_KEY?: string;

  // --- Rate Limiting bindings (unsafe binding、未設定環境ではundefined) ---
  /** 認証前エンドポイント用(IPキー)。 */
  AUTH_RATE_LIMITER?: RateLimiterBinding;
  /** 認証後エンドポイント用(ユーザーIDキー)。 */
  USER_RATE_LIMITER?: RateLimiterBinding;
}

/** Workers Rate Limiting binding の最小インターフェイス。 */
export interface RateLimiterBinding {
  limit(options: { key: string }): Promise<{ success: boolean }>;
}
