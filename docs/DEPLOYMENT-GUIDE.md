# Workshop Complete Deployment Guide

**対象**: 新規OpenShift環境への完全デプロイ手順  
**前提条件**: OpenShift 4.x クラスタ、cluster-admin権限

---

## 📋 概要

このガイドは、ゼロからワークショップ環境を構築する完全な手順を記載しています。

### デプロイされるコンポーネント

1. **GitOps基盤**: OpenShift GitOps (Argo CD)
2. **ワークショップNamespaces**: user01-dev ~ user10-dev
3. **Platform Services**:
   - Gitea (Git server)
   - OpenShift DevSpaces
   - PostgreSQL (各ユーザーnamespaceに1台)
4. **ユーザーリポジトリ**: coolstore-eap7 (user01-user10の各Gitea)

---

## 🚀 デプロイ手順

### Phase 1: 前提条件の確認

#### 1.1 クラスタ情報取得

```bash
# クラスタにログイン
oc login <cluster-url> -u <admin-user>

# クラスタ情報確認
oc cluster-info
oc whoami --show-server
oc get nodes

# Cluster domain取得 (後の手順で使用)
CLUSTER_DOMAIN=$(oc get ingresses.config.openshift.io cluster -o jsonpath='{.spec.domain}')
echo "Cluster domain: ${CLUSTER_DOMAIN}"
```

**重要**: `CLUSTER_DOMAIN`を記録してください（例: `apps.cluster-abc123.example.com`）

#### 1.2 リポジトリクローン

```bash
git clone https://github.com/kamorisan/rhdl-workshop-provision.git
cd rhdl-workshop-provision
```

---

### Phase 2: 環境固有値の設定

⚠️ **重要**: 新規クラスターへのデプロイ時は、環境固有のURL（クラスタードメイン、Gitea URL）を必ず書き換えてください。

#### 2.1 クラスタードメイン設定

Phase 1で取得した`CLUSTER_DOMAIN`を使用して、すべての設定ファイルを更新します。

```bash
# 環境変数確認（Phase 1で取得済み）
echo "Cluster domain: ${CLUSTER_DOMAIN}"
# 例: apps.cluster-jxznt.jxznt.sandbox3409.opentlc.com

# デフォルトドメイン（書き換え対象）
DEFAULT_DOMAIN="apps.cluster-jxznt.jxznt.sandbox3409.opentlc.com"

# 1. gitea-values.yaml更新
sed -i.bak "s|${DEFAULT_DOMAIN}|${CLUSTER_DOMAIN}|g" \
  gitops/config/gitea-values.yaml

# 2. workshop-values.yaml更新（⭐ EAP 8.1 Tekton Pipeline用）
sed -i.bak "s|${DEFAULT_DOMAIN}|${CLUSTER_DOMAIN}|g" \
  gitops/config/workshop-values.yaml

# 確認
echo "=== gitea-values.yaml ==="
grep "DOMAIN\|ROOT_URL" gitops/config/gitea-values.yaml

echo ""
echo "=== workshop-values.yaml ==="
grep -A2 "^cluster:" gitops/config/workshop-values.yaml
grep -A1 "^gitea:" gitops/config/workshop-values.yaml
```

**期待される結果**:
```yaml
# gitea-values.yaml
DOMAIN: gitea.apps.cluster-XXXXX.XXXXX.sandboxYYYY.opentlc.com
ROOT_URL: https://gitea.apps.cluster-XXXXX.XXXXX.sandboxYYYY.opentlc.com/

# workshop-values.yaml
cluster:
  domain: apps.cluster-XXXXX.XXXXX.sandboxYYYY.opentlc.com
  ingressDomain: apps.cluster-XXXXX.XXXXX.sandboxYYYY.opentlc.com
gitea:
  baseUrl: https://gitea-gitea.apps.cluster-XXXXX.XXXXX.sandboxYYYY.opentlc.com
```

**注意**: 
- `sed -i.bak`でバックアップファイル（`.bak`）を作成します
- macOSの場合は`sed -i ''`、Linuxの場合は`sed -i`を使用
- 書き換え漏れがないか、必ず確認してください

#### 2.2 Ansible Vault設定

Gitea管理者認証情報を設定：

```bash
# Vault作成 (初回のみ)
ansible-vault create ansible/group_vars/vault.yml
```

以下の内容を入力：

```yaml
---
# Gitea Admin Credentials
vault_gitea_admin_username: "gitea-admin"
vault_gitea_admin_password: "YOUR_STRONG_PASSWORD_HERE"  # 変更必須
vault_gitea_admin_email: "gitea-admin@workshop.local"

# Workshop User Password (全ユーザー共通)
vault_gitea_workshop_password: "openshift"
```

**セキュリティ**: `vault_gitea_admin_password`は強力なランダム値に変更してください。

---

### Phase 3: GitOpsデプロイ

#### 3.1 GitOps Bootstrap

```bash
# Root Applicationデプロイ
oc apply -f gitops/bootstrap/root-application.yaml

# 進捗確認
watch oc get applications -n openshift-gitops
```

**期待される結果** (5-10分後):
```
NAME                          SYNC STATUS   HEALTH STATUS
workshop-cluster-config       Synced        Healthy
workshop-namespaces           Synced        Healthy
workshop-operators            Synced        Healthy
workshop-platform-instances   Synced        Healthy
workshop-resources            Synced        Healthy
workshop-gitea                Synced        Healthy
workshop-root                 Synced        Healthy
```

#### 3.2 トラブルシューティング

Application OutOfSyncの場合：

```bash
# 詳細確認
oc get application <app-name> -n openshift-gitops -o yaml

# 手動sync
oc patch application <app-name> -n openshift-gitops \
  --type merge -p '{"metadata":{"annotations":{"argocd.argoproj.io/refresh":"hard"}}}'
```

---

### Phase 4: Ansible Secrets作成

#### 4.1 Gitea Secrets

```bash
cd ansible

# Vault password設定
echo "your-vault-password" > .vault_pass

# Secretsデプロイ
ansible-playbook playbooks/gitea-secrets.yml \
  --vault-password-file .vault_pass

# 確認
oc get secret -n gitea | grep gitea
```

**期待される結果**:
```
gitea-admin-secret          Opaque   3      10s
gitea-user-provisioning     Opaque   3      10s
```

---

### Phase 5: Gitea確認とユーザー作成

#### 5.1 Gitea起動確認

```bash
# Gitea Pod確認
oc get pods -n gitea -l app.kubernetes.io/name=gitea

# Route確認
GITEA_ROUTE=$(oc get route gitea -n gitea -o jsonpath='{.spec.host}')
echo "Gitea URL: https://${GITEA_ROUTE}"

# API確認
curl -I "https://${GITEA_ROUTE}/"
```

**期待される結果**: HTTP 200 OK

#### 5.2 ユーザー確認

Gitea user provisioningはPostSync Hookで自動実行されますが、確認します：

```bash
# 管理者認証情報取得
ADMIN_USER=$(oc get secret gitea-user-provisioning -n gitea -o jsonpath='{.data.admin-username}' | base64 -d)
ADMIN_PASS=$(oc get secret gitea-user-provisioning -n gitea -o jsonpath='{.data.admin-password}' | base64 -d)

# ユーザー確認
for i in $(seq -f "%02g" 1 10); do
  curl -fsS -u "${ADMIN_USER}:${ADMIN_PASS}" \
    "https://${GITEA_ROUTE}/api/v1/users/user${i}" | jq -r '.login'
done
```

**期待される結果**: user01 ~ user10が表示される

---

### Phase 6: Git Secrets作成 (S2Iビルド用)

#### 6.1 Git認証Secret作成

S2I BuildConfigがGiteaからソースをクローンするために必要なGit認証情報を作成：

```bash
cd ansible

# Git Secretsデプロイ
ansible-playbook playbooks/git-secrets.yml \
  --vault-password-file .vault_pass

# 確認
for i in $(seq -f "%02g" 1 10); do
  oc get secret gitea-git-secret -n "user${i}-dev" >/dev/null 2>&1 && echo "user${i}-dev: ✓" || echo "user${i}-dev: ✗"
done
```

**処理内容**:
1. 各user namespaceに`gitea-git-secret` (type: kubernetes.io/basic-auth) を作成
2. builder ServiceAccountにsecretをlink (`--for=mount`)
3. BuildConfigの`source.sourceSecret`で参照可能になる

**期待される結果**:
```
user01-dev: ✓
user02-dev: ✓
...
user10-dev: ✓
```

---

### Phase 7: Coolstore-EAP7リポジトリ配布

#### 7.1 自動配布スクリプト実行

```bash
cd ../scripts  # workshop-provisioning/scripts

# Gitea管理者パスワード設定
export GITEA_ADMIN_PASSWORD="${ADMIN_PASS}"

# 全ユーザーへcoolstore-eap7をコピー
./gitea-populate-coolstore.sh
```

**処理内容** (約2-3分):
1. GitHub ocp-s2i-eap7ブランチからクローン
2. 各ユーザー用にカスタマイズ:
   - `PROJECT_NAME`: user01-dev, user02-dev, ...
   - `GIT_REPOSITORY`: Gitea URL
   - `GIT_REF`: main (Giteaのデフォルトブランチ)
   - `sourceSecret`: gitea-git-secret (S2Iビルド用Git認証)
   - `devfile.yaml`作成 (DevSpaces用)
   - `.devspaces/setup-mta-config.sh` (MTA設定自動配置)
3. Giteaリポジトリ作成とpush

#### 7.2 配布確認

```bash
# 全ユーザーのリポジトリ確認
for i in $(seq -f "%02g" 1 10); do
  curl -fsS -u "${ADMIN_USER}:${ADMIN_PASS}" \
    "https://${GITEA_ROUTE}/api/v1/repos/user${i}/coolstore-eap7" \
    | jq -r '"\(.owner.login): \(.name) (\(.size) KB)"'
done
```

**期待される結果**:
```
user01: coolstore-eap7 (9866 KB)
user02: coolstore-eap7 (9866 KB)
...
user10: coolstore-eap7 (9866 KB)
```

#### 7.3 リポジトリ内容確認

配布されたリポジトリに必要なファイルが含まれていることを確認：

```bash
# user01のリポジトリをクローンして確認
git clone "https://${ADMIN_USER}:${ADMIN_PASS}@${GITEA_ROUTE}/user01/coolstore-eap7.git" /tmp/verify-repo
cd /tmp/verify-repo

# 重要ファイルの存在確認
echo "=== DevSpaces関連 ==="
ls -l devfile.yaml .devspaces/setup-mta-config.sh .devspaces/provider-settings.yaml

echo "=== デプロイスクリプト確認 ==="
grep "PROJECT_NAME=" scripts/openshift/eap7/01-setup.sh
grep "GIT_REPOSITORY=" scripts/openshift/eap7/01-setup.sh
grep "GIT_REF=" scripts/openshift/eap7/01-setup.sh
grep "sourceSecret" scripts/openshift/eap7/01-setup.sh
```

**期待される結果**:
- `PROJECT_NAME="user01-dev"`
- `GIT_REPOSITORY="https://gitea-gitea.<domain>/user01/coolstore-eap7.git"`
- `GIT_REF="main"`
- `sourceSecret` ブロックが存在

---

### Phase 7.5: EAP 8.1 Tekton Pipeline環境展開（オプション）

⚠️ **このPhaseはオプションです**: EAP 7からEAP 8.1への移行ワークショップを実施する場合のみ必要です。

#### 7.5.1 概要

このPhaseでは、EAP 8.1移行用のTekton Pipeline環境を展開します。

**展開されるリソース**:
- Tekton RoleBindings（image-builder/puller）
- Pipeline Workspace PVC（各ユーザー2Gi）
- workshop-imagesアクセス権限

**重要事項**:
- ✅ Phase 2でworkshop-values.yamlのURL書き換えが完了していること
- ✅ Pipeline定義は展開されますが、自動実行はされません
- ✅ ワークショップ本編でソースコードをEAP 8対応後、手動でPipelineを起動

#### 7.5.2 前提条件確認

```bash
# workshop-imagesが存在することを確認
oc get namespace workshop-images

# EAP 8.1イメージが存在することを確認
oc get imagestream -n workshop-images | grep eap81
```

**期待される結果**:
```
NAME            IMAGE REPOSITORY
eap81-builder   image-registry.openshift-image-registry.svc:5000/workshop-images/eap81-builder
eap81-runtime   image-registry.openshift-image-registry.svc:5000/workshop-images/eap81-runtime
```

**workshop-imagesが存在しない場合**:

```bash
# Namespace作成
oc create namespace workshop-images

# EAP 8.1イメージをpushまたはImportImageStream作成
# （詳細は別ドキュメント参照）
```

#### 7.5.3 GitOpsリソース確認

Phase 2でworkshop-values.yamlが正しく更新されていることを確認：

```bash
# クラスタードメイン確認
grep -A2 "^cluster:" gitops/config/workshop-values.yaml

# Gitea URL確認
grep -A1 "^gitea:" gitops/config/workshop-values.yaml

# Tekton設定確認
grep -A3 "^tekton:" gitops/config/workshop-values.yaml
```

**期待される結果**:
```yaml
cluster:
  domain: apps.cluster-XXXXX.XXXXX.sandboxYYYY.opentlc.com  # 環境のドメイン
  ingressDomain: apps.cluster-XXXXX.XXXXX.sandboxYYYY.opentlc.com

gitea:
  baseUrl: https://gitea-gitea.apps.cluster-XXXXX.XXXXX.sandboxYYYY.opentlc.com

tekton:
  pipelineWorkspaceSize: 2Gi
  storageClassName: gp3-csi
```

⚠️ **ドメインが`cluster-jxznt.jxznt.sandbox3409.opentlc.com`のままの場合**:

```bash
# Phase 2の手順を再実行
DEFAULT_DOMAIN="apps.cluster-jxznt.jxznt.sandbox3409.opentlc.com"
CLUSTER_DOMAIN=$(oc get ingresses.config.openshift.io cluster -o jsonpath='{.spec.domain}')

sed -i.bak "s|${DEFAULT_DOMAIN}|${CLUSTER_DOMAIN}|g" \
  gitops/config/workshop-values.yaml

# 確認
grep "domain:\|baseUrl:" gitops/config/workshop-values.yaml
```

#### 7.5.4 GitOps変更のコミット＆プッシュ

Phase 2でworkshop-values.yamlを更新した場合は、変更をコミット＆プッシュ：

```bash
cd /path/to/rhdl-workshop-provision

# 変更確認
git status

# workshop-values.yamlの変更をコミット
git add gitops/config/workshop-values.yaml
git commit -m "Update workshop-values.yaml for cluster domain

- Update cluster.domain and gitea.baseUrl to match current cluster
- Add EAP 8.1 Tekton Pipeline configuration
"

# プッシュ（フォークしている場合は自分のリポジトリへ）
git push origin main
```

#### 7.5.5 ArgoCD同期

```bash
# workshop-resourcesをRefresh
oc patch application workshop-resources -n openshift-gitops \
  --type merge \
  -p '{"metadata":{"annotations":{"argocd.argoproj.io/refresh":"hard"}}}'

# workshop-platform-instancesをRefresh
oc patch application workshop-platform-instances -n openshift-gitops \
  --type merge \
  -p '{"metadata":{"annotations":{"argocd.argoproj.io/refresh":"hard"}}}'

# 同期状況確認
watch oc get applications -n openshift-gitops
```

**期待される結果**（5分以内）:
```
NAME                          SYNC STATUS   HEALTH STATUS
workshop-resources            Synced        Healthy
workshop-platform-instances   Synced        Healthy
workshop-images-access        Synced        Healthy  # ← 新規追加
```

#### 7.5.6 リソース展開確認

**RoleBindings確認**:

```bash
# user01-devの権限確認
oc get rolebinding -n user01-dev | grep pipeline

# 期待される結果:
# openshift-pipelines-edit    ClusterRole/edit                        (TektonConfigが自動作成)
# pipelines-scc-rolebinding   ClusterRole/pipelines-scc-clusterrole   (TektonConfigが自動作成)
# pipeline-image-builder      ClusterRole/system:image-builder        (GitOpsで作成) ← 追加
# pipeline-image-puller        ClusterRole/system:image-puller         (GitOpsで作成) ← 追加
```

**PVC確認**:

```bash
# 全ユーザーのPVC確認
for i in $(seq -f "%02g" 1 10); do
  if oc get pvc pipeline-workspace-pvc -n "user${i}-dev" &>/dev/null; then
    echo "user${i}-dev: ✓"
  else
    echo "user${i}-dev: ✗"
  fi
done

# 期待される結果:
# user01-dev: ✓
# user02-dev: ✓
# ...
# user10-dev: ✓
```

**workshop-imagesアクセス権限確認**:

```bash
# workshop-images namespaceのRoleBindings確認
oc get rolebinding -n workshop-images | grep user

# 期待される結果（user01-user10分、各2個）:
# user01-pipeline-puller   ClusterRole/system:image-puller   
# user01-default-puller    ClusterRole/system:image-puller   
# user02-pipeline-puller   ClusterRole/system:image-puller   
# ...
```

**ServiceAccount確認（TektonConfig自動作成）**:

```bash
# user01-devのServiceAccount確認
oc get sa pipeline -n user01-dev -o yaml | grep -A3 ownerReferences

# 期待される結果（TektonConfigが管理）:
# ownerReferences:
# - apiVersion: operator.tekton.dev/v1alpha1
#   kind: TektonConfig
#   name: config
```

#### 7.5.7 トラブルシューティング

**Issue: ArgoCD同期エラー**

```bash
# Application詳細確認
oc get application workshop-images-access -n openshift-gitops -o yaml

# Helmテンプレート構文確認
cd gitops/platform-instances/workshop-images
helm template . --values ../../config/workshop-values.yaml

# 手動同期
oc patch application workshop-images-access -n openshift-gitops \
  --type merge \
  -p '{"operation":{"sync":{"retry":{"limit":"5"}}}}'
```

**Issue: PVC作成失敗（StorageClass not found）**

```bash
# 利用可能なStorageClass確認
oc get storageclass

# workshop-values.yamlのstorageClassNameを環境に合わせて修正
# 例: gp2, gp3, gp3-csi, thin, nfs-client など
```

#### 7.5.8 Phase 7.5完了チェック

- [ ] workshop-values.yamlのクラスタードメインが環境に合致
- [ ] Gitea baseUrlが環境に合致
- [ ] workshop-resources Application: Synced & Healthy
- [ ] workshop-platform-instances Application: Synced & Healthy
- [ ] workshop-images-access Application: Synced & Healthy
- [ ] 全ユーザーnamespaceに`pipeline-image-builder` RoleBinding作成済み
- [ ] 全ユーザーnamespaceに`pipeline-image-puller` RoleBinding作成済み
- [ ] 全ユーザーnamespaceに`pipeline-workspace-pvc` PVC作成済み
- [ ] workshop-images namespaceに全ユーザー分のRoleBinding作成済み
- [ ] ServiceAccount `pipeline`が存在（TektonConfigが自動作成）

**詳細手順**: [docs/eap8/20260722_DEPLOYMENT_GUIDE_Phase8.md](../Gitea/coolstore-eap7/docs/eap8/20260722_DEPLOYMENT_GUIDE_Phase8.md)

---

### Phase 8: DevSpaces Workspace作成

#### 8.1 DevSpaces起動確認

```bash
# DevSpaces Podステータス
oc get pods -n openshift-devspaces

# DevSpaces Route
DEVSPACES_URL=$(oc get route devspaces -n openshift-devspaces -o jsonpath='{.spec.host}')
echo "DevSpaces URL: https://${DEVSPACES_URL}"
```

#### 8.2 DevWorkspace一括作成

スクリプトで全ユーザーのDevWorkspaceを一括作成：

```bash
cd scripts/workspace

# 全ユーザーのDevWorkspace作成
./create-all-workspaces.sh
```

**処理内容**:
1. Gitea routeを自動検出
2. user01-user10のDevWorkspace CRを作成
3. Git URLに認証情報を埋め込み (`https://user01:openshift@gitea.../repo.git`)
4. postStart eventsを設定:
   - `setup-mta-config`: MTA設定自動配置
   - `oc-auto-login`: OpenShiftユーザー認証

**期待される結果**:
```
[1/10] Processing user01...
  ✅ DevWorkspace created
[2/10] Processing user02...
  ✅ DevWorkspace created
...
✅ DevWorkspace creation complete!
```

#### 8.3 DevWorkspace確認

```bash
# 全DevWorkspace確認
for i in $(seq -f "%02g" 1 10); do
  oc get devworkspace coolstore-modernization-workshop -n "user${i}-devspaces" -o jsonpath='{.metadata.name}{"\t"}{.spec.started}{"\n"}'
done
```

**期待される結果**: 全て`coolstore-modernization-workshop  false`（作成済み、未起動）

#### 8.4 ユーザーアクセステスト

ブラウザで各ユーザーとしてテスト：

1. DevSpaces URLにアクセス
2. user01 / openshiftでログイン
3. Workspace "coolstore-modernization-workshop"が表示される
4. "Open"をクリック
5. Workspaceが起動：
   - coolstore-eap7リポジトリがクローンされる
   - postStartイベントが実行される（MTA設定、oc login）
   - VS Code IDEが起動

---

### Phase 9: S2Iデプロイテスト（推奨）

#### 9.1 DevWorkspace起動

```bash
# user01のDevWorkspaceを起動
oc patch devworkspace coolstore-modernization-workshop -n user01-devspaces \
  --type=merge -p '{"spec":{"started":true}}'

# Pod起動確認
oc get pods -n user01-devspaces -w
```

#### 9.2 Workspace内でデプロイ実行

user01としてDevSpaces UIにブラウザアクセスし、Terminalで実行：

```bash
# 認証確認
oc whoami        # → user01
oc project -q    # → user01-dev

# デプロイスクリプト実行
cd /projects/coolstore-eap7/scripts/openshift/eap7
./01-setup.sh
./02-build.sh
./03-deploy.sh

# デプロイ確認
oc get pods -n user01-dev
oc get route coolstore-eap7 -n user01-dev
```

#### 9.3 アプリケーション動作確認

```bash
# Route URL取得
ROUTE=$(oc get route coolstore-eap7 -n user01-dev -o jsonpath='{.spec.host}')

# Products API確認
curl -sk "https://${ROUTE}/services/products" | jq -r '.[0:3] | .[] | {name, price}'

# Web UI確認
curl -sk "https://${ROUTE}/" | grep "Cool Store"
```

**期待される結果**:
- BuildConfig: Git cloneが成功（gitea-git-secret使用）
- S2I Build: PostgreSQL JDBCモジュールインストール成功
- Deployment: EAP7起動、PostgreSQL接続成功
- REST API: 商品データ取得可能
- Web UI: Cool Store MSAページ表示

---

## ✅ デプロイ完了チェックリスト

### GitOps

- [ ] workshop-root Application: Synced/Healthy
- [ ] All child Applications: Synced/Healthy
- [ ] Argo CD auto-prune enabled (prune: true)

### URL設定（環境固有）

⚠️ **新規クラスターデプロイ時は必ず確認**:
- [ ] gitops/config/gitea-values.yaml: クラスタードメインが環境に合致
- [ ] gitops/config/workshop-values.yaml: cluster.domainが環境に合致
- [ ] gitops/config/workshop-values.yaml: gitea.baseUrlが環境に合致

### Namespaces

- [ ] user01-dev ~ user10-dev 作成済み
- [ ] gitea namespace作成済み
- [ ] openshift-devspaces作成済み
- [ ] workshop-images作成済み（EAP 8.1使用時）

### Gitea

- [ ] Gitea Pod: Running
- [ ] Route: HTTPSアクセス可能
- [ ] user01-user10: 全員作成済み (password: openshift)
- [ ] coolstore-eap7リポジトリ: 全ユーザー配布済み
- [ ] devfile.yaml、.devspaces/setup-mta-config.sh含まれる
- [ ] 01-setup.shにsourceSecret設定含まれる

### Git Secrets (S2I用)

- [ ] gitea-git-secret: user01-dev ~ user10-dev全namespaceに作成済み
- [ ] builder ServiceAccount: secretリンク済み
- [ ] Secret type: kubernetes.io/basic-auth

### PostgreSQL

- [ ] 各user namespaceにPostgreSQL Pod: Running
- [ ] coolstore-db-secret: 全namespace作成済み
- [ ] PRODUCT_CATALOGテーブル: 9件のデータ

### DevSpaces

- [ ] DevSpaces Pod: Running
- [ ] Route: HTTPSアクセス可能
- [ ] DevWorkspace: user01-user10全員作成済み
- [ ] user01でWorkspace起動テスト成功
- [ ] postStart events: setup-mta-config、oc-auto-login実行確認

### S2Iデプロイ（推奨テスト）

- [ ] user01からS2Iビルド成功
- [ ] Git clone: Gitea認証成功
- [ ] Build: PostgreSQL JDBCモジュールインストール完了
- [ ] Deploy: EAP7 + PostgreSQL動作
- [ ] Application: REST API応答、Web UI表示

### EAP 8.1 Tekton Pipeline（Phase 7.5実施時）

- [ ] workshop-images-access Application: Synced/Healthy
- [ ] RoleBinding pipeline-image-builder: 全ユーザーnamespace作成済み
- [ ] RoleBinding pipeline-image-puller: 全ユーザーnamespace作成済み
- [ ] PVC pipeline-workspace-pvc: 全ユーザーnamespace作成済み（2Gi）
- [ ] workshop-images RoleBindings: userXX-pipeline-puller、userXX-default-puller作成済み
- [ ] ServiceAccount pipeline: 全ユーザーnamespace存在（TektonConfig自動作成）

---

## 🔧 環境固有のカスタマイズ

### ⚠️ 新規クラスターデプロイ時の必須手順

**新しいOpenShiftクラスターにデプロイする際は、Phase 2で必ずクラスタードメインを書き換えてください。**

以下のファイルにクラスタードメインがハードコーディングされています：

1. **gitops/config/gitea-values.yaml**
   - `gitea.config.server.DOMAIN`
   - `gitea.config.server.ROOT_URL`
   - `gitea.config.server.SSH_DOMAIN`

2. **gitops/config/workshop-values.yaml**（Phase 7.5: EAP 8.1使用時）
   - `cluster.domain`
   - `cluster.ingressDomain`
   - `gitea.baseUrl`

**Phase 2で実行すべきコマンド**:

```bash
# Phase 1でCLUSTER_DOMAINを取得済み
echo "Cluster domain: ${CLUSTER_DOMAIN}"

# デフォルトドメイン（書き換え対象）
DEFAULT_DOMAIN="apps.cluster-jxznt.jxznt.sandbox3409.opentlc.com"

# 両方のファイルを一括更新
sed -i.bak "s|${DEFAULT_DOMAIN}|${CLUSTER_DOMAIN}|g" \
  gitops/config/gitea-values.yaml

sed -i.bak "s|${DEFAULT_DOMAIN}|${CLUSTER_DOMAIN}|g" \
  gitops/config/workshop-values.yaml

# 確認
echo "=== gitea-values.yaml ==="
grep "DOMAIN\|ROOT_URL" gitops/config/gitea-values.yaml

echo "=== workshop-values.yaml ==="
grep "domain:\|baseUrl:" gitops/config/workshop-values.yaml
```

**書き換え後の例**:

```yaml
# gitea-values.yaml
DOMAIN: gitea.apps.cluster-abc123.sandbox9999.opentlc.com
ROOT_URL: https://gitea.apps.cluster-abc123.sandbox9999.opentlc.com/

# workshop-values.yaml
cluster:
  domain: apps.cluster-abc123.sandbox9999.opentlc.com
gitea:
  baseUrl: https://gitea-gitea.apps.cluster-abc123.sandbox9999.opentlc.com
```

### クラスタードメイン変更後の再実行

既にデプロイ済みで、Cluster domainが変わった場合：

```bash
# 1. 新しいクラスタードメイン取得
CLUSTER_DOMAIN=$(oc get ingresses.config.openshift.io cluster -o jsonpath='{.spec.domain}')
echo "New cluster domain: ${CLUSTER_DOMAIN}"

# 2. 設定ファイル更新
DEFAULT_DOMAIN="apps.cluster-jxznt.jxznt.sandbox3409.opentlc.com"  # または現在の値
sed -i.bak "s|${DEFAULT_DOMAIN}|${CLUSTER_DOMAIN}|g" gitops/config/gitea-values.yaml
sed -i.bak "s|${DEFAULT_DOMAIN}|${CLUSTER_DOMAIN}|g" gitops/config/workshop-values.yaml

# 3. Git commit & push
git add gitops/config/gitea-values.yaml gitops/config/workshop-values.yaml
git commit -m "Update cluster domain for new environment"
git push

# 4. Argo CD sync
oc patch application workshop-gitea -n openshift-gitops \
  --type merge -p '{"metadata":{"annotations":{"argocd.argoproj.io/refresh":"hard"}}}'

# 4. Coolstore再配布 (Gitea URL変更のため)
export GITEA_URL="https://gitea-gitea.${NEW_DOMAIN}"
./scripts/gitea-populate-coolstore.sh
```

---

## 📊 デプロイ時間目安

| フェーズ | 所要時間 |
|---------|---------|
| Phase 1-2: 前提条件・設定 | 10分 |
| Phase 3: GitOpsデプロイ | 5-10分 |
| Phase 4: Ansible Secrets (Gitea) | 2分 |
| Phase 5: Gitea確認 | 3分 |
| Phase 6: Git Secrets (S2I用) | 1分 |
| Phase 7: Coolstore配布 | 2-3分 |
| Phase 8: DevWorkspace作成 | 2分 |
| Phase 9: S2Iデプロイテスト | 5-10分 |
| **合計** | **約30-40分** |

---

## 🐛 トラブルシューティング

### Gitea PodがProgressing

**症状**: PVCがTerminatingで残る

**解決**:
```bash
# PVC finalizer削除
oc patch pvc gitea-shared-storage -n gitea \
  -p '{"metadata":{"finalizers":null}}' --type=merge

# Application hard refresh
oc patch application workshop-gitea -n openshift-gitops \
  --type merge -p '{"metadata":{"annotations":{"argocd.argoproj.io/refresh":"hard"}}}'
```

### Coolstore配布スクリプト失敗

**症状**: ユーザーリポジトリが作成されない

**確認事項**:
1. Gitea管理者パスワードが正しいか
2. Gitea APIが応答するか: `curl -I https://<gitea-route>/api/v1/version`
3. GitHubへの接続: `curl -I https://github.com/kamorisan/coolstore-eap7`

**再実行**:
```bash
# 特定ユーザーのみ再実行
USER_COUNT=1 ./scripts/gitea-populate-coolstore.sh  # user01のみ
```

### DevSpaces Workspaceが起動しない

**確認事項**:
1. devfile.yamlがリポジトリに存在するか
2. Git URLが正しいか（各ユーザーのGitea URL）
3. DevSpaces Podログ確認: `oc logs -n openshift-devspaces <pod>`

### S2I BuildがGit認証エラーで失敗

**症状**: `failed to fetch requested repository with provided credentials`

**原因**: gitea-git-secretが未作成、またはbuilder SAにリンクされていない

**解決**:
```bash
# Secret確認
oc get secret gitea-git-secret -n user01-dev

# builder SAリンク確認
oc describe sa builder -n user01-dev | grep gitea-git-secret

# 再作成
cd ansible
ansible-playbook playbooks/git-secrets.yml --vault-password-file .vault_pass
```

### MTA設定が自動配置されない

**症状**: DevWorkspace起動後、MTA拡張機能に設定が反映されない

**確認**:
```bash
# Pod内で確認
POD=$(oc get pods -n user01-devspaces -l controller.devfile.io/devworkspace_name=coolstore-modernization-workshop -o jsonpath='{.items[0].metadata.name}')

# postStartログ確認
oc exec -n user01-devspaces "$POD" -c dev-tools -- cat /tmp/setup-mta-config.log

# 設定ファイル確認
oc exec -n user01-devspaces "$POD" -c dev-tools -- ls -l /checode/remote/data/User/globalStorage/redhat.mta-core/settings/provider-settings.yaml
```

**手動実行** (暫定対応):
```bash
oc exec -n user01-devspaces "$POD" -c dev-tools -- bash /projects/coolstore-eap7/.devspaces/setup-mta-config.sh
```

---

## 📚 関連ドキュメント

- [coolstore-eap7環境固有値分析](../! miscellaneous/coolstore-eap7-environment-specific-values.md)
- [Gitea GitOps実装ガイド](../! miscellaneous/gitea-gitops-implementation-guide.md)
- [Gitea SCC問題解決レポート](../! miscellaneous/20260718_gitea-openshift-scc-troubleshooting-report.md)

---

## 🎯 新規クラスターへの完全再現手順まとめ

新しいクラスターで完全再現する場合の最小限コマンド：

```bash
# 1. リポジトリクローン
git clone https://github.com/kamorisan/rhdl-workshop-provision.git
cd rhdl-workshop-provision

# 2. Cluster domain取得
CLUSTER_DOMAIN=$(oc get ingresses.config.openshift.io cluster -o jsonpath='{.spec.domain}')
echo "Cluster domain: ${CLUSTER_DOMAIN}"

# ⚠️ 3. クラスタードメイン更新（必須！）
DEFAULT_DOMAIN="apps.cluster-jxznt.jxznt.sandbox3409.opentlc.com"

# gitea-values.yaml更新
sed -i.bak "s|${DEFAULT_DOMAIN}|${CLUSTER_DOMAIN}|g" \
  gitops/config/gitea-values.yaml

# workshop-values.yaml更新（EAP 8.1使用時）
sed -i.bak "s|${DEFAULT_DOMAIN}|${CLUSTER_DOMAIN}|g" \
  gitops/config/workshop-values.yaml

# 確認
echo "=== gitea-values.yaml ==="
grep "DOMAIN\|ROOT_URL" gitops/config/gitea-values.yaml

echo "=== workshop-values.yaml ==="
grep "domain:\|baseUrl:" gitops/config/workshop-values.yaml

# 4. Ansible Vault作成
ansible-vault create ansible/group_vars/vault.yml
# 内容は Phase 2.2 参照

# 5. GitOps Bootstrap
oc apply -f gitops/bootstrap/root-application.yaml
watch oc get applications -n openshift-gitops  # 全てSynced/Healthyまで待機

# 6. Ansible Secrets作成
cd ansible
echo "your-vault-password" > .vault_pass
ansible-playbook playbooks/gitea-secrets.yml --vault-password-file .vault_pass

# 7. Git Secrets作成 (S2I用)
ansible-playbook playbooks/git-secrets.yml --vault-password-file .vault_pass

# 8. Gitea管理者パスワード取得
ADMIN_PASS=$(oc get secret gitea-user-provisioning -n gitea -o jsonpath='{.data.admin-password}' | base64 -d)

# 9. Coolstore配布
cd ../scripts
export GITEA_ADMIN_PASSWORD="${ADMIN_PASS}"
./gitea-populate-coolstore.sh

# 10. DevWorkspace作成
cd workspace
./create-all-workspaces.sh

# 11. S2Iデプロイテスト (user01のDevWorkspace UIから)
# - oc whoami → user01確認
# - cd /projects/coolstore-eap7/scripts/openshift/eap7
# - ./01-setup.sh && ./02-build.sh && ./03-deploy.sh
```

**所要時間**: 約30-40分

**成功判定**: 
- user01のDevWorkspaceからEAP7アプリケーションがデプロイできる
- REST API (`/services/products`) が応答する
- Web UI (`/`) が表示される

---

**最終更新**: 2026-07-19  
**検証環境**: OpenShift 4.x (cluster-jxznt.jxznt.sandbox3409.opentlc.com)  
**検証項目**: GitOps完全デプロイ、S2Iビルド、DevWorkspace起動、EAP7デプロイ
