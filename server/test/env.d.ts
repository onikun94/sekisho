import type { Env as AppEnv } from '../src/env';
import type { D1Migration } from 'cloudflare:test';

/**
 * テスト実行時の `env`(cloudflare:workers)の型を、アプリの Env と
 * vitest.config.ts で注入するテスト専用バインディングで補強する。
 */
declare global {
  namespace Cloudflare {
    interface Env extends AppEnv {
      TEST_MIGRATIONS: D1Migration[];
    }
  }
}

export {};
