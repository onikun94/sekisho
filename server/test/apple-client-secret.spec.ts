import { describe, expect, it } from 'vitest';
import { generateAppleClientSecret } from '../src/lib/apple';
import { base64UrlDecode, base64UrlDecodeToString } from '../src/lib/encoding';

/** テスト用に P-256 鍵ペアを生成し、秘密鍵を PKCS#8 PEM で返す。 */
async function generateP256KeyPair(): Promise<{ privateKeyPem: string; publicKey: CryptoKey }> {
  const keyPair = (await crypto.subtle.generateKey({ name: 'ECDSA', namedCurve: 'P-256' }, true, [
    'sign',
    'verify',
  ])) as CryptoKeyPair;
  const pkcs8 = new Uint8Array((await crypto.subtle.exportKey('pkcs8', keyPair.privateKey)) as ArrayBuffer);
  let binary = '';
  for (const byte of pkcs8) {
    binary += String.fromCharCode(byte);
  }
  const pem = `-----BEGIN PRIVATE KEY-----\n${btoa(binary)}\n-----END PRIVATE KEY-----`;
  return { privateKeyPem: pem, publicKey: keyPair.publicKey };
}

describe('generateAppleClientSecret', () => {
  it('検証可能なES256 JWTを生成しclaimが正しい', async () => {
    const { privateKeyPem, publicKey } = await generateP256KeyPair();
    const nowSeconds = Math.floor(Date.now() / 1000);
    const token = await generateAppleClientSecret(
      {
        teamId: 'TEAM123456',
        keyId: 'KEY1234567',
        privateKeyPem,
        clientId: 'com.onikun94.sekisho',
      },
      nowSeconds,
    );

    const [headerB64, payloadB64, signatureB64] = token.split('.') as [string, string, string];
    const header = JSON.parse(base64UrlDecodeToString(headerB64));
    expect(header).toMatchObject({ alg: 'ES256', kid: 'KEY1234567' });

    const payload = JSON.parse(base64UrlDecodeToString(payloadB64));
    expect(payload).toMatchObject({
      iss: 'TEAM123456',
      aud: 'https://appleid.apple.com',
      sub: 'com.onikun94.sekisho',
      iat: nowSeconds,
    });
    expect(payload.exp).toBeGreaterThan(nowSeconds);

    const valid = await crypto.subtle.verify(
      { name: 'ECDSA', hash: 'SHA-256' },
      publicKey,
      base64UrlDecode(signatureB64),
      new TextEncoder().encode(`${headerB64}.${payloadB64}`),
    );
    expect(valid).toBe(true);
  });
});
