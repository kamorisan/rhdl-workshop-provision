# Workshop Environment Cleanup and Re-deployment Log

**日付**: 2026-09-16  
**作業者**: kamori  
**クラスタ**: cluster-jxznt.jxznt.sandbox3409.opentlc.com  
**目的**: 既存環境（54日前にデプロイ）のクリーンアップと新規環境の再構築

---

## 📋 作業サマリー

| フェーズ | 作業内容 | ステータス | 所要時間 |
|---------|---------|-----------|---------|
| Phase 1 | 既存環境のクリーンアップ | ✅ 完了 | ~25分 |
| Phase 2 | ユーザー数変更（10→15） | ✅ 完了 | ~5分 |
| Phase 3 | GitOps Bootstrap | 🔄 実行中 | - |
| Phase 4-7 | 新規デプロイメント | ⏳ 待機中 | - |

---

## Phase 1: 既存環境のクリーンアップ

### 1.1 削除対象リソース

#### 削除されたGitOps Applications
- `workshop-resources` - DevWorkspaces、RBAC
- `workshop-namespaces` - ユーザーnamespace（user01-10）
- `workshop-platform-instances` - Dev Spaces、MTA instances
- `workshop-gitea` - Gitea Git server
- `workshop-images` - カスタムイメージ
- `workshop-operators` - Operator subscriptions
- `workshop-cluster-config` - クラスタ設定
- `etherpad` - Etherpad

#### 削除されたNamespaces（30個）
- `user01-dev` ~ `user10-dev`（10個）
- `user01-devspaces` ~ `user10-devspaces`（10個）
- `openshift-devspaces`
- `openshift-mta`
- `gitea`
- `workshop-images`
- `workshop-system`
- `etherpad`
- `cert-manager`
- `cert-manager-operator`

#### 削除されたユーザーリソース
- ユーザー: `user01` ~ `user10`（9個、user05欠番）
- Identity: `workshop_htpasswd:user01` ~ `workshop_htpasswd:user10`
- OAuth Identity Provider: `workshop_htpasswd`
- Secret: `workshop-htpasswd` (openshift-config)

#### 削除されたOperatorリソース
- Subscription: `devworkspace-operator-fast-redhat-operators-openshift-marketplace`
- CSV: `devspacesoperator.v3.30.0`

### 1.2 つまづいた箇所と対処法

#### ⚠️ Issue 1: PVC削除がスタック

**症状:**
```bash
oc get pvc -n user01-dev
NAME                     STATUS        VOLUME                                     ...
pipeline-workspace-pvc   Terminating   pvc-38f0d525-beb7-45f7-92e0-5b8fa968e56d   ...
```

**原因:**
- PVCにfinalizerが残っており、削除が完了しない
- GitOps Applicationの削除が600秒タイムアウト

**対処法:**
```bash
# 各ユーザーnamespaceのTerminating PVCからfinalizerを削除
for i in {01..10}; do
  oc get pvc -n user${i}-dev --field-selector=status.phase=Terminating -o name 2>/dev/null | while read pvc; do
    echo "  Removing finalizers from $pvc"
    oc patch $pvc -n user${i}-dev -p '{"metadata":{"finalizers":null}}' --type=merge 2>&1 || true
  done
done

# 特定のPVCを手動削除
oc patch pvc pipeline-workspace-pvc -n user01-dev -p '{"metadata":{"finalizers":null}}' --type=merge
```

**結果:** PVCが即座に削除され、namespaceのクリーンアップが進行

---

#### ⚠️ Issue 2: openshift-devspaces namespace がTerminatingでスタック

**症状:**
```bash
oc get namespace openshift-devspaces
NAME                  STATUS        AGE
openshift-devspaces   Terminating   54d
```

**原因:**
- CheCluster CR `devspaces`にfinalizerが残っている
- 以下のfinalizerがリソース削除をブロック:
  - `cheGateway.clusterpermissions.finalizers.che.eclipse.org`
  - `oauthclients.finalizers.che.eclipse.org`
  - `dashboard.clusterpermissions.finalizers.che.eclipse.org`
  - `container-build.finalizers.che.eclipse.org`
  - `consolelink.finalizers.che.eclipse.org`

**診断コマンド:**
```bash
oc get checluster -n openshift-devspaces
oc get namespace openshift-devspaces -o yaml | grep -A 10 "status:"
```

**対処法:**
```bash
# CheCluster CRからfinalizerを削除
oc patch checluster devspaces -n openshift-devspaces -p '{"metadata":{"finalizers":null}}' --type=merge
```

**結果:** CheClusterとopenshift-devspaces namespaceが即座に削除

---

#### ⚠️ Issue 3: workshop-namespaces Application がProgressingで長時間待機

**症状:**
```bash
oc get application workshop-namespaces -n openshift-gitops
NAME                   SYNC STATUS   HEALTH STATUS
workshop-namespaces    OutOfSync     Progressing
```

**原因:**
- Application自体にfinalizerが残っている
- 管理対象のnamespaceは削除済みだが、Applicationリソースが終了しない

**対処法:**
```bash
# Applicationからfinalizerを削除
oc patch application workshop-namespaces -n openshift-gitops -p '{"metadata":{"finalizers":null}}' --type=merge
```

**結果:** Applicationが即座に削除され、クリーンアップスクリプトが完了

---

### 1.3 クリーンアップスクリプトの実行ログ

**実行コマンド:**
```bash
cd /Users/kamori/vscode/developer-lightspeed/workshop-provisioning
./scripts/gitops/cleanup-gitops.sh users
```

**タイムライン:**
- 16:12:34 - workshop-resources削除開始
- 16:23:57 - workshop-resources削除完了（PVCスタックで600秒タイムアウト）
- 16:23:58 - workshop-namespaces削除開始
- 16:28:11 - workshop-namespaces削除完了
- **手動介入:** CheCluster finalizerおよびApplication finalizer削除

**最終確認:**
```bash
oc get applications -n openshift-gitops
# 結果: No resources found

oc get namespaces | grep -E "user|workshop|gitea|mta|devspaces"
# 結果: クリーン（workshop関連namespace 0個）

oc get users | grep user
# 結果: No resources found
```

---

### 1.4 保持されたリソース

#### OpenShift Pipelines Operator（意図的に保持）
```bash
oc get csv -n openshift-pipelines
NAME                                      VERSION
openshift-pipelines-operator-rh.v1.23.2   1.23.2

oc get tektonconfig
NAME     VERSION   READY
config   1.23.2    True
```

**理由:**
- ワークショップではTekton Pipelinesを使用する設計
- coolstore-eap7/8のパイプラインタスク定義あり
- 既存Operatorを再利用することで再インストール時間を節約
- GitOpsで管理対象として再度適用される

---

## Phase 2: ユーザー数変更（10→15）

### 2.1 変更対象ファイル

#### ✅ 変更1: GitOps設定ファイル

**ファイル:** `gitops/config/workshop-values.yaml`

**変更箇所:**
```yaml
# 変更前
workshop:
  userCount: 10
  usernamePrefix: user
  namespaceSuffix: -dev

# 変更後
workshop:
  userCount: 15
  usernamePrefix: user
  namespaceSuffix: -dev
```

**パス:** [gitops/config/workshop-values.yaml:15](file:///Users/kamori/vscode/developer-lightspeed/workshop-provisioning/gitops/config/workshop-values.yaml#L15)

**影響範囲:**
- Helm chartsがこの値を参照してリソースを生成
- user01-dev ~ user15-dev (計15個のnamespace)
- user01-devspaces ~ user15-devspaces (計15個のnamespace)

---

#### ✅ 変更2: Ansible Inventory

**ファイル:** `ansible/inventory/production/hosts.yml`

**変更箇所:**
```yaml
# 変更前
  vars:
    workshop_user_count: 10
    workshop_username_prefix: user
    workshop_user_password: openshift

# 変更後
  vars:
    workshop_user_count: 15
    workshop_username_prefix: user
    workshop_user_password: openshift
```

**パス:** [ansible/inventory/production/hosts.yml:16](file:///Users/kamori/vscode/developer-lightspeed/workshop-provisioning/ansible/inventory/production/hosts.yml#L16)

**影響範囲:**
- Ansible playbooksがこの値を参照
- ユーザー認証情報生成（user01-user15）
- Giteaリポジトリ配布（15個）

---

### 2.2 ハードコード箇所の確認

#### 調査結果
```bash
grep -r "user10\|user01.*user10\|1-10\|01-10" scripts/*.sh docs/*.md
```

**発見箇所:**
- `scripts/gitea-populate-coolstore.sh` - コメント内の例示のみ
- `docs/DEPLOYMENT-GUIDE.md` - ドキュメント内の例示

**結論:** 
- すべて説明・例示用のテキスト
- 実際のロジックは変数ベース（`workshop_user_count`, `userCount`）
- **変更不要**

---

### 2.3 想定リソース消費（15ユーザー）

| リソース | 計算式 | 合計 |
|---------|-------|------|
| CPU | 15 users × 1 core + 4 platform cores | **19 cores** |
| Memory | 15 users × 2GB + 16GB platform | **46GB** |
| Storage | 15 users × 10GB + 20GB platform | **170GB** |

---

## Phase 3: GitOps Bootstrap（実行中）

### 3.1 事前確認

**クラスタ接続確認:**
```bash
oc whoami
# kube:admin

oc whoami --show-server
# https://api.cluster-jxznt.jxznt.sandbox3409.opentlc.com:6443

oc auth can-i '*' '*' --all-namespaces
# yes
```

**クラスタドメイン確認:**
```bash
CLUSTER_DOMAIN=$(oc get ingresses.config.openshift.io cluster -o jsonpath='{.spec.domain}')
echo $CLUSTER_DOMAIN
# apps.cluster-jxznt.jxznt.sandbox3409.opentlc.com
```

**設定ファイル確認:**
```bash
grep "domain:" gitops/config/workshop-values.yaml | head -2
# domain: apps.cluster-jxznt.jxznt.sandbox3409.opentlc.com
# ✅ 同じクラスタのため変更不要
```

---

### 3.2 次のステップ

DEPLOYMENT-GUIDE.md の Phase 3 から開始:

#### Phase 3: GitOpsデプロイ
```bash
# Root Applicationデプロイ
oc apply -f gitops/bootstrap/root-application.yaml

# 進捗確認
watch oc get applications -n openshift-gitops
```

---

## 教訓と次回のための注意事項

### ✅ Do（推奨される対応）

1. **PVC削除時のfinalizer対応**
   - namespace削除前に、Terminating PVCのfinalizerを手動削除
   - 一括処理スクリプトを準備:
     ```bash
     for ns in $(oc get ns --field-selector=status.phase=Terminating -o name); do
       oc get pvc -n $ns --field-selector=status.phase=Terminating -o name | \
       xargs -I {} oc patch {} -n $ns -p '{"metadata":{"finalizers":null}}' --type=merge
     done
     ```

2. **CheCluster削除の優先順位**
   - openshift-devspaces namespace削除前に、CheCluster CRを明示的に削除
   - または、CheCluster CRのfinalizerを先に削除:
     ```bash
     oc patch checluster devspaces -n openshift-devspaces -p '{"metadata":{"finalizers":null}}' --type=merge
     ```

3. **GitOps Application削除のタイムアウト対策**
   - 600秒タイムアウト前に手動で進捗確認
   - 必要に応じてApplicationのfinalizerを削除して強制完了

4. **既存Operatorの再利用**
   - ワークショップで使用するOperator（Pipelines等）は保持してOK
   - 再インストール時間の節約

---

### ⚠️ Don't（避けるべき対応）

1. **namespaceの強制削除**
   - `oc patch namespace <ns> -p '{"metadata":{"finalizers":null}}'` は最終手段
   - まずリソース（PVC、CR等）のfinalizerを削除

2. **cleanup-gitops.shの途中キャンセル**
   - スクリプトは最後まで実行させる
   - 手動介入は別のターミナルで実施

3. **ドメイン設定の不要な変更**
   - 同じクラスタで再デプロイする場合、ドメイン設定は変更不要
   - 変更すると逆にGitea URLが不一致になる

---

## 次回のクリーンアップ改善案

### クリーンアップスクリプトの改良提案

**`scripts/gitops/cleanup-gitops.sh`に追加すべき機能:**

```bash
# 1. PVC finalizer自動削除
cleanup_stuck_pvcs() {
    local namespaces=$(oc get pvc -A --field-selector=status.phase=Terminating -o jsonpath='{.items[*].metadata.namespace}' | tr ' ' '\n' | sort -u)
    for ns in $namespaces; do
        if [[ $ns == user*-dev ]] || [[ $ns == user*-devspaces ]]; then
            oc get pvc -n $ns --field-selector=status.phase=Terminating -o name | \
            xargs -I {} oc patch {} -n $ns -p '{"metadata":{"finalizers":null}}' --type=merge
        fi
    done
}

# 2. CheCluster finalizer自動削除
cleanup_checluster() {
    if oc get checluster -n openshift-devspaces devspaces &>/dev/null; then
        oc patch checluster devspaces -n openshift-devspaces -p '{"metadata":{"finalizers":null}}' --type=merge
    fi
}

# 3. Application finalizer自動削除（タイムアウト後）
cleanup_stuck_applications() {
    local stuck_apps=$(oc get applications -n openshift-gitops --field-selector=metadata.deletionTimestamp!='' -o name)
    for app in $stuck_apps; do
        oc patch $app -n openshift-gitops -p '{"metadata":{"finalizers":null}}' --type=merge
    done
}
```

---

## デプロイメント実行記録（Phase 3以降）

### Phase 3: GitOps Bootstrap
- **開始時刻:** _実行後に記入_
- **完了時刻:** _実行後に記入_
- **ステータス:** ⏳ 待機中

### Phase 4: Operators
- **ステータス:** ⏳ 待機中

### Phase 5: Platform Instances  
- **ステータス:** ⏳ 待機中

### Phase 6: User Namespaces
- **ステータス:** ⏳ 待機中

### Phase 7: Gitea Repository Population
- **ステータス:** ⏳ 待機中

---

## 参考資料

- [DEPLOYMENT-GUIDE.md](./DEPLOYMENT-GUIDE.md) - 完全デプロイ手順
- [DEPLOYMENT_CHECKLIST.md](./DEPLOYMENT_CHECKLIST.md) - デプロイチェックリスト
- [OPERATIONS.md](./OPERATIONS.md) - 運用手順
- [TROUBLESHOOTING.md](./TROUBLESHOOTING.md) - トラブルシューティング

---

**ドキュメント作成日:** 2026-09-16  
**最終更新日:** 2026-09-16
