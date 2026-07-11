# Workshop Scripts

このディレクトリには、ワークショップ環境の運用に必要なすべてのスクリプトが含まれています。

## 📂 ディレクトリ構成

```
scripts/
├── README.md              # このファイル
├── setup-git.sh           # Git初期設定（初回のみ）
├── initial-setup.sh       # 本番用：完全セットアップ
├── status-check.sh        # 本番用：状態確認
├── cleanup-gitops.sh      # 本番用：クリーンアップ
├── reset-gitops.sh        # 本番用：環境リセット
├── generate-user-list.sh  # 本番用：ユーザーリスト生成
└── test/                  # テスト用スクリプト
    ├── test-full.sh           # フルテスト（GitOps有効）
    ├── test-quick-start.sh    # クイックテスト
    └── test-without-gitops.sh # 最小テスト（GitOps無し）
```

---

## 🎯 本番用スクリプト（scripts/）

### `setup-git.sh`
**用途**: GitHubリポジトリの初期設定（最初の1回のみ）

**使用方法**:
```bash
./scripts/setup-git.sh
```

**処理内容**:
- Git初期化
- リモートリポジトリURL設定
- コミット＆プッシュ

---

### `initial-setup.sh` ⭐ 本番デプロイ用
**用途**: 本番環境の完全な初回プロビジョニング

**使用方法**:
```bash
./scripts/initial-setup.sh
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

### `status-check.sh` ⭐ 頻繁に使用
**用途**: 現在の環境状態をクイック確認

**使用方法**:
```bash
./scripts/status-check.sh
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
./scripts/setup-git.sh

# 2. 設定ファイル準備
cp ansible/inventory/example/hosts.yml ansible/inventory/production/hosts.yml
vim ansible/inventory/production/hosts.yml

cp ansible/group_vars/vault.example.yml ansible/group_vars/vault.yml
vim ansible/group_vars/vault.yml
ansible-vault encrypt ansible/group_vars/vault.yml

# 3. プロビジョニング
./scripts/initial-setup.sh

# 4. ユーザーリスト生成
./scripts/generate-user-list.sh html
```

---

### テスト実行

```bash
# 1. Git初期設定（初回のみ）
./scripts/setup-git.sh

# 2. テスト設定確認
vim ansible/inventory/test/hosts.yml

# 3. フルテスト実行
./scripts/test/test-full.sh

# 4. ステータス確認
./scripts/status-check.sh

# 5. クリーンアップ
./scripts/cleanup-gitops.sh all
```

---

### 日常運用

```bash
# ステータス確認
./scripts/status-check.sh

# ユーザーリスト再生成
./scripts/generate-user-list.sh html

# 環境リセット
./scripts/reset-gitops.sh applications

# クリーンアップ
./scripts/cleanup-gitops.sh users
```

---

## 📋 スクリプト比較表

### 本番用スクリプト

| スクリプト | 用途 | 所要時間 | 対話型 |
|-----------|------|---------|--------|
| setup-git.sh | Git初期設定 | 1分 | ✓ |
| initial-setup.sh | 完全セットアップ | 20-30分 | ✓ |
| status-check.sh | 状態確認 | 10秒 | - |
| cleanup-gitops.sh | リソース削除 | 5-15分 | ✓ |
| reset-gitops.sh | 環境リセット | 20-40分 | ✓ |
| generate-user-list.sh | 資格情報リスト | 5秒 | - |

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
