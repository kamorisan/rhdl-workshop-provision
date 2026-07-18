# Workshop Documentation

このディレクトリには、Developer Lightspeed Workshop環境の構築・運用に関するドキュメントが含まれています。

---

## 🚀 新規環境デプロイ（最重要）

### [DEPLOYMENT-GUIDE.md](DEPLOYMENT-GUIDE.md) ⭐ **START HERE**

**対象者**: 新しいOpenShift環境に初めてワークショップをデプロイする管理者

**内容**:
- Phase 1-7の完全デプロイ手順
- 環境固有値の設定方法
- Gitea、DevSpaces、PostgreSQLの自動デプロイ
- coolstore-eap7リポジトリの配布
- トラブルシューティング
- デプロイ完了チェックリスト

**所要時間**: 約30-35分

---

## 📋 デプロイ補助資料

### [DEPLOYMENT_CHECKLIST.md](DEPLOYMENT_CHECKLIST.md)

**対象者**: デプロイ前後の確認作業を行う管理者

**内容**:
- デプロイ前の前提条件チェックリスト
- デプロイ後の動作確認項目
- 各コンポーネントのヘルスチェック

---

## 🔧 運用・保守

### [OPERATIONS.md](OPERATIONS.md)

**対象者**: デプロイ済み環境を運用・保守する管理者

**内容**:
- ユーザー追加・削除
- パスワードリセット
- バックアップ・リストア
- スケーリング
- アップグレード

---

## 🐛 トラブルシューティング

### [TROUBLESHOOTING.md](TROUBLESHOOTING.md)

**対象者**: 環境に問題が発生した場合の対応を行う管理者

**内容**:
- よくある問題と解決方法
- Argo CD sync失敗
- Pod起動失敗
- ユーザーアクセス問題
- DevSpaces関連問題

---

## 📚 リファレンス

### [QUICK_REFERENCE.md](QUICK_REFERENCE.md)

**対象者**: よく使うコマンドをすぐに参照したい管理者

**内容**:
- コマンド一覧（プロビジョニング、確認、削除）
- パス一覧
- URL一覧
- クイックTips

---

## 👥 ワークショップ参加者向け

### [WORKSHOP_GUIDE.md](WORKSHOP_GUIDE.md)

**対象者**: ワークショップに参加する開発者

**内容**:
- DevSpaces Workspaceの起動方法
- アプリケーションのビルド・デプロイ
- MTA（Migration Toolkit for Applications）の使い方
- Developer Lightspeedの活用方法

---

## 🗂️ アーカイブ（参考資料）

以下のドキュメントは古いバージョンまたは進行中のタスクです。通常は参照不要です。

### ~~NEW_CLUSTER_DEPLOYMENT.md~~ → **DEPLOYMENT-GUIDE.md**に統合済み

旧版の新規クラスターデプロイ手順。最新の手順は`DEPLOYMENT-GUIDE.md`を参照してください。

### ~~GETTING_STARTED.md~~ → **DEPLOYMENT-GUIDE.md**に統合済み

旧版のGetting Startedガイド。最新の手順は`DEPLOYMENT-GUIDE.md`を参照してください。

### GITOPS_MIGRATION_TODO.md

DevSpaces WorkspaceのGitOps化に関する進行中のタスクリスト。実装検討中の項目です。

---

## 📖 ドキュメント利用フロー

### 初めてデプロイする場合

1. **[DEPLOYMENT-GUIDE.md](DEPLOYMENT-GUIDE.md)** を読んで手順に従う
2. **[DEPLOYMENT_CHECKLIST.md](DEPLOYMENT_CHECKLIST.md)** でデプロイ完了を確認
3. 問題があれば **[TROUBLESHOOTING.md](TROUBLESHOOTING.md)** を参照

### 運用・保守する場合

1. **[OPERATIONS.md](OPERATIONS.md)** で運用手順を確認
2. **[QUICK_REFERENCE.md](QUICK_REFERENCE.md)** でコマンドを素早く参照
3. 問題があれば **[TROUBLESHOOTING.md](TROUBLESHOOTING.md)** を参照

### ワークショップ参加者の場合

1. **[WORKSHOP_GUIDE.md](WORKSHOP_GUIDE.md)** を読んで開始

---

## 🔄 更新履歴

| 日付 | ドキュメント | 変更内容 |
|------|-------------|---------|
| 2026-07-18 | DEPLOYMENT-GUIDE.md | 新規作成（最新の完全デプロイ手順） |
| 2026-07-18 | README.md | ドキュメント整理・ナビゲーション追加 |
| 2026-07-15 | NEW_CLUSTER_DEPLOYMENT.md | 旧版（DEPLOYMENT-GUIDEに統合） |
| 2026-07-14 | GETTING_STARTED.md | 旧版（DEPLOYMENT-GUIDEに統合） |

---

## ❓ 質問・フィードバック

ドキュメントに関する質問や改善提案は、GitHub Issuesでお知らせください：
https://github.com/kamorisan/rhdl-workshop-provision/issues
