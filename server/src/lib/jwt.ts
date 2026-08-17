import {
  base64UrlDecode,
  base64UrlDecodeToString,
  base64UrlEncode,
  base64UrlEncodeString,
  pemToDer,
  utf8Bytes,
} from './encoding';

export interface JwtParts {
  header: Record<string, unknown>;
  payload: Record<string, unknown>;
  signature: Uint8Array;
  /** 署名対象の `<header>.<payload>` 部分。 */
  signingInput: string;
}

/** JWT を検証せずに分解する。形式不正なら null。 */
export function decodeJwt(token: string): JwtParts | null {
  const segments = token.split('.');
  if (segments.length !== 3) return null;
  const [headerB64, payloadB64, signatureB64] = segments as [string, string, string];
  try {
    return {
      header: JSON.parse(base64UrlDecodeToString(headerB64)),
      payload: JSON.parse(base64UrlDecodeToString(payloadB64)),
      signature: base64UrlDecode(signatureB64),
      signingInput: `${headerB64}.${payloadB64}`,
    };
  } catch {
    return null;
  }
}

async function hmacKey(secret: string, usage: 'sign' | 'verify'): Promise<CryptoKey> {
  return crypto.subtle.importKey('raw', utf8Bytes(secret), { name: 'HMAC', hash: 'SHA-256' }, false, [usage]);
}

/** HS256 で JWT を署名する。 */
export async function signJwtHS256(payload: Record<string, unknown>, secret: string): Promise<string> {
  const signingInput = `${base64UrlEncodeString(JSON.stringify({ alg: 'HS256', typ: 'JWT' }))}.${base64UrlEncodeString(JSON.stringify(payload))}`;
  const key = await hmacKey(secret, 'sign');
  const signature = await crypto.subtle.sign('HMAC', key, utf8Bytes(signingInput));
  return `${signingInput}.${base64UrlEncode(signature)}`;
}

/**
 * HS256 JWT を検証し payload を返す。署名不一致・期限切れ・形式不正は null。
 */
export async function verifyJwtHS256(token: string, secret: string): Promise<Record<string, unknown> | null> {
  const parts = decodeJwt(token);
  if (!parts || parts.header['alg'] !== 'HS256') return null;
  const key = await hmacKey(secret, 'verify');
  const valid = await crypto.subtle.verify('HMAC', key, parts.signature, utf8Bytes(parts.signingInput));
  if (!valid) return null;
  const exp = parts.payload['exp'];
  if (typeof exp !== 'number' || exp * 1000 <= Date.now()) return null;
  return parts.payload;
}

/** ES256(P-256)で JWT を署名する。Apple の client_secret 生成に使う。 */
export async function signJwtES256(
  header: Record<string, unknown>,
  payload: Record<string, unknown>,
  privateKeyPem: string,
): Promise<string> {
  const key = await crypto.subtle.importKey('pkcs8', pemToDer(privateKeyPem), { name: 'ECDSA', namedCurve: 'P-256' }, false, [
    'sign',
  ]);
  const signingInput = `${base64UrlEncodeString(JSON.stringify({ alg: 'ES256', typ: 'JWT', ...header }))}.${base64UrlEncodeString(JSON.stringify(payload))}`;
  // WebCrypto の ECDSA 署名は raw r||s 形式で、JWS ES256 の要求形式と一致する。
  const signature = await crypto.subtle.sign({ name: 'ECDSA', hash: 'SHA-256' }, key, utf8Bytes(signingInput));
  return `${signingInput}.${base64UrlEncode(signature)}`;
}
