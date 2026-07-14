# Getting Started: 新規クラスターへのデプロイ

このガイドでは、完全に新規のOpenShiftクラスターに Developer Lightspeed Workshop 環境をゼロからデプロイする手順を説明します。

> **📚 関連ドキュメント**
> - [README.md](../README.md) - プロジェクト概要とアーキテクチャ
> - [DEPLOYMENT_CHECKLIST.md](DEPLOYMENT_CHECKLIST.md) - デプロイ前の確認項目チェックリスト
> - [scripts/README.md](../scripts/README.md) - スクリプトリファレンス

---

## 📋 前提条件

開始前に以下を準備してください（詳細は [DEPLOYMENT_CHECKLIST.md](DEPLOYMENT_CHECKLIST.md) 参照）：

### OpenShiftクラスター
- ✅ OpenShift 4.12以降
- ✅ cluster-admin権限
- ✅ デフォルトStorageClass設定済み
- ✅ 十分なリソース（CPU: ~14コア、メモリ: ~36GB、ストレージ: ~120GB）

### ローカル環境
- ✅ Ansible 2.15+
- ✅ `oc` CLI
- ✅ `htpasswd` コマンド
- ✅ Python 3.9+
- ✅ Git

### 外部サービス
- ✅ LLM API（OpenAI互換エンドポイント）
  - APIキー取得済み
  - エンドポイントURL確認済み
  - モデル名確認済み
- ✅ GitHubアカウント（GitOpsリポジトリ用）

---

## 🚀 デプロイ手順

所要時間: 約30-40分

### Step 1: リポジトリのクローンとGit設定

```bash
# 1.1 リポジトリをクローン
git clone https://github.com/YOUR_USERNAME/rhdl-workshop-provision.git
cd rhdl-workshop-provision

# 1.2 Git初期設定（初回のみ）
./scripts/setup/setup-git.sh
```

**実行内容:**
- Gitリモート設定
- 初回コミット
- GitHubへプッシュ

---

### Step 2: OpenShiftクラスターへログイン

```bash
# 2.1 cluster-adminでログイン
oc login https://api.YOUR_CLUSTER_DOMAIN:6443

# 2.2 権限確認
oc whoami
oc auth can-i '*' '*' --all-namespaces
# Expected: yes
```

**確認:**
```bash
# クラスター情報表示
oc cluster-info

# デフォルトStorageClass確認
oc get storageclass
# 1つが (default) マーク付きであることを確認
```

---

### Step 3: 設定ファイルの作成

#### 3.1 Inventoryファイル

```bash
# テンプレートをコピー
cp ansible/inventory/example/hosts.yml ansible/inventory/production/hosts.yml

# 編集
vim ansible/inventory/production/hosts.yml
```

**設定項目（最小構成）:**

```yaml
all:
  vars:
    # クラスター設定
    cluster_api_url: "https://api.YOUR_CLUSTER_DOMAIN:6443"
    
    # ワークショップ設定
    workshop_user_count: 10
    workshop_user_prefix: "user"
    
    # デモアプリケーション
    demo_repository_url: "https://github.com/kamorisan/spring-to-quarkus-sample"
    demo_repository_revision: "main"
    
    # Operator設定（クラスターのバージョンに合わせて調整）
    devspaces_channel: "stable"
    mta_channel: "stable-v8.1"
    
    # GitOps設定
    gitops_repo_url: "https://github.com/YOUR_USERNAME/rhdl-workshop-provision"
    gitops_repo_revision: "main"
    
    # LLM設定
    llm_provider: "ChatOpenAI"
    llm_model: "gpt-oss-120b"
    llm_api_base: "https://maas-rhdp.apps.maas.redhatworkshops.io/v1"
```

#### 3.2 Vaultファイル（機密情報）

```bash
# テンプレートをコピー
cp ansible/group_vars/vault.example.yml ansible/group_vars/vault.yml

# 編集
vim ansible/group_vars/vault.yml
```

**必須項目:**

```yaml
---
# LLM API Key（必須）
vault_llm_api_key: "sk-YOUR-API-KEY-HERE"

# GitOpsリポジトリトークン（プライベートリポジトリの場合）
vault_gitops_repo_token: ""

# デモリポジトリトークン（プライベートリポジトリの場合）
vault_demo_repo_token: ""
```

**暗号化:**

```bash
# Vaultファイルを暗号化
ansible-vault encrypt ansible/group_vars/vault.yml
# パスワードを設定（忘れずに保管！）

# 確認（暗号化されているはず）
cat ansible/group_vars/vault.yml
# $ANSIBLE_VAULT;1.1;AES256 で始まっていればOK
```

---

### Step 4: MTA Tackle CRの確認と調整

> **重要:** MTAのバージョンやOperatorによって、Tackle CRのフィールド名が異なる場合があります。

```bash
# 4.1 クラスターに接続した状態でCRDを確認
oc explain tackle.spec --recursive | grep -A 20 kai

# 4.2 必要に応じて gitops/platform-instances/mta/tackle.yaml を調整
vim gitops/platform-instances/mta/tackle.yaml
```

**確認項目:**
- `kai_solution_server_enabled` または `kai.enabled`
- LLM設定フィールド名（`kai_llm_provider`, `kai_llm_model`, `kai_llm_baseurl`）

**現在の環境（MTA 8.1.2）の例:**

```yaml
spec:
  feature_auth_required: false
  kai_solution_server_enabled: true
  kai_llm_provider: OpenAI
  kai_llm_model: gpt-oss-120b
  kai_llm_baseurl: https://maas-rhdp.apps.maas.redhatworkshops.io/v1
```

---

### Step 5: Ansible Collectionsのインストール

```bash
# 5.1 依存関係インストール
ansible-galaxy collection install -r ansible/requirements.yml

# 5.2 確認
ansible-galaxy collection list | grep kubernetes
# kubernetes.core が表示されればOK
```

---

### Step 6: Preflight Check（事前確認）

```bash
# 6.1 Preflight実行
make preflight

# または直接Ansible実行
ansible-playbook -i ansible/inventory/production/hosts.yml \
  ansible/playbooks/preflight.yml \
  --ask-vault-pass
```

**確認項目:**
- ✅ クラスター接続可能
- ✅ cluster-admin権限あり
- ✅ StorageClass設定済み
- ✅ Operator利用可能
- ✅ LLMエンドポイント到達可能
- ✅ GitOpsリポジトリアクセス可能

**⚠️ エラーが出た場合は修正してから次へ進んでください。**

---

### Step 7: 環境デプロイ

#### 7.1 自動デプロイ（推奨）

```bash
./scripts/setup/initial-setup.sh
```

**実行内容:**
1. Preflight check
2. Ansible collections確認
3. GitOps Operatorデプロイ
4. Operators（Dev Spaces, MTA）デプロイ
5. Platform Instances（Dev Spaces CR, Tackle CR）デプロイ
6. ユーザーNamespace作成
7. OAuth設定
8. デプロイ検証

**所要時間:** 20-30分

#### 7.2 手動デプロイ（詳細制御が必要な場合）

```bash
# Ansible Playbook直接実行
ansible-playbook -i ansible/inventory/production/hosts.yml \
  ansible/playbooks/provision.yml \
  --ask-vault-pass
```

---

### Step 8: デプロイ状況の確認

```bash
# 8.1 ステータスチェック
./scripts/ops/status-check.sh

# 8.2 GitOps Applications確認
oc get applications -n openshift-gitops

# Expected output (すべてSynced/Healthy):
# NAME                 SYNC STATUS   HEALTH STATUS
# workshop-root        Synced        Healthy
# workshop-operators   Synced        Healthy
# workshop-platform    Synced        Healthy
# ...

# 8.3 Operator確認
oc get csv -n openshift-operators | grep -E 'devspaces|mta'

# 8.4 MTA Solution Server確認
oc get pods -n openshift-mta | grep kai
# kai-api-xxx    Running
# kai-db-xxx     Running
```

---

### Step 9: MTA Secret準備（重要！）

Workshop環境では、MTA LLM APIキーをSecretとして管理します。

#### 9.1 openshift-mta NamespaceにSecret作成

```bash
# 9.1.1 Secret作成
oc create secret generic kai-api-keys \
  -n openshift-mta \
  --from-literal=OPENAI_API_BASE='https://maas-rhdp.apps.maas.redhatworkshops.io/v1' \
  --from-literal=OPENAI_API_KEY='sk-YOUR-API-KEY-HERE'

# 9.1.2 確認
oc get secret kai-api-keys -n openshift-mta
```

**このSecretが、各ユーザーNamespaceにコピーされます。**

---

### Step 10: Workspace作成（Secret注入）

```bash
# 10.1 Secret配布 + Workspace作成（一括実行）
./scripts/workspace/create-workspaces-with-secrets.sh

# または環境変数でカスタマイズ
USER_COUNT=5 ./scripts/workspace/create-workspaces-with-secrets.sh
```

**実行内容:**
1. `kai-api-keys` Secretを各ユーザーNamespace（user01-devspaces, user02-devspaces...）にコピー
2. DevWorkspaceリソース作成（Secret参照付き）
3. 各ユーザーがWorkspaceを起動可能に

**確認:**

```bash
# Secret配布確認
oc get secret kai-api-keys -n user01-devspaces
oc get secret kai-api-keys -n user02-devspaces

# DevWorkspace作成確認
oc get devworkspace -n user01-devspaces
oc get devworkspace -n user02-devspaces
```

---

### Step 11: 動作確認

#### 11.1 テストユーザーでログイン

```bash
# 11.1.1 ユーザー認証情報取得
cat artifacts/workshop-users.csv | head -3

# 11.1.2 user01でログイン
oc login -u user01 -p <password>

# 11.1.3 自分のNamespaceアクセス確認
oc get pods -n user01-dev
# 権限あり（空の場合もあり）

# 11.1.4 他のNamespaceアクセス確認（失敗するべき）
oc get pods -n user02-dev
# Error from server (Forbidden): pods is forbidden
```

#### 11.2 Dev Spaces Dashboard確認

```bash
# 11.2.1 Dev Spaces URL取得
oc get route -n openshift-devspaces devspaces -o jsonpath='{.spec.host}'

# 11.2.2 ブラウザでアクセス
# https://devspaces-openshift-devspaces.apps.YOUR_CLUSTER_DOMAIN

# 11.2.3 user01でログイン
# Username: user01
# Password: <上記で確認したパスワード>

# 11.2.4 Workspaceが表示されることを確認
# "spring-to-quarkus-workshop" が見えるはず
```

#### 11.3 Workspace起動テスト

```bash
# Dashboard上でWorkspaceを起動

# 起動後、ターミナルで確認:
echo $MTA_LLM_API_KEY
# sk-... が表示されればSecret注入成功

echo $MTA_LLM_BASE_URL
# https://maas-... が表示されればOK

# MTA設定ファイル確認
cat /checode/remote/data/User/globalStorage/redhat.mta-core/settings/provider-settings.yaml
# APIキーとエンドポイントが正しく設定されているはず
```

#### 11.4 MTA拡張機能確認

1. VS Code拡張機能タブを開く
2. "Migration Toolkit for Applications" が自動インストールされているか確認
3. MTA拡張機能の設定を確認

---

### Step 12: ユーザー配布資料作成

```bash
# 12.1 HTMLフォーマットでユーザーリスト生成
./scripts/user/generate-user-list.sh html

# 12.2 出力確認
open artifacts/workshop-user-list.html

# 12.3 参加者に配布
# - OpenShift Console URL
# - Dev Spaces Dashboard URL
# - ユーザー名とパスワード
# - Workshop Guide
```

---

## ✅ デプロイ完了チェックリスト

すべて✅になっていることを確認してください：

- [ ] GitOps Applications すべて Synced/Healthy
- [ ] Dev Spaces Operator Running
- [ ] MTA Operator Running
- [ ] Dev Spaces CheCluster Ready
- [ ] MTA Tackle CR Ready
- [ ] Solution Server (kai-api, kai-db) Running
- [ ] ユーザーNamespace作成済み（user01-dev, user01-devspaces, ...）
- [ ] Secret配布済み（kai-api-keys in user*-devspaces）
- [ ] DevWorkspace作成済み
- [ ] user01でログイン成功
- [ ] user01のWorkspace起動成功
- [ ] Workspace内でSecret注入確認
- [ ] MTA拡張機能インストール確認
- [ ] ユーザーリスト作成済み

---

## 🔧 トラブルシューティング

### 問題: Argo CD ApplicationがSyncedにならない

```bash
# Application詳細確認
oc describe application <app-name> -n openshift-gitops

# 手動Sync実行
oc patch application <app-name> -n openshift-gitops \
  --type merge -p '{"operation":{"initiatedBy":{"username":"admin"},"sync":{}}}'

# Argo CD UIで確認
oc get route openshift-gitops-server -n openshift-gitops -o jsonpath='{.spec.host}'
# ブラウザでアクセス
```

### 問題: MTA Solution Serverが起動しない

```bash
# Tackle CR Status確認
oc get tackle mta -n openshift-mta -o yaml | grep -A 20 status

# kai-api-keys Secret確認
oc get secret kai-api-keys -n openshift-mta
oc get secret kai-api-keys -n openshift-mta -o jsonpath='{.data}' | jq 'keys'

# Operator Log確認
oc logs -n openshift-mta -l name=mta-operator --tail=200

# kai-api Pod Log確認
oc logs -n openshift-mta -l app.kubernetes.io/component=kai-api --tail=200
```

### 問題: WorkspaceでSecret注入されていない

```bash
# Secret存在確認
oc get secret kai-api-keys -n user01-devspaces

# DevWorkspace Spec確認
oc get devworkspace spring-to-quarkus-workshop -n user01-devspaces -o yaml

# Pod環境変数確認
oc get pod -n user01-devspaces
oc exec -it <workspace-pod-name> -n user01-devspaces -- env | grep MTA_LLM
```

### 問題: MTA拡張機能がインストールされない

```bash
# .vscode/extensions.json確認
ls -la /projects/spring-to-quarkus-sample/.vscode/
cat /projects/spring-to-quarkus-sample/.vscode/extensions.json

# Workspace再起動
# Dashboard上でStop → Start

# 手動インストール
# VS Code内で Extensions → Search "MTA" → Install
```

### 問題: LLMへの接続エラー

```bash
# Workspace内でテスト
curl -I https://maas-rhdp.apps.maas.redhatworkshops.io/v1/models \
  -H "Authorization: Bearer ${MTA_LLM_API_KEY}"

# 200 OK が返ればネットワーク疎通OK

# エラーの場合:
# - APIキー確認
# - エンドポイントURL確認
# - クラスターからの外部接続確認
```

---

## 🔄 環境のリセット

### ユーザーのみリセット

```bash
./scripts/gitops/cleanup-gitops.sh users
```

### プラットフォームまでリセット

```bash
./scripts/gitops/cleanup-gitops.sh platform
```

### 完全リセット

```bash
./scripts/gitops/cleanup-gitops.sh all
```

### 再デプロイ

```bash
./scripts/setup/initial-setup.sh
./scripts/workspace/create-workspaces-with-secrets.sh
```

---

## 📚 次のステップ

環境デプロイが完了したら：

1. **Workshop Guide確認**
   - 参加者向けガイドを確認
   - Spring Boot → Quarkus移行手順を理解

2. **MTA Hub探索**（オプション）
   ```bash
   oc get route mta -n openshift-mta -o jsonpath='{.spec.host}'
   # ブラウザでアクセス
   ```

3. **Solution Server動作確認**
   - 1人のユーザーでMTA分析実行
   - AI提案取得
   - Solution Serverに蓄積されることを確認

4. **運用監視設定**
   - リソース使用量モニタリング
   - ログ収集設定
   - アラート設定

5. **バックアップ**
   ```bash
   # ユーザー認証情報バックアップ
   cp artifacts/workshop-users.csv ~/backup/

   # Vault バックアップ
   cp ansible/group_vars/vault.yml ~/backup/
   ```

---

## 📞 サポート

問題が解決しない場合：

1. [DEPLOYMENT_CHECKLIST.md](DEPLOYMENT_CHECKLIST.md) で前提条件を再確認
2. [README.md](../README.md) でアーキテクチャを確認
3. `./scripts/ops/status-check.sh` で環境ステータス確認
4. GitHubリポジトリでIssue作成

---

**デプロイ完了！参加者に素晴らしいWorkshop体験を提供しましょう 🎉**
