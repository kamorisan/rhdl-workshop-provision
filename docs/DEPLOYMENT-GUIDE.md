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

#### 2.1 Gitea URL設定

```bash
# Gitea URLを設定ファイルに反映
GITEA_URL="https://gitea-gitea.${CLUSTER_DOMAIN}"

# gitea-values.yamlを更新
sed -i "s|apps.cluster-jxznt.jxznt.sandbox3409.opentlc.com|${CLUSTER_DOMAIN}|g" \
  gitops/config/gitea-values.yaml

# 確認
grep "DOMAIN\|ROOT_URL" gitops/config/gitea-values.yaml
```

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

### Phase 6: Coolstore-EAP7リポジトリ配布

#### 6.1 自動配布スクリプト実行

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
   - `devfile.yaml`作成 (DevSpaces用)
3. Giteaリポジトリ作成とpush

#### 6.2 配布確認

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

---

### Phase 7: DevSpaces設定

#### 7.1 DevSpaces起動確認

```bash
# DevSpaces Podステータス
oc get pods -n openshift-devspaces

# DevSpaces Route
DEVSPACES_URL=$(oc get route devspaces -n openshift-devspaces -o jsonpath='{.spec.host}')
echo "DevSpaces URL: https://${DEVSPACES_URL}"
```

#### 7.2 ユーザーアクセステスト

ブラウザで各ユーザーとしてテスト：

1. DevSpaces URLにアクセス
2. user01 / openshiftでログイン
3. "Create Workspace"をクリック
4. Git Repository URL入力: `https://<gitea-route>/user01/coolstore-eap7`
5. Workspaceが起動し、devfile.yamlが自動適用されることを確認

---

## ✅ デプロイ完了チェックリスト

### GitOps

- [ ] workshop-root Application: Synced/Healthy
- [ ] All child Applications: Synced/Healthy
- [ ] Argo CD auto-prune enabled (prune: true)

### Namespaces

- [ ] user01-dev ~ user10-dev 作成済み
- [ ] gitea namespace作成済み
- [ ] openshift-devspaces作成済み

### Gitea

- [ ] Gitea Pod: Running
- [ ] Route: HTTPSアクセス可能
- [ ] user01-user10: 全員作成済み (password: openshift)
- [ ] coolstore-eap7リポジトリ: 全ユーザー配布済み

### PostgreSQL

- [ ] 各user namespaceにPostgreSQL Pod: Running
- [ ] coolstore-db-secret: 全namespace作成済み
- [ ] PRODUCT_CATALOGテーブル: 9件のデータ

### DevSpaces

- [ ] DevSpaces Pod: Running
- [ ] Route: HTTPSアクセス可能
- [ ] user01でWorkspace作成テスト成功

---

## 🔧 環境固有のカスタマイズ

### Gitea URL変更後の再実行

Cluster domainが変わった場合：

```bash
# 1. Gitea values更新
NEW_DOMAIN="apps.new-cluster.example.com"
sed -i "s|apps.cluster-.*|${NEW_DOMAIN}|g" gitops/config/gitea-values.yaml

# 2. Git commit & push
git add gitops/config/gitea-values.yaml
git commit -m "Update Gitea URL for new cluster"
git push

# 3. Argo CD sync
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
| Phase 4: Ansible Secrets | 2分 |
| Phase 5: Gitea確認 | 3分 |
| Phase 6: Coolstore配布 | 2-3分 |
| Phase 7: DevSpaces確認 | 5分 |
| **合計** | **約30-35分** |

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

---

## 📚 関連ドキュメント

- [coolstore-eap7環境固有値分析](../! miscellaneous/coolstore-eap7-environment-specific-values.md)
- [Gitea GitOps実装ガイド](../! miscellaneous/gitea-gitops-implementation-guide.md)
- [Gitea SCC問題解決レポート](../! miscellaneous/20260718_gitea-openshift-scc-troubleshooting-report.md)

---

**最終更新**: 2026-07-18  
**検証環境**: OpenShift 4.x (cluster-jxznt.jxznt.sandbox3409.opentlc.com)
