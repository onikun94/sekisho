import { base64UrlEncode, base64UrlEncodeString, sha256Hex, utf8Bytes } from '../../src/lib/encoding';

export const TEST_KID = 'sekisho-test-key';

export interface AppleTestSigner {
  privateKey: CryptoKey;
  /** Apple JWKS エンドポイントのモックレスポンス。 */
  jwks: { keys: Array<JsonWebKey & { kid: string }> };
}

/** Apple の署名鍵を模した RSA 鍵ペアを生成する。 */
export async function createAppleTestSigner(): Promise<AppleTestSigner> {
  const keyPair = (await crypto.subtle.generateKey(
    {
      name: 'RSASSA-PKCS1-v1_5',
      modulusLength: 2048,
      publicExponent: new Uint8Array([1, 0, 1]),
      hash: 'SHA-256',
    },
    true,
    ['sign', 'verify'],
  )) as CryptoKeyPair;
  const publicJwk = (await crypto.subtle.exportKey('jwk', keyPair.publicKey)) as JsonWebKey;
  return {
    privateKey: keyPair.privateKey,
    jwks: { keys: [{ ...publicJwk, kid: TEST_KID, use: 'sig', alg: 'RS256' }] },
  };
}

/** identity token の claim を組み立てて RS256 で署名する。 */
export async function signIdentityToken(
  signer: AppleTestSigner,
  payload: Record<string, unknown>,
): Promise<string> {
  const signingInput = `${base64UrlEncodeString(JSON.stringify({ alg: 'RS256', kid: TEST_KID }))}.${base64UrlEncodeString(JSON.stringify(payload))}`;
  const signature = await crypto.subtle.sign('RSASSA-PKCS1-v1_5', signer.privateKey, utf8Bytes(signingInput));
  return `${signingInput}.${base64UrlEncode(signature)}`;
}

/** 正常系の identity token claim を生成する。overrides で異常系を作る。 */
export async function defaultClaims(options: {
  bundleId: string;
  rawNonce: string;
  subject?: string;
  overrides?: Record<string, unknown>;
}): Promise<Record<string, unknown>> {
  const nowSeconds = Math.floor(Date.now() / 1000);
  return {
    iss: 'https://appleid.apple.com',
    aud: options.bundleId,
    sub: options.subject ?? 'apple-subject-0001',
    exp: nowSeconds + 600,
    iat: nowSeconds,
    nonce: await sha256Hex(options.rawNonce),
    nonce_supported: true,
    ...options.overrides,
  };
}
