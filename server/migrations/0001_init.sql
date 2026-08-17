-- Sekisho D1 初期スキーマ
-- docs/cloudflare-implementation-plan.md §4 のデータモデル(匿名週間リーグ版)に対応する。
-- 計画からの追加: users.apple_refresh_token(アカウント削除時のAppleトークン失効処理に必要)。
-- FamilyControlsトークン・アプリ名・正確な利用時間・個別利用履歴は保存しない。

CREATE TABLE users (
  id TEXT PRIMARY KEY,
  apple_subject TEXT NOT NULL UNIQUE,
  -- サーバーが安全な語彙から自動生成する(Phase 2)。自由入力の表示名・プロフィールは持たせない。
  anonymous_handle TEXT,
  mascot_id TEXT,
  timezone TEXT,
  goal_tier TEXT,
  apple_refresh_token TEXT,
  created_at TEXT NOT NULL,
  deleted_at TEXT
);

CREATE TABLE auth_sessions (
  id TEXT PRIMARY KEY,
  user_id TEXT NOT NULL REFERENCES users(id),
  refresh_token_hash TEXT NOT NULL UNIQUE,
  expires_at TEXT NOT NULL,
  revoked_at TEXT,
  created_at TEXT NOT NULL
);
CREATE INDEX idx_auth_sessions_user ON auth_sessions(user_id);

-- 毎週自動編成される匿名リーグ(宿場)。参加者20人以下は1リーグ、21人以上で12〜20人程度に分割。
CREATE TABLE leagues (
  id TEXT PRIMARY KEY,
  week_start_date TEXT NOT NULL,
  week_end_date TEXT NOT NULL,
  timezone_group TEXT,
  goal_tier TEXT,
  max_members INTEGER NOT NULL DEFAULT 20,
  status TEXT NOT NULL CHECK (status IN ('active', 'finished')),
  created_at TEXT NOT NULL
);
CREATE INDEX idx_leagues_week ON leagues(week_start_date, status);

CREATE TABLE league_members (
  league_id TEXT NOT NULL REFERENCES leagues(id),
  user_id TEXT NOT NULL REFERENCES users(id),
  joined_at TEXT NOT NULL,
  weekly_score INTEGER NOT NULL DEFAULT 0,
  active_days INTEGER NOT NULL DEFAULT 0,
  excluded_at TEXT,
  PRIMARY KEY (league_id, user_id)
);
CREATE INDEX idx_league_members_user ON league_members(user_id);

CREATE TABLE daily_results (
  id TEXT PRIMARY KEY,
  league_id TEXT NOT NULL REFERENCES leagues(id),
  user_id TEXT NOT NULL REFERENCES users(id),
  local_date TEXT NOT NULL,
  status TEXT NOT NULL CHECK (status IN ('achieved', 'missed', 'unrecorded')),
  -- サーバー側で算出する(達成10点、3日連続+5点、7日全達成+20点、減点なし)。クライアント指定値は受け付けない。
  score INTEGER NOT NULL DEFAULT 0,
  posted_at TEXT NOT NULL,
  UNIQUE (league_id, user_id, local_date)
);

CREATE TABLE device_tokens (
  id TEXT PRIMARY KEY,
  user_id TEXT NOT NULL REFERENCES users(id),
  apns_device_token TEXT NOT NULL UNIQUE,
  environment TEXT NOT NULL CHECK (environment IN ('sandbox', 'production')),
  updated_at TEXT NOT NULL
);
CREATE INDEX idx_device_tokens_user ON device_tokens(user_id);

CREATE TABLE ai_insights (
  id TEXT PRIMARY KEY,
  user_id TEXT NOT NULL REFERENCES users(id),
  target_date TEXT NOT NULL,
  input_version TEXT NOT NULL,
  model_id TEXT NOT NULL,
  summary TEXT NOT NULL,
  suggestion_json TEXT NOT NULL,
  created_at TEXT NOT NULL,
  UNIQUE (user_id, target_date)
);

CREATE TABLE subscription_states (
  user_id TEXT PRIMARY KEY REFERENCES users(id),
  entitlement_id TEXT NOT NULL,
  is_active INTEGER NOT NULL DEFAULT 0,
  expires_at TEXT,
  updated_at TEXT NOT NULL
);
