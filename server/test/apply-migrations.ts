import { applyD1Migrations } from 'cloudflare:test';
import { env } from 'cloudflare:workers';

// 各テスト実行前に D1 マイグレーションを適用する(vitest.config.ts の setupFiles)。
await applyD1Migrations(env.DB, env.TEST_MIGRATIONS);
