# 新規クラスターへのワークショップ環境デプロイ手順

**対象クラスター**: cluster-jxznt.jxznt.sandbox3409.opentlc.com  
**デプロイ日時**: 2026-07-15  
**デプロイ方法**: 完全自動化（Ansible + GitOps + スクリプト）

## 目次

1. [前提条件](#前提条件)
2. [クラスター情報](#クラスター情報)
3. [デプロイ手順](#デプロイ手順)
4. [デプロイ内容](#デプロイ内容)
5. [検証手順](#検証手順)
6. [トラブルシューティング](#トラブルシューティング)

---

## 前提条件

### 必要なツール

| ツール | バージョン | インストール方法 |
|--------|-----------|---------------|
| `oc` CLI | 4.12+ | https://mirror.openshift.com/pub/openshift-v4/clients/ocp/ |
| `ansible-playbook` | 2.15+ | `pip install ansible` |
| `git` | 2.x+ | システムパッケージマネージャー |

### 必要な権限

- OpenShiftクラスターへの **cluster-admin** 権限
- GitHubリポジトリへのアクセス（公開リポジトリの場合は不要）

### 必要な情報

✅ すべて揃っています：

- ✓ クラスターAPI URL
- ✓ 管理者認証情報（kubeadmin）
- ✓ LLM APIキー（MTA Solution Server用）
- ✓ GitOpsリポジトリURL
- ✓ デモアプリケーションリポジトリURL

---

## クラスター情報

### 基本情報

```yaml
cluster:
  name: cluster-jxznt
  api_url: https://api.cluster-jxznt.jxznt.sandbox3409.opentlc.com:6443
  console_url: https://console-openshift-console.apps.cluster-jxznt.jxznt.sandbox3409.opentlc.com
  domain: apps.cluster-jxznt.jxznt.sandbox3409.opentlc.com

admin:
  username: kubeadmin
  password: q6dBD-wCK9C-zwnjI-4ac3c
```

### LLM Configuration (MTA Solution Server)

```yaml
llm:
  provider: ChatOpenAI
  model: gpt-oss-120b
  api_base: https://maas-rhdp.apps.maas.redhatworkshops.io/v1
  api_key: sk-k6yUFWReBsfsLzDmPWFn9w
```

**APIキーのテスト**:
```bash
curl -X POST https://maas-rhdp.apps.maas.redhatworkshops.io/v1/chat/completions \
  -H "Authorization: Bearer sk-k6yUFWReBsfsLzDmPWFn9w" \
  -H "Content-Type: application/json" \
  -d '{
    "model": "gpt-oss-120b",
    "messages": [{"role": "user", "content": "Hello, world!"}]
  }'
```

### ワークショップ設定

```yaml
workshop:
  user_count: 10
  username_prefix: user
  password: openshift
  users:
    - user01 / openshift
    - user02 / openshift
    - ...
    - user10 / openshift

repositories:
  gitops: https://github.com/kamorisan/rhdl-workshop-provision.git
  demo_app: https://github.com/kamorisan/coolstore-eap7.git
```

---

## デプロイ手順

### ステップ0: 事前準備

```bash
# 1. リポジトリのクローン（まだの場合）
cd ~/vscode
git clone https://github.com/kamorisan/rhdl-workshop-provision.git workshop-provisioning
cd workshop-provisioning

# 2. OpenShiftクラスターにログイン
oc login https://api.cluster-jxznt.jxznt.sandbox3409.opentlc.com:6443 \
  -u kubeadmin \
  -p q6dBD-wCK9C-zwnjI-4ac3c

# 3. cluster-admin権限の確認
oc auth can-i '*' '*' --all-namespaces
# => yes が返ればOK
```

### ⚠️ 手動デプロイ時の注意事項

`auto-deploy-new-cluster.sh` を使わず手動でデプロイする場合、以下の設定が**必須**です：

#### 必須変数チェックリスト

**ansible/inventory/production/hosts.yml**:
```yaml
vars:
  # ✅ これらの変数が必須
  cluster_api_url: "https://api.cluster-xxx.opentlc.com:6443"
  cluster_validate_certs: false
  demo_repository_url: "https://github.com/kamorisan/coolstore-eap7"  # demo_app_repo_url ではない
  demo_repository_revision: "main"
```

**ansible/group_vars/all.yml**:
```yaml
# ✅ cluster_api_url が空でないこと
cluster_api_url: "https://api.cluster-xxx..."  # "" はNG

# ✅ 変数名が一致していること
demo_repository_url: "https://github.com/kamorisan/coolstore-eap7"  # demo_app_repo_url ではない
```

**よくある間違い**:
- ❌ `cluster_api_url: ""`（空文字列）→ preflightで `'cluster_validate_certs' is undefined` エラー
- ❌ `demo_app_repo_url`（誤った変数名）→ preflightで `'demo_repository_url' is undefined` エラー
- ❌ inventoryとall.ymlで変数名が異なる → 優先順位の問題でエラー

**デプロイ前の確認コマンド**:
```bash
# Preflight単独実行でエラーがないか確認
VAULT_PASSWORD="workshop" ansible-playbook \
  -i ansible/inventory/production/hosts.yml \
  ansible/playbooks/preflight.yml \
  --vault-password-file=<(echo "$VAULT_PASSWORD") \
  -e @ansible/group_vars/vault.yml

# 成功すれば "ok=XX changed=0 failed=0" となる
```

---

### ステップ1: 自動デプロイスクリプトの実行（推奨）

**実行コマンド**:
```bash
cd /Users/kamori/vscode/developer-lightspeed/workshop-provisioning

# スクリプトに実行権限を付与
chmod +x scripts/setup/auto-deploy-new-cluster.sh

# 完全自動デプロイを実行
./scripts/setup/auto-deploy-new-cluster.sh
```

**実行時間**: 約 **30-40分**

**処理内容**:
1. ✓ 前提条件チェック（oc CLI, Ansible, 権限）
2. ✓ インベントリ自動生成（クラスター情報を自動検出）
3. ✓ Vault自動生成（LLM APIキー、ユーザーパスワード）
4. ✓ **all.yml更新** - cluster_api_url, demo_repository_url等を自動設定
5. ✓ Ansibleコレクションインストール
6. ✓ **Preflight Check** - クラスター状態、Operator、リソースの検証
7. ✓ **Ansibleデプロイ実行**（GitOps Operator, htpasswd, Secrets）
8. ✓ Operatorの起動待機（GitOps, Dev Spaces, MTA）
9. ✓ Argo CD Applicationsの同期待機
10. ✓ **DevWorkspace作成**（全10ユーザー分）

**重要な自動設定項目**:
- `cluster_api_url`: oc whoami --show-serverから自動検出
- `cluster_validate_certs`: false（自己署名証明書対応）
- `demo_repository_url`: coolstore-eap7リポジトリ
- `gitops_repo_url`: rhdl-workshop-provisionリポジトリ

これらの変数は**preflightチェックで必須**です。手動デプロイの場合は必ず設定してください。

### ステップ2: デプロイ状況の確認

デプロイ中、別のターミナルで進捗を確認できます：

```bash
# Argo CD Applicationsの状態
oc get applications -n openshift-gitops

# Dev Spaces Operatorの状態
oc get csv -n openshift-operators | grep devspaces

# MTA Operatorの状態
oc get csv -n openshift-mta | grep mta

# ユーザーnamespace
oc get namespaces | grep user
```

---

## デプロイ内容

### 1. Operators（Ansibleでデプロイ）

| Operator | Namespace | Channel | 説明 |
|----------|-----------|---------|------|
| OpenShift GitOps | openshift-gitops | latest | Argo CD（GitOps管理） |
| OpenShift Dev Spaces | openshift-operators | stable | Cloud IDE |
| MTA Operator | openshift-mta | stable-v8.1 | Migration Toolkit for Applications |

### 2. Platform Instances（GitOpsでデプロイ）

| リソース | Namespace | 説明 |
|---------|-----------|------|
| CheCluster (devspaces) | openshift-devspaces | Dev Spaces インスタンス |
| Tackle CR | openshift-mta | MTA Hub インスタンス |
| Solution Server Deployment | openshift-mta | Kai (LLM統合) |

### 3. 認証設定（Ansibleでデプロイ）

- **OAuth**: htpasswd identity provider
- **Users**: user01-user10（パスワード: `openshift`）
- **Secret**: htpasswd-secret（10ユーザーのハッシュ）

### 4. ユーザーリソース（GitOpsでデプロイ）

各ユーザーごとに以下が作成されます：

```
user01/
├── Namespaces
│   ├── user01-dev           # 開発用namespace
│   └── user01-devspaces     # Dev Spaces workspace用
├── RBAC
│   ├── view role binding     # 他namespaceへの参照権限
│   └── edit role binding     # 自分のnamespaceへの編集権限
├── ResourceQuota
│   ├── pods: 10
│   ├── cpu: 2-4 cores
│   └── memory: 16-32 Gi
└── LimitRange
    ├── Container: 100m-2000m CPU, 128Mi-8Gi memory
    └── Pod: 100m-4000m CPU, 128Mi-16Gi memory
```

### 5. DevWorkspaces（スクリプトでデプロイ）

各ユーザーごとに1つのワークスペースが作成されます：

```yaml
apiVersion: workspace.devfile.io/v1alpha2
kind: DevWorkspace
metadata:
  name: coolstore-modernization-workshop
  namespace: user01-devspaces
spec:
  started: false  # 初回は停止状態
  routingClass: che
  contributions:
    - name: editor
      kubernetes:
        name: che-code-coolstore-modernization-workshop  # che-code IDE
  template:
    projects:
      - name: coolstore-eap7  # GitHubからクローン
    components:
      - name: dev-tools       # UDI (Universal Developer Image)
    commands:
      - oc-auto-login         # OpenShift自動ログイン
      - setup-mta-config      # MTA設定コピー
      - maven-build           # ビルド
    events:
      postStart:
        - setup-mta-config    # 起動時に自動実行
```

### 6. VS Code Extensions（プロジェクトで設定）

coolstore-eap7リポジトリの `.vscode/extensions.json` で指定：

```json
{
  "recommendations": [
    "redhat.mta-core",      // Red Hat Developer Lightspeed
    "redhat.java",          // Java言語サポート
    "redhat.vscode-xml"     // XML/Mavenサポート
  ]
}
```

---

## 検証手順

### 1. Operatorの確認

```bash
# GitOps Operator
oc get csv -n openshift-gitops | grep gitops
# => openshift-gitops-operator.xxx   Succeeded

# Dev Spaces Operator
oc get csv -n openshift-operators | grep devspaces
# => devspaces.xxx   Succeeded

# MTA Operator
oc get csv -n openshift-mta | grep mta
# => mta-operator.xxx   Succeeded
```

### 2. Argo CD Applicationsの確認

```bash
oc get applications -n openshift-gitops

# 期待される出力（6つのApplication）:
# NAME                      SYNC STATUS   HEALTH STATUS
# workshop-operators        Synced        Healthy
# workshop-platform         Synced        Healthy
# workshop-namespaces       Synced        Healthy
# workshop-resources        Synced        Healthy
# workshop-cluster-config   Synced        Healthy
# root                      Synced        Healthy
```

### 3. ユーザーnamespaceの確認

```bash
oc get namespaces | grep user

# 期待される出力（20個のnamespace）:
# user01-dev
# user01-devspaces
# user02-dev
# user02-devspaces
# ...
# user10-dev
# user10-devspaces
```

### 4. DevWorkspaceの確認

```bash
# 全ワークスペース一覧
oc get devworkspace --all-namespaces | grep coolstore

# 特定ユーザーのワークスペース
oc get devworkspace -n user01-devspaces

# 期待される出力:
# NAME                               DEVWORKSPACE ID   PHASE     INFO
# coolstore-modernization-workshop   workspaceXXXX     Stopped   Stopped
```

### 5. エンドポイントの確認

```bash
# GitOps Console
oc get route openshift-gitops-server -n openshift-gitops -o jsonpath='{.spec.host}'
# => openshift-gitops-server-openshift-gitops.apps.cluster-jxznt...

# Dev Spaces
oc get route devspaces -n openshift-devspaces -o jsonpath='{.spec.host}'
# => devspaces.apps.cluster-jxznt...

# MTA Hub
oc get route tackle -n openshift-mta -o jsonpath='{.spec.host}'
# => tackle-openshift-mta.apps.cluster-jxznt...
```

### 6. ユーザーログインテスト

```bash
# user01でログイン
oc login https://api.cluster-jxznt.jxznt.sandbox3409.opentlc.com:6443 \
  -u user01 \
  -p openshift

# 自分のnamespaceが見えることを確認
oc get namespaces | grep user01
# => user01-dev
# => user01-devspaces

# 他ユーザーのnamespaceは見えない（viewのみ）
oc get pods -n user02-dev
# => エラーまたは空
```

### 7. Dev Spacesワークスペース起動テスト

```bash
# kubeadminに戻る
oc login -u kubeadmin -p q6dBD-wCK9C-zwnjI-4ac3c

# user01のワークスペースを起動
oc patch devworkspace coolstore-modernization-workshop \
  -n user01-devspaces \
  --type merge \
  -p '{"spec":{"started":true}}'

# 起動を待つ（30-60秒）
watch oc get devworkspace -n user01-devspaces

# 期待される出力:
# NAME                               PHASE     INFO
# coolstore-modernization-workshop   Running   https://devspaces.apps...
```

### 8. ワークスペース内容の確認

```bash
# Podに入る
POD=$(oc get pods -n user01-devspaces -o name | grep -v deploy | head -1)
oc exec -n user01-devspaces ${POD##*/} -c dev-tools -- bash -c "ls -la /projects/"

# 期待される出力:
# coolstore-eap7/   # GitHubからクローンされたプロジェクト

# MTA設定の確認
oc exec -n user01-devspaces ${POD##*/} -c dev-tools -- bash -c \
  "cat /checode/remote/data/User/globalStorage/redhat.mta-core/settings/provider-settings.yaml"

# 期待される出力:
# models:
#   OpenAI: &active
#     environment:
#       OPENAI_API_KEY: "sk-k6yUFWReBsfsLzDmPWFn9w"
#     ...
```

---

## トラブルシューティング

### Issue -1: Root Application - repoURL が空でデプロイ失敗

**症状**:
```bash
oc get application workshop-root -n openshift-gitops
NAME            SYNC STATUS   HEALTH STATUS
workshop-root   Unknown       Unknown

# エラーメッセージ
spec.source.repoURL and either spec.source.path or spec.source.chart are required
```

**原因**: 
- Ansible bootstrap実行時に `gitops.repo_url` が空文字列のままだった
- `auto-deploy-new-cluster.sh` の all.yml 更新ステップで sed 置換が失敗
- inventoryに `gitops_repo_url` が設定されていなかった

**解決方法**:

```bash
# 1. Root Applicationのrepo URLを手動で設定
oc patch application workshop-root -n openshift-gitops --type merge -p '
{
  "spec": {
    "source": {
      "repoURL": "https://github.com/kamorisan/rhdl-workshop-provision.git"
    }
  }
}'

# 2. 手動Sync実行
oc patch application workshop-root -n openshift-gitops --type merge -p '
{
  "metadata": {
    "annotations": {
      "argocd.argoproj.io/refresh": "normal"
    }
  }
}'

# 3. 子Applicationsが作成されたことを確認
oc get applications -n openshift-gitops
# => workshop-operators, workshop-platform-instances などが表示されればOK
```

**予防策**:
- **inventory に gitops_repo_url を追加**（最も確実）:
  ```yaml
  # ansible/inventory/production/hosts.yml
  vars:
    gitops_repo_url: "https://github.com/kamorisan/rhdl-workshop-provision.git"
    gitops_repo_revision: "main"
  ```

- デプロイ後、Root Application の状態を必ず確認:
  ```bash
  oc get application workshop-root -n openshift-gitops -o yaml | grep repoURL
  # => 空でないことを確認
  ```

**スクリプト修正** (次回デプロイ時の対応):
```bash
# auto-deploy-new-cluster.sh の inventory生成部分に追加
gitops_repo_url: https://github.com/kamorisan/rhdl-workshop-provision.git
gitops_repo_revision: main
```

---

### Issue 0: Preflight Check - 変数未定義エラー

**症状**:
```bash
fatal: [localhost]: FAILED! => 
  msg: |-
    'demo_repository_url' is undefined
    # または
    'cluster_validate_certs' is undefined
```

**原因**: 
- inventoryファイルとall.ymlの変数名が不一致
- 自動生成スクリプトで使用している変数名がpreflightロールの期待値と異なる

**解決方法**:

```bash
# 1. inventoryファイルを確認
cat ansible/inventory/production/hosts.yml

# 以下の変数が定義されていることを確認:
# - cluster_api_url: "https://api.cluster-xxx..."
# - cluster_validate_certs: false
# - demo_repository_url: "https://github.com/..."  (demo_app_repo_url ではない)
# - demo_repository_revision: "main"

# 2. 変数が不足している場合、手動で追加
vim ansible/inventory/production/hosts.yml

# vars: セクションに追加
cluster_api_url: "https://api.cluster-jxznt.jxznt.sandbox3409.opentlc.com:6443"
cluster_validate_certs: false
demo_repository_url: "https://github.com/kamorisan/coolstore-eap7"
demo_repository_revision: "main"

# 3. all.ymlも確認（バックアップ推奨）
cp ansible/group_vars/all.yml ansible/group_vars/all.yml.bak
vim ansible/group_vars/all.yml

# cluster_api_url が空でないことを確認
cluster_api_url: "https://api.cluster-xxx..."  # 空文字列はNG

# 4. 再デプロイ
VAULT_PASSWORD="workshop" ./scripts/setup/deploy-workshop.sh
```

**予防策**:
- `auto-deploy-new-cluster.sh` を使用（自動で正しい変数名を設定）
- デプロイ前にpreflightを単独実行して確認:
  ```bash
  VAULT_PASSWORD="workshop" ansible-playbook \
    -i ansible/inventory/production/hosts.yml \
    ansible/playbooks/preflight.yml \
    --vault-password-file=<(echo "$VAULT_PASSWORD") \
    -e @ansible/group_vars/vault.yml
  ```

---

### Issue 1: Operatorが "Succeeded" にならない

**症状**:
```bash
oc get csv -n openshift-devspaces
# => devspaces.xxx   Installing   (長時間)
```

**原因**: リソース不足、イメージプル失敗

**対処**:
```bash
# Podの状態確認
oc get pods -n openshift-devspaces

# イベント確認
oc get events -n openshift-devspaces --sort-by='.lastTimestamp'

# ログ確認
oc logs -n openshift-devspaces <pod-name>
```

### Issue 2: Argo CD ApplicationがOutOfSync

**症状**:
```bash
oc get applications -n openshift-gitops
# => workshop-resources   OutOfSync   Missing
```

**対処**:
```bash
# 手動でSync実行
oc patch application workshop-resources \
  -n openshift-gitops \
  --type merge \
  -p '{"metadata":{"annotations":{"argocd.argoproj.io/refresh":"normal"}}}'

# Sync波の順序を確認
oc get application workshop-resources -n openshift-gitops -o yaml | grep sync-wave

# AppProjectの権限確認
oc get appproject workshop-users -n openshift-gitops -o yaml
```

### Issue 3: DevWorkspaceが起動しない

**症状**:
```bash
oc get devworkspace -n user01-devspaces
# => coolstore-modernization-workshop   Failed   ...
```

**対処**:
```bash
# DevWorkspace詳細
oc get devworkspace coolstore-modernization-workshop -n user01-devspaces -o yaml

# Pod状態
oc get pods -n user01-devspaces

# LimitRange確認
oc get limitrange -n user01-devspaces -o yaml

# リソース超過の場合
oc describe devworkspace coolstore-modernization-workshop -n user01-devspaces
```

### Issue 4: 拡張機能がインストールされない

**症状**: MTA拡張機能がVS Codeに表示されない

**対処**:
```bash
# che-code-runtimeのattributes確認
oc get devworkspacetemplate che-code-coolstore-modernization-workshop \
  -n user01-devspaces \
  -o jsonpath='{.spec.components[?(@.name=="che-code-runtime")].attributes}'

# 期待される出力:
# {
#   "che-code.eclipse.org/vscode-extensions": [
#     "https://open-vsx.org/api/redhat/mta-core/..."
#   ]
# }

# ワークスペースを再作成
oc delete devworkspace coolstore-modernization-workshop -n user01-devspaces
# 再度create-all-workspaces.shを実行
```

### Issue 5: MTA provider-settings.yamlがコピーされない

**症状**: setup-mta-configコマンドが失敗

**対処**:
```bash
# Podに入って手動確認
POD=$(oc get pods -n user01-devspaces -o name | head -1)

# ソースファイルの存在確認
oc exec -n user01-devspaces ${POD##*/} -c dev-tools -- \
  ls -la /projects/coolstore-eap7/.devspaces/

# 手動コピー
oc exec -n user01-devspaces ${POD##*/} -c dev-tools -- bash -c \
  'mkdir -p /checode/remote/data/User/globalStorage/redhat.mta-core/settings && \
   cp /projects/coolstore-eap7/.devspaces/provider-settings.yaml \
      /checode/remote/data/User/globalStorage/redhat.mta-core/settings/'
```

---

## デプロイ後の確認チェックリスト

- [ ] 3つのOperatorがすべて "Succeeded"
- [ ] 6つのArgo CD Applicationsがすべて "Synced" かつ "Healthy"
- [ ] 20個のユーザーnamespaceが存在（userXX-dev, userXX-devspaces）
- [ ] 10個のDevWorkspaceが作成済み（Stopped状態）
- [ ] user01でログインして自分のnamespaceにアクセス可能
- [ ] user01のワークスペースが起動可能（Running状態）
- [ ] ワークスペース内にcoolstore-eap7プロジェクトがクローン済み
- [ ] MTA拡張機能が推奨として表示される
- [ ] provider-settings.yamlが正しい場所にコピー済み

---

## 参考情報

### エンドポイント一覧

| サービス | URL |
|---------|-----|
| OpenShift Console | https://console-openshift-console.apps.cluster-jxznt.jxznt.sandbox3409.opentlc.com |
| GitOps (Argo CD) | https://openshift-gitops-server-openshift-gitops.apps.cluster-jxznt... |
| Dev Spaces | https://devspaces.apps.cluster-jxznt... |
| MTA Hub | https://tackle-openshift-mta.apps.cluster-jxznt... |

### 自動化スクリプト一覧

| スクリプト | 用途 |
|-----------|------|
| `scripts/setup/auto-deploy-new-cluster.sh` | 完全自動デプロイ |
| `scripts/setup/deploy-workshop.sh` | Ansibleデプロイ実行 |
| `scripts/workspace/setup-all-workspaces.sh` | ワークスペース一括作成 |
| `scripts/workspace/setup-user-permissions.sh` | ユーザー権限設定 |
| `scripts/workspace/setup-che-code-templates.sh` | che-codeテンプレート作成 |
| `scripts/workspace/create-all-workspaces.sh` | DevWorkspace作成 |

### 設定ファイル一覧

| ファイル | 説明 |
|---------|------|
| `ansible/inventory/production/hosts.yml` | クラスター情報（自動生成） |
| `ansible/group_vars/vault.yml` | 機密情報（LLM APIキーなど） |
| `gitops/config/workshop-values.yaml` | ワークショップ設定 |
| `scripts/workspace/devworkspace-template.yaml` | DevWorkspaceテンプレート |

---

## まとめ

この手順により、以下が完全自動でデプロイされます：

1. **Operators**: GitOps, Dev Spaces, MTA（Ansibleで管理）
2. **Platform**: Argo CD, Dev Spaces CR, Tackle CR, Solution Server（GitOpsで管理）
3. **Users**: 10ユーザー、htpasswd認証（Ansibleで管理）
4. **Namespaces**: 20個（userXX-dev, userXX-devspaces）（GitOpsで管理）
5. **RBAC**: view/edit role bindings（GitOpsで管理）
6. **Workspaces**: 10個のDevWorkspace（スクリプトで管理）

**所要時間**: 約30-40分

**再現性**: すべてスクリプト化されており、何度でも同じ結果が得られます

**クリーンアップ**: 不要になったら、Argo CD Applicationsを削除すればすべてのリソースが自動削除されます

---

## よくある質問 (FAQ)

### Q1: ワークスペース起動時に既にtargetフォルダが存在するのはなぜ？

**A**: coolstore-eap7リポジトリに `.gitignore` がなく、誤ってビルド成果物がコミットされていた場合に発生します。

**確認方法**:
```bash
# GitHubリポジトリを確認
git clone https://github.com/kamorisan/coolstore-eap7
cd coolstore-eap7
ls -la target/  # targetフォルダが存在するか
cat .gitignore  # .gitignoreが存在するか
```

**解決済み**: coolstore-eap7リポジトリに `.gitignore` を追加し、Maven/IDE/OSの一時ファイルを除外するよう設定しました。

**今後のベストプラクティス**:
- 新しいデモアプリケーションリポジトリを作成する際は、必ず `.gitignore` を最初に追加
- `target/`, `.idea/`, `.DS_Store` などのビルド成果物・一時ファイルは絶対にコミットしない
- リポジトリテンプレートに `.gitignore` を含める
