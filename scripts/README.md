# Workshop Scripts

このディレクトリには、ワークショップ環境の運用に必要なすべてのスクリプトが含まれています。

## 📂 ディレクトリ構成

```
scripts/
├── README.md                  # このファイル
├── setup/                     # 🛠️  初期セットアップ
│   ├── initial-setup.sh       # 完全セットアップ
│   ├── setup-git.sh           # Git初期設定
│   └── setup-user-secrets.sh  # Secret配布
├── workspace/                 # 💼 Workspace管理
│   ├── create-workspaces-with-secrets.sh  # ✅ 推奨
│   ├── create-workspaces-via-api.sh
│   └── deprecated/            # 廃止予定スクリプト
├── user/                      # 👥 ユーザー管理
│   └── generate-user-list.sh
├── gitops/                    # 🔄 GitOps操作
│   ├── cleanup-gitops.sh
│   └── reset-gitops.sh
├── ops/                       # 🔍 運用・監視
│   └── status-check.sh
└── test/                      # 🧪 テスト
    ├── test-full.sh
    ├── test-quick-start.sh
    └── test-without-gitops.sh
```

---

## 🚀 Quick Start

### 1. 初期セットアップ

```bash
# 全体セットアップ（GitOps, MTA, Dev Spacesなど）
./scripts/setup/initial-setup.sh

# Git設定のみ
./scripts/setup/setup-git.sh

# Secret配布のみ
./scripts/setup/setup-user-secrets.sh
```

### 2. Workspace作成（✅ 推奨）

```bash
# Secret参照付きWorkspace作成
./scripts/workspace/create-workspaces-with-secrets.sh
```

### 3. ステータス確認

```bash
./scripts/ops/status-check.sh
```

---

## 🎯 Scripts by Category

### 🛠️  setup/ - 初期セットアップ

#### `setup/setup-git.sh`
**用途**: GitHubリポジトリの初期設定（最初の1回のみ）

**使用方法**:
```bash
./scripts/setup/setup-git.sh
```

**処理内容**:
- Git初期化
- リモートリポジトリURL設定
- コミット＆プッシュ

---

#### `setup/initial-setup.sh` ⭐ 本番デプロイ用
**用途**: 本番環境の完全な初回プロビジョニング

**使用方法**:
```bash
./scripts/setup/initial-setup.sh
```

**処理内容**:
1. 前提条件チェック
2. 設定ファイル検証
3. Ansible collectionsインストール
4. Preflightチェック
5. 完全プロビジョニング（GitOps, Operators, Platform, Users）
6. 検証
7. エンドポイント＆資格情報表示

**前提条件**:
- `ansible/inventory/production/hosts.yml` 設定済み
- `ansible/group_vars/vault.yml` 暗号化済み
- GitHubにpush済み

---

#### `setup/setup-user-secrets.sh`
**用途**: MTA LLM APIキーのSecret配布

**使用方法**:
```bash
./scripts/setup/setup-user-secrets.sh
```

**処理内容**:
- `openshift-mta/kai-api-keys` を各ユーザーNamespaceにコピー
- Workspace作成前に実行

---

### 💼 workspace/ - Workspace管理

#### `workspace/create-workspaces-with-secrets.sh` ⭐ 推奨
**用途**: Secret参照付きDevWorkspace作成

**使用方法**:
```bash
./scripts/workspace/create-workspaces-with-secrets.sh

# ユーザー数カスタマイズ
USER_COUNT=5 ./scripts/workspace/create-workspaces-with-secrets.sh
```

**処理内容**:
1. Secret配布（openshift-mta → user namespaces）
2. DevWorkspace作成（Secret参照付き）

**環境変数**:
- `USER_COUNT`: ユーザー数（デフォルト: 10）
- `USERNAME_PREFIX`: プレフィックス（デフォルト: user）
- `DEVFILE_REPO`: DevfileリポジトリURL

---

#### `workspace/create-workspaces-via-api.sh`
**用途**: Dev Spaces API経由Workspace作成

**使用方法**:
```bash
./scripts/workspace/create-workspaces-via-api.sh
```

---

#### `workspace/deprecated/`
**廃止予定スクリプト**:
- `create-devworkspaces.sh`
- `create-workspaces-from-devfile.sh`
- `replicate-workspaces*.sh/py`
- `add-mta-extension.sh`

⚠️ 互換性のため残されていますが、新規利用は非推奨です。

---

### 👥 user/ - ユーザー管理

#### `user/generate-user-list.sh`
**用途**: ワークショップ参加者への配布資料作成

**使用方法**:
```bash
# HTML形式（推奨）
./scripts/user/generate-user-list.sh html

# Markdown形式
./scripts/user/generate-user-list.sh markdown
```

**出力先**: `artifacts/workshop-user-list.*`

---

### 🔄 gitops/ - GitOps操作

#### `gitops/cleanup-gitops.sh` ⚠️ 重要
**用途**: GitOps Applicationsの段階的削除

**使用方法**:
```bash
# ユーザーのみ削除
./scripts/gitops/cleanup-gitops.sh users

# プラットフォームまで削除
./scripts/gitops/cleanup-gitops.sh platform

# すべて削除
./scripts/gitops/cleanup-gitops.sh all
```

---

#### `gitops/reset-gitops.sh`
**用途**: GitOps Applicationsのリセット

**使用方法**:
```bash
# Applicationのみリセット
./scripts/gitops/reset-gitops.sh applications

# 完全リセット
./scripts/gitops/reset-gitops.sh full
```

---

### 🔍 ops/ - 運用・監視

#### `ops/status-check.sh` ⭐ 頻繁に使用
**用途**: 現在の環境状態をクイック確認

**使用方法**:
```bash
./scripts/ops/status-check.sh
```

**表示内容**:
- GitOps Operator状態
- Applications sync/health
- Dev Spaces/MTA状態
- ユーザーNamespace/Workspace
- 総合ステータス判定

---

### `cleanup-gitops.sh` ⭐ 重要
**用途**: GitOps Applicationsの段階的削除

**使用方法**:
```bash
# ユーザーのみ削除
./scripts/cleanup-gitops.sh users

# プラットフォームまで削除
./scripts/cleanup-gitops.sh platform

# すべて削除（GitOps Operatorは残す）
./scripts/cleanup-gitops.sh all

# Root Applicationも含めて完全削除
export CLEANUP_ROOT=true
./scripts/cleanup-gitops.sh all
```

**削除スコープ**:
- `users` - ユーザーNamespace, Workspace, RBAC
- `platform` - users + Dev Spaces/MTA Instances
- `all` - platform + Operators

---

### `reset-gitops.sh`
**用途**: GitOps Applicationsのリセット（削除→再作成）

**使用方法**:
```bash
# Applicationのみリセット（パスワード維持）
./scripts/reset-gitops.sh applications

# 完全リセット（パスワード再生成）
./scripts/reset-gitops.sh full
```

---

### `generate-user-list.sh`
**用途**: ワークショップ参加者への配布資料作成

**使用方法**:
```bash
# HTML形式（推奨）
./scripts/generate-user-list.sh html

# Markdown形式
./scripts/generate-user-list.sh markdown

# テキスト表形式
./scripts/generate-user-list.sh table
```

**出力先**: `artifacts/workshop-user-list.*`

---

## 🧪 テスト用スクリプト（scripts/test/）

### `test/test-full.sh` ⭐ 推奨
**用途**: GitOps機能を含む完全なテスト（2ユーザー）

**使用方法**:
```bash
./scripts/test/test-full.sh
```

**処理内容**:
1. ログイン確認
2. Ansible collectionsインストール
3. Preflightチェック（確認プロンプト）
4. 完全プロビジョニング（15-25分）
5. 検証
6. 結果表示

**前提条件**:
- GitHubにpush済み
- `ansible/inventory/test/hosts.yml`設定済み

**所要時間**: 20-30分

---

### `test/test-quick-start.sh`
**用途**: 対話的なクイックテスト

**使用方法**:
```bash
./scripts/test/test-quick-start.sh
```

**処理内容**: test-full.shとほぼ同じ

---

### `test/test-without-gitops.sh`
**用途**: GitOpsをスキップした最小限のテスト

**使用方法**:
```bash
./scripts/test/test-without-gitops.sh
```

**処理内容**:
- Preflightチェック
- ユーザー作成（htpasswd）
- OAuth設定のみ

**制限事項**:
- GitOps機能なし
- Operators/Platform/Workspaceなし

**所要時間**: 5分

---

## 🎯 推奨ワークフロー

### 本番環境デプロイ

```bash
# 1. Git初期設定（初回のみ）
./scripts/setup/setup-git.sh

# 2. 設定ファイル準備
cp ansible/inventory/example/hosts.yml ansible/inventory/production/hosts.yml
vim ansible/inventory/production/hosts.yml

cp ansible/group_vars/vault.example.yml ansible/group_vars/vault.yml
vim ansible/group_vars/vault.yml
ansible-vault encrypt ansible/group_vars/vault.yml

# 3. プロビジョニング
./scripts/setup/initial-setup.sh

# 4. Workspace作成
./scripts/workspace/create-workspaces-with-secrets.sh

# 5. ユーザーリスト生成
./scripts/user/generate-user-list.sh html
```

---

### テスト実行

```bash
# 1. Git初期設定（初回のみ）
./scripts/setup/setup-git.sh

# 2. テスト設定確認
vim ansible/inventory/test/hosts.yml

# 3. フルテスト実行
./scripts/test/test-full.sh

# 4. ステータス確認
./scripts/ops/status-check.sh

# 5. クリーンアップ
./scripts/gitops/cleanup-gitops.sh all
```

---

### 日常運用

```bash
# ステータス確認
./scripts/ops/status-check.sh

# ユーザーリスト再生成
./scripts/user/generate-user-list.sh html

# Workspace作成
./scripts/workspace/create-workspaces-with-secrets.sh

# 環境リセット
./scripts/gitops/reset-gitops.sh applications

# クリーンアップ
./scripts/gitops/cleanup-gitops.sh users
```

---

## 📋 スクリプト比較表

### 本番用スクリプト

| スクリプト | 用途 | 所要時間 | 対話型 |
|-----------|------|---------|--------|
| setup/setup-git.sh | Git初期設定 | 1分 | ✓ |
| setup/initial-setup.sh | 完全セットアップ | 20-30分 | ✓ |
| setup/setup-user-secrets.sh | Secret配布 | 1分 | - |
| workspace/create-workspaces-with-secrets.sh | Workspace作成 | 2-5分 | - |
| ops/status-check.sh | 状態確認 | 10秒 | - |
| gitops/cleanup-gitops.sh | リソース削除 | 5-15分 | ✓ |
| gitops/reset-gitops.sh | 環境リセット | 20-40分 | ✓ |
| user/generate-user-list.sh | 資格情報リスト | 5秒 | - |

### テスト用スクリプト

| スクリプト | GitOps | 所要時間 | ユーザー数 |
|-----------|--------|---------|-----------|
| test/test-full.sh | ✓ | 20-30分 | 2 |
| test/test-quick-start.sh | ✓ | 20-30分 | 2 |
| test/test-without-gitops.sh | ✗ | 5分 | 2 |

---

## 🚨 よくある質問

### Q: 本番とテストの違いは？

**A**: 
- **本番用** (`scripts/`): `ansible/inventory/production/` を使用、実際のワークショップ向け
- **テスト用** (`scripts/test/`): `ansible/inventory/test/` を使用、検証・開発向け

---

### Q: どのテストスクリプトを使えばいい？

**A**: 基本的に `test/test-full.sh` を使用してください。

---

### Q: GitHubにpushせずにテストできる？

**A**: `test/test-without-gitops.sh` で最小限のテストが可能ですが、GitOps機能はテストできません。

---

### Q: テスト後のクリーンアップは？

**A**: 
```bash
# テスト後
./scripts/cleanup-gitops.sh all

# 完全削除
export CLEANUP_ROOT=true
./scripts/cleanup-gitops.sh all
```

---

## 📚 関連ドキュメント

- [../README.md](../README.md) - プロジェクト概要
- [../docs/OPERATIONS.md](../docs/OPERATIONS.md) - 運用ガイド
- [../docs/QUICK_REFERENCE.md](../docs/QUICK_REFERENCE.md) - コマンドリファレンス
- [../docs/TROUBLESHOOTING.md](../docs/TROUBLESHOOTING.md) - トラブルシューティング
- [../TEST_RUN.md](../TEST_RUN.md) - テスト実行詳細手順
