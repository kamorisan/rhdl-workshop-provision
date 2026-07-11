# テスト実行手順

## 現在の環境情報

- **クラスター**: https://api.cluster-59m78.59m78.sandbox1272.opentlc.com:6443
- **ユーザー**: kube:admin (cluster-admin)
- **Dev Spaces Operator**: stable チャンネル利用可能
- **MTA Operator**: stable-v8.1 チャンネル利用可能
- **テストユーザー数**: 2名

## ステップ 1: テスト用設定ファイル作成

```bash
cd /Users/kamori/vscode/developer-lightspeed/workshop-provisioning

# テスト用inventory作成
mkdir -p ansible/inventory/test
cat > ansible/inventory/test/hosts.yml << 'EOF'
---
all:
  hosts:
    localhost:
      ansible_connection: local
      ansible_python_interpreter: "{{ ansible_playbook_python }}"

  vars:
    # OpenShift Cluster
    cluster_api_url: "https://api.cluster-59m78.59m78.sandbox1272.opentlc.com:6443"
    cluster_validate_certs: false  # Self-signed cert対応

    # Workshop Configuration (テスト用: 2ユーザー)
    workshop_user_count: 2

    # Demo Application
    demo_repository_url: "https://github.com/kamorisan/spring-to-quarkus-sample"
    demo_repository_revision: "main"
    demo_repository_private: false

    # Migration Configuration
    migration_source: "springboot"
    migration_target: "quarkus"

    # GitOps Repository (ローカルテスト用)
    # 注意: 実際のGitリポジトリURLに変更が必要
    gitops_repo_url: "https://github.com/kamorisan/workshop-provisioning.git"
    gitops_repo_revision: "main"
    gitops_repo_path: "gitops/bootstrap"
    gitops_auth_type: "none"

    # LLM Configuration
    llm_provider: "openai"
    llm_model: "gpt-4"
    llm_api_base: "https://api.openai.com/v1"

    # Operator Channels
    devspaces_channel: "stable"
    mta_channel: "stable-v8.1"

    # Resource Limits (テスト用に縮小)
    workspace_cpu_request: "500m"
    workspace_cpu_limit: "2000m"
    workspace_memory_request: "2Gi"
    workspace_memory_limit: "8Gi"
    workspace_storage: "10Gi"

    # Solution Server
    solution_server_enabled: true
    solution_server_storage: "5Gi"

    # PVC Retention (テスト用: 削除)
    retain_solution_server_pvc: false
    retain_workspace_pvc: false

    # Network Policy (テスト用: 無効)
    network_policy_enabled: false
EOF

# テスト用vault作成 (LLM API Keyは仮の値)
cat > ansible/group_vars/vault.yml << 'EOF'
---
# Test Vault - LLM API Keyは実際の値に置き換えてください

vault_llm_api_key: "sk-test-key-replace-with-real-key"
EOF

echo "✓ テスト用設定ファイルを作成しました"
```

## ステップ 2: 重要な設定確認

### 2.1 LLM API Key設定

**重要**: 実際のLLM API Keyが必要です。以下のいずれかを実行してください。

#### オプションA: LLM API Keyを設定する場合
```bash
# vault.ymlを編集してLLM API Keyを設定
vim ansible/group_vars/vault.yml
# vault_llm_api_key: "sk-your-actual-api-key" に変更

# Vaultを暗号化
ansible-vault encrypt ansible/group_vars/vault.yml
# パスワードを設定 (例: test123)
```

#### オプションB: LLM機能なしでテストする場合
```bash
# Solution Serverを無効化
# ansible/inventory/test/hosts.ymlで以下を変更:
# solution_server_enabled: false
```

### 2.2 GitOpsリポジトリURL設定

**重要**: GitOpsマニフェストをGitリポジトリにpushする必要があります。

#### オプションA: 実際のGitリポジトリを使用
```bash
# 1. GitHubでリポジトリ作成
# 2. workshop-provisioningをpush
cd /Users/kamori/vscode/developer-lightspeed/workshop-provisioning
git init
git add .
git commit -m "Initial commit"
git remote add origin https://github.com/kamorisan/workshop-provisioning.git
git push -u origin main

# 3. inventory/test/hosts.ymlのgitops_repo_urlを更新
# gitops_repo_url: "https://github.com/kamorisan/workshop-provisioning.git"
```

#### オプションB: テスト用に簡易化
```bash
# gitops/配下のマニフェストをクラスタに直接適用する方法
# (本番推奨ではないが、テストには使用可能)
```

### 2.3 MTA Tackle CR検証

```bash
# 現在のクラスタでTackle CRDのフィールドを確認
oc get crd tackles.tackle.konveyor.io >/dev/null 2>&1 || echo "MTA Operator未インストール (正常)"

# インストール後に確認:
# oc explain tackle.spec --recursive
```

## ステップ 3: Ansible Collection インストール

```bash
cd /Users/kamori/vscode/developer-lightspeed/workshop-provisioning

# Ansible collectionsをインストール
ansible-galaxy collection install -r ansible/requirements.yml --force

echo "✓ Ansible collectionsをインストールしました"
```

## ステップ 4: Preflight チェック実行

```bash
# Preflightチェックのみ実行
ansible-playbook ansible/playbooks/bootstrap.yml \
  -i ansible/inventory/test/hosts.yml \
  --tags preflight

# または
INVENTORY=ansible/inventory/test/hosts.yml make preflight
```

**期待される出力**:
- ✓ Cluster API接続成功
- ✓ cluster-admin権限確認
- ✓ OperatorHub利用可能
- ✓ StorageClass確認
- ⚠ GitOpsリポジトリ接続（設定次第）
- ⚠ LLMエンドポイント接続（設定次第）

## ステップ 5: 実際のプロビジョニング実行

### オプションA: フル機能でテスト (LLM有効)

```bash
# LLM API Keyを設定済みの場合
cd /Users/kamori/vscode/developer-lightspeed/workshop-provisioning

# 初回セットアップスクリプト実行
INVENTORY=ansible/inventory/test/hosts.yml ./scripts/initial-setup.sh

# または手動実行
ansible-playbook ansible/playbooks/bootstrap.yml \
  -i ansible/inventory/test/hosts.yml \
  --ask-vault-pass
```

### オプションB: 最小構成でテスト (LLM無効)

```bash
# Solution Server無効でテスト
ansible-playbook ansible/playbooks/bootstrap.yml \
  -i ansible/inventory/test/hosts.yml \
  -e solution_server_enabled=false \
  -e workshop_user_count=2
```

## ステップ 6: 進行状況監視

別のターミナルで以下を実行:

```bash
# GitOps Applications監視
watch -n 5 'oc get applications -n openshift-gitops'

# Operator状態監視
watch -n 5 'oc get csv -A | grep -E "devspaces|mta"'

# Pod状態監視
watch -n 5 'oc get pods -A | grep -E "devspaces|mta|user0"'
```

## ステップ 7: 検証

```bash
cd /Users/kamori/vscode/developer-lightspeed/workshop-provisioning

# ステータス確認スクリプト
./scripts/status-check.sh

# または検証Playbook
ansible-playbook ansible/playbooks/verify.yml \
  -i ansible/inventory/test/hosts.yml

# Makefileターゲット
INVENTORY=ansible/inventory/test/hosts.yml make verify
```

**期待される結果**:
- ✓ GitOps Operator: Ready
- ✓ Dev Spaces Operator: Ready
- ✓ MTA Operator: Ready
- ✓ Dev Spaces Instance: Available
- ✓ MTA Instance: Created
- ✓ User Namespaces: 2/2 (user01-dev, user02-dev)
- ✓ DevWorkspaces: 2/2

## ステップ 8: ユーザー資格情報確認

```bash
# CSV確認
cat artifacts/workshop-users.csv

# HTML生成
./scripts/generate-user-list.sh html
open artifacts/workshop-user-list.html
```

## ステップ 9: ユーザーログインテスト

```bash
# user01でログイン
oc login -u user01 -p <artifacts/workshop-users.csvから取得>

# 自分のnamespaceアクセス確認
oc get pods -n user01-dev

# 他人のnamespaceアクセス確認（失敗するはず）
oc get pods -n user02-dev  # Error: Forbiddenが期待される

# 管理者に戻る
oc login -u kube:admin
```

## ステップ 10: Dev Spaces アクセステスト

```bash
# Dev Spaces URLを取得
DEVSPACES_URL=$(oc get route devspaces -n openshift-devspaces -o jsonpath='{.spec.host}')
echo "Dev Spaces Dashboard: https://$DEVSPACES_URL"

# ブラウザで開く
open "https://$DEVSPACES_URL"
```

1. user01でログイン
2. Workspaceを起動: "spring-to-quarkus-user01"
3. デモアプリがcloneされているか確認
4. MTA拡張が利用可能か確認

## ステップ 11: クリーンアップ

### テスト後の完全削除

```bash
cd /Users/kamori/vscode/developer-lightspeed/workshop-provisioning

# ユーザーリソースのみ削除
./scripts/cleanup-gitops.sh users

# 全削除（Root Applicationも）
export CLEANUP_ROOT=true
./scripts/cleanup-gitops.sh all

# または手動
ansible-playbook ansible/playbooks/destroy.yml \
  -i ansible/inventory/test/hosts.yml \
  -e destroy_scope=all \
  -e confirm_destroy=true
```

## トラブルシューティング

### Issue 1: GitOps リポジトリ接続エラー

**症状**: "Failed to connect to GitOps repository"

**解決策**:
```bash
# ローカルテストの場合、Root Applicationを手動で調整
# gitops/bootstrap/root-application.yamlのrepoURLを確認
```

### Issue 2: LLM Secret エラー

**症状**: Solution Server起動失敗

**解決策**:
```bash
# Solution Serverを無効化してテスト
ansible-playbook ansible/playbooks/bootstrap.yml \
  -i ansible/inventory/test/hosts.yml \
  -e solution_server_enabled=false
```

### Issue 3: Tackle CR フィールドエラー

**症状**: MTA Tackle CR作成失敗

**解決策**:
```bash
# MTA Operatorインストール後にCRD確認
oc explain tackle.spec --recursive

# gitops/platform-instances/mta/tackle.yamlを調整
vim gitops/platform-instances/mta/tackle.yaml
```

### Issue 4: Workspace起動失敗

**症状**: DevWorkspace stuck in Starting

**解決策**:
```bash
# Pod状態確認
oc get pods -n user01-dev
oc describe pod <workspace-pod> -n user01-dev

# リソース不足の場合
# ansible/inventory/test/hosts.ymlでメモリ削減
# workspace_memory_limit: "4Gi"
```

## 推奨テストフロー（最小構成）

LLM API KeyやGitリポジトリが準備できない場合の最小テスト:

```bash
# 1. 設定作成（上記ステップ1）

# 2. Solution Server無効化
vim ansible/inventory/test/hosts.yml
# solution_server_enabled: false に設定

# 3. Preflight
ansible-playbook ansible/playbooks/bootstrap.yml \
  -i ansible/inventory/test/hosts.yml \
  --tags preflight

# 4. ユーザーとNamespaceのみプロビジョニング
ansible-playbook ansible/playbooks/bootstrap.yml \
  -i ansible/inventory/test/hosts.yml \
  -e workshop_user_count=2 \
  -e solution_server_enabled=false

# 5. 検証
./scripts/status-check.sh

# 6. クリーンアップ
./scripts/cleanup-gitops.sh all
```

## 次のステップ

テストが成功したら:

1. 本番用のGitリポジトリをセットアップ
2. 実際のLLM API Keyを設定
3. MTA Tackle CRを対象クラスタCRDに合わせて調整
4. ユーザー数を増やしてテスト (5, 10, 20)
5. 本番デプロイ

---

**質問やエラーが発生した場合**: docs/TROUBLESHOOTING.md を参照してください。
