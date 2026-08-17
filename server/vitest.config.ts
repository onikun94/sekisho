import path from 'node:path';
import { cloudflareTest, readD1Migrations } from '@cloudflare/vitest-pool-workers';
import { defineConfig } from 'vitest/config';

export default defineConfig({
  plugins: [
    cloudflareTest(async () => {
      const migrations = await readD1Migrations(path.join(import.meta.dirname, 'migrations'));
      return {
        wrangler: { configPath: './wrangler.jsonc' },
        miniflare: {
          bindings: {
            // テストのsetupファイルでD1へ適用するマイグレーション(テスト専用バインディング)。
            TEST_MIGRATIONS: migrations,
            // 本番では Workers Secrets で注入する値のテスト用ダミー。
            AUTH_JWT_SECRET: 'test-jwt-secret',
          },
        },
      };
    }),
  ],
  test: {
    setupFiles: ['./test/apply-migrations.ts'],
  },
});
