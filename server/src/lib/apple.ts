import { sha256Hex } from './encoding';
import { decodeJwt, signJwtES256 } from './jwt';
import { unauthorized } from '../errors';

export const APPLE_ISSUER = 'https://appleid.apple.com';
const JWKS_URL = 'https://appleid.apple.com/auth/keys';
const TOKEN_URL = 'https://appleid.apple.com/auth/token';
const REVOKE_URL = 'https://appleid.apple.com/auth/revoke';
const JWKS_CACHE_TTL_MS = 60 * 60 * 1000;

interface AppleJwk extends JsonWebKey {
  kid: string;
}

let jwksCache: { keys: AppleJwk[]; fetchedAt: number } | null = null;

async function fetchAppleJwks(fetcher: typeof fetch): Promise<AppleJwk[]> {
  if (jwksCache && Date.now() - jwksCache.fetchedAt < JWKS_CACHE_TTL_MS) {
    return jwksCache.keys;
  }
  const response = await fetcher(JWKS_URL);
  if (!response.ok) {
    throw new Error(`Apple JWKS fetch failed: ${response.status}`);
  }
  const body = (await response.json()) as { keys: AppleJwk[] };
  jwksCache = { keys: body.keys, fetchedAt: Date.now() };
  return body.keys;
}

/** テスト用: JWKS のモジュールキャッシュを破棄する。 */
export function clearAppleJwksCache(): void {
  jwksCache = null;
}

export interface VerifiedAppleIdentity {
  /** Apple 側のユーザー識別子(users.apple_subject に対応)。 */
  subject: string;
  email?: string;
}

/**
 * Sign in with Apple の identity token を検証する。
 * 署名(Apple JWKS)・issuer・audience・有効期限・nonce をすべて確認する。
 * iOS 側は rawNonce の SHA-256 を ASAuthorizationAppleIDRequest.nonce に設定している前提で、
 * サーバーは sha256(rawNonce) と token の nonce claim を照合する。
 */
export async function verifyAppleIdentityToken(options: {
  identityToken: string;
  rawNonce: string;
  bundleId: string;
  fetcher?: typeof fetch;
}): Promise<VerifiedAppleIdentity> {
  const fetcher = options.fetcher ?? fetch;
  const parts = decodeJwt(options.identityToken);
  if (!parts || parts.header['alg'] !== 'RS256' || typeof parts.header['kid'] !== 'string') {
    throw unauthorized('invalid_token', 'identity token is malformed');
  }

  const keys = await fetchAppleJwks(fetcher);
  const jwk = keys.find((key) => key.kid === parts.header['kid']);
  if (!jwk) {
    throw unauthorized('invalid_token', 'signing key not found');
  }

  const publicKey = await crypto.subtle.importKey(
    'jwk',
    jwk,
    { name: 'RSASSA-PKCS1-v1_5', hash: 'SHA-256' },
    false,
    ['verify'],
  );
  const valid = await crypto.subtle.verify(
    'RSASSA-PKCS1-v1_5',
    publicKey,
    parts.signature,
    new TextEncoder().encode(parts.signingInput),
  );
  if (!valid) {
    throw unauthorized('invalid_token', 'signature verification failed');
  }

  const { payload } = parts;
  if (payload['iss'] !== APPLE_ISSUER) {
    throw unauthorized('invalid_token', 'unexpected issuer');
  }
  if (payload['aud'] !== options.bundleId) {
    throw unauthorized('invalid_token', 'unexpected audience');
  }
  const exp = payload['exp'];
  if (typeof exp !== 'number' || exp * 1000 <= Date.now()) {
    throw unauthorized('invalid_token', 'token expired');
  }
  const expectedNonce = await sha256Hex(options.rawNonce);
  if (payload['nonce'] !== expectedNonce) {
    throw unauthorized('invalid_nonce', 'nonce mismatch');
  }
  const subject = payload['sub'];
  if (typeof subject !== 'string' || subject.length === 0) {
    throw unauthorized('invalid_token', 'missing subject');
  }

  return {
    subject,
    email: typeof payload['email'] === 'string' ? payload['email'] : undefined,
  };
}

export interface AppleClientConfig {
  teamId: string;
  keyId: string;
  privateKeyPem: string;
  /** iOS ネイティブアプリでは bundle id が client_id になる。 */
  clientId: string;
}

/** Apple のトークンAPI用 client_secret(ES256 JWT)を生成する。 */
export async function generateAppleClientSecret(config: AppleClientConfig, nowSeconds = Math.floor(Date.now() / 1000)): Promise<string> {
  return signJwtES256(
    { kid: config.keyId },
    {
      iss: config.teamId,
      iat: nowSeconds,
      exp: nowSeconds + 60 * 60, // 生成の都度使い捨てるため短命でよい
      aud: APPLE_ISSUER,
      sub: config.clientId,
    },
    config.privateKeyPem,
  );
}

/**
 * authorization code を Apple の refresh token へ交換する。
 * アカウント削除時のトークン失効処理に使うため users.apple_refresh_token に保存する。
 */
export async function exchangeAuthorizationCode(options: {
  code: string;
  config: AppleClientConfig;
  fetcher?: typeof fetch;
}): Promise<{ refreshToken: string } | null> {
  const fetcher = options.fetcher ?? fetch;
  const clientSecret = await generateAppleClientSecret(options.config);
  const response = await fetcher(TOKEN_URL, {
    method: 'POST',
    headers: { 'content-type': 'application/x-www-form-urlencoded' },
    body: new URLSearchParams({
      grant_type: 'authorization_code',
      code: options.code,
      client_id: options.config.clientId,
      client_secret: clientSecret,
    }),
  });
  if (!response.ok) {
    console.warn(`Apple token exchange failed: ${response.status}`);
    return null;
  }
  const body = (await response.json()) as { refresh_token?: string };
  return body.refresh_token ? { refreshToken: body.refresh_token } : null;
}

/** Apple の refresh token を失効させる(アカウント削除時)。 */
export async function revokeAppleRefreshToken(options: {
  refreshToken: string;
  config: AppleClientConfig;
  fetcher?: typeof fetch;
}): Promise<boolean> {
  const fetcher = options.fetcher ?? fetch;
  const clientSecret = await generateAppleClientSecret(options.config);
  const response = await fetcher(REVOKE_URL, {
    method: 'POST',
    headers: { 'content-type': 'application/x-www-form-urlencoded' },
    body: new URLSearchParams({
      token: options.refreshToken,
      token_type_hint: 'refresh_token',
      client_id: options.config.clientId,
      client_secret: clientSecret,
    }),
  });
  if (!response.ok) {
    console.warn(`Apple token revoke failed: ${response.status}`);
  }
  return response.ok;
}

/** Env から AppleClientConfig を構成する。secrets 未設定なら null(交換・失効処理はスキップ)。 */
export function appleClientConfigFromEnv(env: {
  APPLE_TEAM_ID?: string;
  APPLE_KEY_ID?: string;
  APPLE_PRIVATE_KEY?: string;
  APPLE_BUNDLE_ID: string;
}): AppleClientConfig | null {
  if (!env.APPLE_TEAM_ID || !env.APPLE_KEY_ID || !env.APPLE_PRIVATE_KEY) {
    return null;
  }
  return {
    teamId: env.APPLE_TEAM_ID,
    keyId: env.APPLE_KEY_ID,
    privateKeyPem: env.APPLE_PRIVATE_KEY,
    clientId: env.APPLE_BUNDLE_ID,
  };
}
