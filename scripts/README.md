# Workshop Scripts

このディレクトリには、ワークショップ環境の運用に必要なすべてのスクリプトが含まれています。

## 📁 スクリプト一覧

### 🚀 セットアップ・プロビジョニング

#### `setup-git.sh`
GitHubリポジトリのセットアップ（初回のみ）

**用途**: ローカルのworkshop-provisioningをGitHubにpushする

**実行タイミング**: 最初の1回のみ

**使用方法**:
```bash
./scripts/setup-git.sh
```

**処理内容**:
- Git初期化
- リモートリポジトリURL設定
- コミット＆プッシュ

---

#### `initial-setup.sh`
完全な初回セットアップ（本番用）

**用途**: 本番環境の初回プロビジョニング

**実行タイミング**: 本番デプロイ時

**使用方法**:
```bash
./scripts/initial-setup.sh
```

**処理内容**:
1. 前提条件チェック
2. 設定ファイル検証
3. Ansible collectionsインストール
4. Preflightチェック
5. 完全プロビジョニング
6. 検証
7. エンドポイント＆資格情報表示

---

### 🧪 テスト用スクリプト

#### `test-full.sh` ⭐ 推奨
完全なGitOpsテスト（2ユーザー、Solution Server無効）

**用途**: GitOps機能を含む完全なテスト

**実行タイミング**: 開発・検証時

**使用方法**:
```bash
./scripts/test-full.sh
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

---

#### `test-quick-start.sh`
クイックテスト（対話型、旧形式）

**用途**: 対話的なテスト実行

**実行タイミング**: 手動確認したい時

**使用方法**:
```bash
./scripts/test-quick-start.sh
```

**処理内容**: test-full.shとほぼ同じ

---

#### `test-without-gitops.sh`
GitOps無し限定テスト

**用途**: GitOpsをスキップした最小テスト

**実行タイミング**: GitHubにpushできない時、または最小限の動作確認時

**使用方法**:
```bash
./scripts/test-without-gitops.sh
```

**処理内容**:
- Preflightチェック
- ユーザー作成（htpasswd）
- OAuth設定

**制限事項**:
- GitOps Operatorなし
- Dev Spaces/MTA Operatorなし
- Namespaceなし
- Workspaceなし

---

### 📊 ステータス確認

#### `status-check.sh` ⭐ 頻繁に使用
ワークショップ環境の状態確認

**用途**: 現在の環境状態をクイック確認

**実行タイミング**: いつでも

**使用方法**:
```bash
./scripts/status-check.sh
```

**表示内容**:
- GitOps Operator状態
- GitOps Applications sync/health
- Dev Spaces Operator/Instance状態
- MTA Operator/Instance状態
- Solution Server状態
- ユーザーNamespace数
- Workspace状態
- OAuth設定
- 総合ステータス判定

---

### 🧹 クリーンアップ

#### `cleanup-gitops.sh` ⭐ 重要
GitOps Applicationsのクリーンアップ

**用途**: ワークショップリソースの段階的削除

**実行タイミング**: テスト後、ワークショップ終了後

**使用方法**:
```bash
# ユーザーのみ削除
./scripts/cleanup-gitops.sh users

# プラットフォームまで削除
./scripts/cleanup-gitops.sh platform

# すべて削除（GitOps Operatorは残す）
./scripts/cleanup-gitops.sh all

# Root Applicationも含めてすべて削除
export CLEANUP_ROOT=true
./scripts/cleanup-gitops.sh all
```

**削除スコープ**:
- `users` - ユーザーNamespace、Workspace、RBAC
- `platform` - users + Dev Spaces/MTA Instance
- `all` - platform + Operators

---

#### `reset-gitops.sh`
GitOps Applicationsのリセット（削除＋再作成）

**用途**: ワークショップ環境の再セットアップ

**実行タイミング**: 環境をクリーンな状態から再構築したい時

**使用方法**:
```bash
# Applicationのみリセット（Secretは保持、パスワード維持）
./scripts/reset-gitops.sh applications

# 完全リセット（Secret再生成、新パスワード）
./scripts/reset-gitops.sh full
```

**モード**:
- `applications` - GitOps Operatorとsecretは保持
- `full` - すべて再作成（パスワード再生成）

---

### 📄 ユーザー管理

#### `generate-user-list.sh`
ユーザー資格情報リストの生成

**用途**: ワークショップ参加者への配布資料作成

**実行タイミング**: プロビジョニング完了後

**使用方法**:
```bash
# Markdown形式
./scripts/generate-user-list.sh markdown

# HTML形式（推奨）
./scripts/generate-user-list.sh html

# テキスト表形式
./scripts/generate-user-list.sh table
```

**出力先**:
- `artifacts/workshop-user-list.md`
- `artifacts/workshop-user-list.html`
- `artifacts/workshop-user-list.txt`

---

## 🎯 推奨ワークフロー

### 初回セットアップ（本番）

```bash
# 1. GitHubへのpush
./scripts/setup-git.sh

# 2. 設定ファイル編集
vim ansible/inventory/production/hosts.yml
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
# 1. GitHubへのpush（初回のみ）
./scripts/setup-git.sh

# 2. テスト設定確認
vim ansible/inventory/test/hosts.yml

# 3. フルテスト実行
./scripts/test-full.sh

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

| スクリプト | 用途 | 対象環境 | 所要時間 | GitOps | 対話型 |
|-----------|------|---------|---------|--------|--------|
| setup-git.sh | Git初期設定 | - | 1分 | - | ✓ |
| initial-setup.sh | 本番初回セットアップ | 本番 | 20-30分 | ✓ | ✓ |
| test-full.sh | 完全テスト | テスト | 20-30分 | ✓ | ✓ |
| test-quick-start.sh | クイックテスト | テスト | 20-30分 | ✓ | ✓ |
| test-without-gitops.sh | 最小テスト | テスト | 5分 | ✗ | ✓ |
| status-check.sh | 状態確認 | 両方 | 10秒 | - | - |
| cleanup-gitops.sh | リソース削除 | 両方 | 5-15分 | - | ✓ |
| reset-gitops.sh | 環境リセット | 両方 | 20-40分 | ✓ | ✓ |
| generate-user-list.sh | 資格情報リスト | 両方 | 5秒 | - | - |

---

## 🚨 よくある質問

### Q: どのテストスクリプトを使えばいい？

**A**: 基本的に `test-full.sh` を使用してください。GitOpsを含む完全なテストが実行されます。

---

### Q: GitHubにpushできない場合は？

**A**: `test-without-gitops.sh` で最小限のテストが可能ですが、GitOps機能はテストできません。

---

### Q: テスト後のクリーンアップは？

**A**: `cleanup-gitops.sh all` ですべて削除できます。Root Applicationも削除する場合は `export CLEANUP_ROOT=true` を先に実行してください。

---

### Q: ユーザー数を変更したい

**A**: 
```bash
ansible-playbook ansible/playbooks/bootstrap.yml \
  -i ansible/inventory/test/hosts.yml \
  -e workshop_user_count=5
```

---

### Q: パスワードを再生成せずに環境を作り直したい

**A**: `reset-gitops.sh applications` を使用してください。

---

## 🔧 トラブルシューティング

### スクリプトが見つからない

```bash
# スクリプトディレクトリに移動
cd /path/to/workshop-provisioning

# スクリプトを実行
./scripts/status-check.sh
```

### 権限エラー

```bash
# 実行権限付与
chmod +x scripts/*.sh
```

### ログ確認

すべてのスクリプトは `artifacts/` にログを保存します:
```bash
ls -lt artifacts/*.log | head -5
tail -f artifacts/<latest-log>
```

---

## 📚 関連ドキュメント

- [../README.md](../README.md) - プロジェクト概要
- [../docs/OPERATIONS.md](../docs/OPERATIONS.md) - 運用ガイド
- [../docs/QUICK_REFERENCE.md](../docs/QUICK_REFERENCE.md) - コマンドリファレンス
- [../docs/TROUBLESHOOTING.md](../docs/TROUBLESHOOTING.md) - トラブルシューティング
- [../TEST_RUN.md](../TEST_RUN.md) - テスト実行詳細手順
