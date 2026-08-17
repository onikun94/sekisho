# Sekisho API (Cloudflare Workers)

`docs/cloudflare-implementation-plan.md` の Phase 1(Cloudflare基盤)の実装。
Hono + TypeScript の Worker API で、D1・Sign in with Apple 検証・独自セッション管理・レート制限を含む。
D1 スキーマは匿名週間リーグ(宿場)方針(2026-08-17改定)に対応している。

## 構成

| パス | 内容 |
|---|---|
| `src/index.ts` | Hono アプリ本体(ルーティング、エラーハンドリング) |
| `src/routes/auth.ts` | `POST /v1/auth/apple` `/refresh` `/logout` |
| `src/routes/account.ts` | `DELETE /v1/account` |
| `src/lib/apple.ts` | identity token 検証(JWKS)、client_secret 生成、トークン交換・失効 |
| `src/lib/session.ts` | アクセストークン(JWT HS256, 15分)とリフレッシュトークン(60日、ハッシュのみD1保存、ローテーション) |
| `src/middleware/` | Bearer 認証、IPキーのレート制限 |
| `migrations/` | D1 マイグレーション(計画§4の全テーブル) |
| `test/` | vitest-pool-workers による自動テスト |

## 開発

```bash
npm install
cp .dev.vars.example .dev.vars   # AUTH_JWT_SECRET を設定
npm run db:migrate:local
npm run dev                      # http://localhost:8787
npm test
npm run typecheck
```

テストでは Apple の JWKS をモックし、テスト内で生成した RSA 鍵で identity token を署名して検証フロー全体を通している。

## 初回デプロイ手順(リモート操作、実行前に要確認)

1. D1 作成(APAC location hint、計画§Phase 1):
   ```bash
   npx wrangler d1 create sekisho-db-dev --location=apac
   npx wrangler d1 create sekisho-db --location=apac
   ```
   返ってきた `database_id` を `wrangler.jsonc` の各環境に反映する。
2. マイグレーション適用: `npm run db:migrate:dev` / `npm run db:migrate:production`
3. Secrets 登録:
   ```bash
   npx wrangler secret put AUTH_JWT_SECRET                    # development
   npx wrangler secret put AUTH_JWT_SECRET --env production
   # Apple トークン失効処理用(App Store Connect の p8 キー)
   npx wrangler secret put APPLE_TEAM_ID --env production
   npx wrangler secret put APPLE_KEY_ID --env production
   npx wrangler secret put APPLE_PRIVATE_KEY --env production
   ```
4. デプロイ: `npx wrangler deploy`(development) / `npm run deploy:production`

## API 契約

エラーは全エンドポイント共通で `{"error": {"code": string, "message": string}}`。

### POST /v1/auth/apple
iOS は rawNonce を生成し、`ASAuthorizationAppleIDRequest.nonce` に SHA-256(rawNonce) を設定する。
サーバーは署名・iss・aud(bundle id)・exp・nonce を検証する。
自由入力の表示名は受け付けない。`anonymousHandle` はリーグ参加時にサーバーが安全な語彙から生成する(Phase 2)ため、Phase 1 では null。

```json
// リクエスト
{ "identityToken": "...", "authorizationCode": "...", "rawNonce": "..." }
// レスポンス 200
{ "accessToken": "...", "accessTokenExpiresAt": "ISO8601", "refreshToken": "...", "user": { "id": "...", "anonymousHandle": null } }
```

### POST /v1/auth/refresh
`{ "refreshToken": "..." }` → 200(新しいトークン一式。旧リフレッシュトークンは即失効)

### POST /v1/auth/logout(Bearer 必須)
`{ "refreshToken": "..." }` → 204

### DELETE /v1/account(Bearer 必須)
→ 204。Apple の refresh token を失効させ、セッション・デバイストークン等を削除し、
users 行は外部キー整合性のため匿名化して残す(apple_subject 破棄・PII 削除)。

## 設計メモ

- 計画§4 からの追加: `users.apple_refresh_token`。アカウント削除時の Apple トークン失効(計画§3)に必要。
- リーグ関連テーブル(`leagues` / `league_members` / `daily_results`)はスキーマのみ作成済みで、
  週次自動編成・得点算出・standings API は Phase 2 で実装する。
  得点はサーバー算出とし、クライアント指定値を受け付けない(計画§7)。
- Apple 系 secrets が未設定でもサインイン検証は動作する(トークン交換・失効のみスキップ、production では error ログ)。
- レート制限(unsafe binding)は連打抑制のみに使用。AI 利用回数などの厳密な管理は D1 で行う(計画§7)。
  認証前エンドポイントは IP キー(10回/60秒)、認証後エンドポイントはユーザーIDキー(120回/60秒)。
- アクセストークンは 15 分で失効するため、認可の取り消し(ログアウト・削除)はリフレッシュ拒否と
  認証ミドルウェアの deleted_at チェックで担保する。

## iOS 側クライアント

`Sources/SekishoApp/Services/Backend/` に対応する Swift 実装がある
(`SekishoAPIClient` プロトコル + Live/Mock 実装、`KeychainTokenStore`、`BackendSessionManager`、`AppleSignInNonce`)。
