# Workshop User Count Update Workflow

**対象**: 既存のワークショップ環境でユーザー数を変更する手順  
**前提条件**: GitOpsでデプロイ済みの環境

---

## 📋 概要

ワークショップのユーザー数（userCount）を変更する場合、以下の2つのファイルを更新してGitHubにpushする必要があります。

**変更対象ファイル:**
1. `gitops/config/workshop-values.yaml` - GitOps/Helm charts用
2. `ansible/inventory/production/hosts.yml` - Ansible playbooks用（.gitignoreされているため手動管理）

---

## 🚀 変更手順

### Step 1: 設定ファイルの更新

#### 1.1 GitOps設定ファイル更新

**ファイル:** `gitops/config/workshop-values.yaml`

```bash
# ファイルを編集
vi gitops/config/workshop-values.yaml
```

**変更箇所:**
```yaml
workshop:
  userCount: 10  # ← この値を変更（例: 15）
  usernamePrefix: user
  namespaceSuffix: -dev
```

**例: 10ユーザー → 15ユーザー**
```yaml
workshop:
  userCount: 15
  usernamePrefix: user
  namespaceSuffix: -dev
```

---

#### 1.2 Ansible Inventory更新

**ファイル:** `ansible/inventory/production/hosts.yml`

```bash
# ファイルを編集
vi ansible/inventory/production/hosts.yml
```

**変更箇所:**
```yaml
all:
  hosts:
    localhost:
      ansible_connection: local
  vars:
    workshop_user_count: 10  # ← この値を変更（例: 15）
    workshop_username_prefix: user
    workshop_user_password: openshift
```

**注意:** このファイルは`.gitignore`に含まれているため、GitHubにはpushされません（環境固有設定のため）。

---

### Step 2: GitHubへのPush

**GitOps設定ファイルのみをcommit & push:**

```bash
# 変更確認
git status
git diff gitops/config/workshop-values.yaml

# Staging
git add gitops/config/workshop-values.yaml

# Commit
git commit -m "Update workshop user count from 10 to 15

Changes:
- gitops/config/workshop-values.yaml: userCount 10 → 15

This will create user11-15 namespaces (dev + devspaces).

Co-Authored-By: Claude <noreply@anthropic.com>"

# Push
git push origin main
```

---

### Step 3: Argo CDの自動Sync待機

GitHubへのpush後、Argo CDが自動的に変更を検出してsyncします。

**デフォルトの自動Sync間隔:**
- 通常: 3分（180秒）
- または手動でrefresh

#### 3.1 自動Sync待機

```bash
# Argo CDが変更を検出するまで待機（最大3分）
sleep 180

# リビジョン確認
oc get application workshop-namespaces -n openshift-gitops \
  -o jsonpath='{.status.sync.revision}'
```

#### 3.2 手動Refresh（すぐに反映したい場合）

```bash
# Application を手動refresh
oc annotate application workshop-namespaces -n openshift-gitops \
  argocd.argoproj.io/refresh=hard --overwrite

# または、直接syncをトリガー
oc patch application workshop-namespaces -n openshift-gitops \
  --type merge \
  -p '{"operation":{"initiatedBy":{"username":"admin"},"sync":{}}}'
```

---

### Step 4: 新規Namespace作成確認

#### 4.1 Namespace数確認

```bash
# 総Namespace数
oc get namespaces | grep -E "user.*-dev$|user.*-devspaces$" | wc -l
# 期待値: userCount × 2（例: 15 × 2 = 30）

# Dev namespaces
oc get namespaces | grep -E "user.*-dev$" | wc -l
# 期待値: userCount（例: 15）

# DevSpaces namespaces  
oc get namespaces | grep -E "user.*-devspaces$" | wc -l
# 期待値: userCount（例: 15）
```

#### 4.2 新規Namespace詳細確認

```bash
# 新規作成されたnamespaceを表示
oc get namespaces | grep -E "user.*-dev" | sort

# 例: user11-dev ~ user15-dev が新規追加されたことを確認
```

---

### Step 5: 追加ユーザーのセットアップ

新規ユーザー（例: user11-15）に対して、以下のセットアップを実施します。

#### 5.1 Giteaユーザー作成

```bash
# 新規ユーザー範囲を指定（例: 11-15）
for i in {11..15}; do
  printf -v user "user%02d" $i
  echo "Creating ${user}..."
  oc exec -n gitea deployment/gitea -- gitea admin user create \
    --username "${user}" \
    --password "openshift" \
    --email "${user}@workshop.local" \
    --must-change-password=false \
    --admin=false
done
```

**確認:**
```bash
# Giteaユーザー確認
GITEA_ROUTE=$(oc get route gitea -n gitea -o jsonpath='{.spec.host}')
ADMIN_USER=$(oc get secret gitea-user-provisioning -n gitea -o jsonpath='{.data.admin-username}' | base64 -d)
ADMIN_PASS=$(oc get secret gitea-user-provisioning -n gitea -o jsonpath='{.data.admin-password}' | base64 -d)

for i in 11 12 13 14 15; do
  curl -fsS -k -u "${ADMIN_USER}:${ADMIN_PASS}" \
    "https://${GITEA_ROUTE}/api/v1/users/user${i}" 2>/dev/null \
    | jq -r '.login'
done
```

---

#### 5.2 Git Secrets作成

```bash
# 新規ユーザーのGit secrets作成
for i in {11..15}; do
  printf -v user "user%02d" $i
  echo "Creating git secret for ${user}-dev..."
  
  oc create secret generic gitea-git-secret \
    -n ${user}-dev \
    --type=kubernetes.io/basic-auth \
    --from-literal=username=${user} \
    --from-literal=password=openshift \
    --dry-run=client -o yaml | oc apply -f -
  
  # Builder ServiceAccountにlink
  oc secrets link builder gitea-git-secret -n ${user}-dev --for=mount
done
```

**確認:**
```bash
# Git secrets確認
for i in 11 12 13 14 15; do
  printf -v ns "user%02d-dev" $i
  oc get secret gitea-git-secret -n ${ns} >/dev/null 2>&1 && \
    echo "${ns}: ✓" || echo "${ns}: ✗"
done
```

---

#### 5.3 coolstore-eap7リポジトリ配布

```bash
cd /path/to/workshop-provisioning/scripts

# 環境変数設定
export GITEA_ADMIN_PASSWORD=$(oc get secret gitea-user-provisioning -n gitea \
  -o jsonpath='{.data.admin-password}' | base64 -d)
export USER_COUNT=15  # 新しいuserCount
export GITEA_URL="https://gitea-gitea.apps.cluster-XXXXX.XXXXX.sandboxYYYY.opentlc.com"

# リポジトリ配布スクリプト実行
./gitea-populate-coolstore.sh
```

**注意:** スクリプトは全ユーザー（user01-15）を処理しますが、既存ユーザー（user01-10）は上書きされます。

---

## 📊 検証チェックリスト

### ✅ 環境確認

```bash
# 1. Namespace数確認
echo "Total namespaces: $(oc get namespaces | grep -E 'user.*-dev$|user.*-devspaces$' | wc -l)"
echo "Expected: $((USER_COUNT * 2))"

# 2. PostgreSQL pods確認
psql_count=0
for i in $(seq -f "%02g" 1 $USER_COUNT); do
  count=$(oc get pods -n user${i}-dev 2>/dev/null | grep -c postgresql || echo 0)
  psql_count=$((psql_count + count))
done
echo "PostgreSQL pods: ${psql_count}/${USER_COUNT}"

# 3. Gitea users確認
gitea_users=0
for i in $(seq -f "%02g" 1 $USER_COUNT); do
  curl -fsS -k -u "${ADMIN_USER}:${ADMIN_PASS}" \
    "https://${GITEA_ROUTE}/api/v1/users/user${i}" \
    2>/dev/null | jq -r '.login' | grep -q user && \
    gitea_users=$((gitea_users + 1))
done
echo "Gitea users: ${gitea_users}/${USER_COUNT}"

# 4. Gitea repositories確認  
echo "Gitea repositories: ${USER_COUNT} (coolstore-eap7)"

# 5. Git secrets確認
secret_count=0
for i in $(seq -f "%02g" 1 $USER_COUNT); do
  oc get secret gitea-git-secret -n user${i}-dev >/dev/null 2>&1 && \
    secret_count=$((secret_count + 1))
done
echo "Git secrets: ${secret_count}/${USER_COUNT}"
```

---

## ⚠️ トラブルシューティング

### Issue 1: Argo CDが新しいリビジョンを検出しない

**症状:**
```bash
oc get application workshop-namespaces -n openshift-gitops -o jsonpath='{.status.sync.revision}'
# 古いリビジョンのまま
```

**対処法:**
```bash
# Hard refresh
oc annotate application workshop-namespaces -n openshift-gitops \
  argocd.argoproj.io/refresh=hard --overwrite

# 5分待機して再確認
sleep 300
oc get application workshop-namespaces -n openshift-gitops -o jsonpath='{.status.sync.revision}'
```

---

### Issue 2: 新規Namespaceが作成されない

**症状:**
```bash
oc get namespaces | grep user11-dev
# 何も表示されない
```

**原因と対処:**

1. **GitHubにpushされていない**
   ```bash
   git status
   git log origin/main..main  # push漏れ確認
   git push origin main  # 必要に応じてpush
   ```

2. **Application がOutOfSync**
   ```bash
   oc get application workshop-namespaces -n openshift-gitops
   # OutOfSyncの場合は手動sync
   oc patch application workshop-namespaces -n openshift-gitops \
     --type merge -p '{"operation":{"sync":{}}}'
   ```

3. **Helm values参照エラー**
   ```bash
   # Application logsを確認
   oc logs -n openshift-gitops -l app.kubernetes.io/name=openshift-gitops-application-controller \
     | grep workshop-namespaces
   ```

---

### Issue 3: Namespaceは作成されたがPostgreSQLがデプロイされない

**症状:**
```bash
oc get pods -n user11-dev
# No resources found
```

**対処法:**
```bash
# Application workshop-resourcesを確認
oc get application workshop-resources -n openshift-gitops

# OutOfSyncの場合は手動sync
oc patch application workshop-resources -n openshift-gitops \
  --type merge -p '{"operation":{"sync":{}}}'

# PostgreSQLのsync wave確認（通常は30）
oc get pods -n user11-dev -w  # watch mode
```

---

## 🔄 ユーザー数減少時の注意事項

### ⚠️ 警告

ユーザー数を減少させる場合（例: 15 → 10）、以下のリソースが**自動削除**されます：

- `user11-dev` ~ `user15-dev` namespaces
- `user11-devspaces` ~ `user15-devspaces` namespaces
- PostgreSQL databases（データ含む）
- DevWorkspaces
- PVCs（データ損失）

### 推奨手順

**1. バックアップ（必要な場合）**
```bash
# PostgreSQL dumpなど
for i in {11..15}; do
  oc exec -n user${i}-dev deployment/postgresql -- \
    pg_dump -U coolstore coolstore > user${i}_backup.sql
done
```

**2. userCount更新とpush**
```bash
# workshop-values.yaml更新
# userCount: 15 → 10

git add gitops/config/workshop-values.yaml
git commit -m "Reduce workshop user count from 15 to 10"
git push origin main
```

**3. Argo CDのpruneで自動削除**

Argo CDの`prune: true`設定により、user11-15のnamespaceは自動的に削除されます。

---

## 📚 関連ドキュメント

- [DEPLOYMENT-GUIDE.md](./DEPLOYMENT-GUIDE.md) - 完全デプロイ手順
- [DEPLOYMENT_LOG_2026-09-16.md](./DEPLOYMENT_LOG_2026-09-16.md) - 実際の変更作業ログ（10→15への変更例）
- [OPERATIONS.md](./OPERATIONS.md) - 運用手順
- [TROUBLESHOOTING.md](./TROUBLESHOOTING.md) - トラブルシューティング

---

## 🎯 まとめ

**userCount変更の流れ:**
1. ✅ `workshop-values.yaml` 更新
2. ✅ `ansible/inventory/production/hosts.yml` 更新（手動管理）
3. ✅ GitHubへpush
4. ✅ Argo CDの自動sync待機（または手動refresh）
5. ✅ 新規Namespace作成確認
6. ✅ Giteaユーザー作成
7. ✅ Git secrets作成
8. ✅ リポジトリ配布
9. ✅ 検証

**所要時間:** 約15-20分（Argo CD sync含む）

---

**ドキュメント作成日:** 2026-09-16  
**最終更新日:** 2026-09-16
