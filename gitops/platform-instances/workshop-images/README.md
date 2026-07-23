# Workshop Images - Image Mirror

このHelmチャートは、Red HatレジストリからEAPイメージをOpenShift内部レジストリにミラーリングし、ワークショップユーザーにアクセス権を付与します。

## 概要

### 管理されるイメージ

| イメージ | ソース | ミラー先 |
|---------|-------|---------|
| EAP 8.1 Builder | `registry.redhat.io/jboss-eap-8/eap81-openjdk21-builder-openshift-rhel9:latest` | `image-registry.openshift-image-registry.svc:5000/workshop-images/eap81-builder:8.1` |
| EAP 8.1 Runtime | `registry.redhat.io/jboss-eap-8/eap81-openjdk21-runtime-openshift-rhel9:latest` | `image-registry.openshift-image-registry.svc:5000/workshop-images/eap81-runtime:8.1` |
| EAP 7.4 ELS | `registry.redhat.io/jboss-eap-7/eap74-els-openjdk8-openshift-rhel8:latest` | `image-registry.openshift-image-registry.svc:5000/workshop-images/eap74-els:7.4` |

## コンポーネント

### 1. ImageStreams (`imagestreams.yaml`)
- sync-wave: 10
- 3つのImageStreamを作成
- ミラーイメージの格納先

### 2. BuildConfigs (`buildconfigs.yaml`)
- sync-wave: 20
- 3つのBuildConfigを作成
- DockerfileでRed Hatレジストリからイメージをpull

### 3. RBAC (`rbac.yaml`)
- sync-wave: 5
- ServiceAccount: `image-mirror-sa`
- Role: BuildConfig/Build操作権限
- RoleBinding: ServiceAccountとdefault SAに権限付与

### 4. Initial Build Job (`initial-build-job.yaml`)
- sync-wave: 30
- ArgoCD PostSyncフック
- 初回デプロイ時に自動的にビルドを開始
- 既にビルド済みの場合はスキップ
- 成功後600秒でJob削除

### 5. RoleBindings for Users (`rolebindings.yaml`)
- sync-wave: 40（既存）
- user01-10にimage-puller権限を付与

## デプロイフロー

```
Sync Wave 5:  RBAC（ServiceAccount, Role, RoleBinding）
              ↓
Sync Wave 10: ImageStreams作成
              ↓
Sync Wave 20: BuildConfigs作成
              ↓
Sync Wave 30: Initial Build Job実行（PostSync Hook）
              ├─ BuildConfigの存在確認
              ├─ 既存ビルドのステータス確認
              └─ 必要に応じてビルド開始
              ↓
Sync Wave 40: User RoleBindings作成
```

## 認証

Red Hatレジストリへの認証は**クラスター全体のPull Secret**を使用します。

- Secret名: `pull-secret`
- Namespace: `openshift-config`
- 自動的にすべてのBuildPodで利用可能

新規クラスターの場合、OpenShiftインストール時にRed Hat Pull Secretが設定されている必要があります。

## 手動ビルドの実行

初回ビルド後、イメージを更新したい場合：

```bash
# EAP 8.1 Builder
oc start-build mirror-eap81-builder -n workshop-images

# EAP 8.1 Runtime
oc start-build mirror-eap81-runtime -n workshop-images

# EAP 7.4 ELS
oc start-build mirror-eap74-els -n workshop-images
```

## ビルド状態の確認

```bash
# すべてのビルドを表示
oc get builds -n workshop-images

# 特定のBuildConfigのビルド履歴
oc get builds -n workshop-images -l buildconfig=mirror-eap81-builder

# ビルドログ確認
oc logs build/mirror-eap81-builder-1 -n workshop-images
```

## ImageStreamの確認

```bash
# すべてのImageStreamを表示
oc get imagestream -n workshop-images

# 詳細情報
oc describe imagestream eap81-builder -n workshop-images

# タグとSHA256確認
oc get imagestreamtag eap81-builder:8.1 -n workshop-images \
  -o jsonpath='{.image.metadata.name}{"\n"}'
```

## トラブルシューティング

### ビルドが失敗する

1. **認証エラー**
   ```bash
   # クラスターのPull Secretを確認
   oc get secret pull-secret -n openshift-config
   
   # registry.redhat.io の認証情報が含まれているか確認
   oc get secret pull-secret -n openshift-config -o jsonpath='{.data.\.dockerconfigjson}' \
     | base64 -d | jq '.auths."registry.redhat.io"'
   ```

2. **BuildConfigが見つからない**
   ```bash
   # ArgoCD Applicationの同期状態確認
   oc get application workshop-images -n openshift-gitops
   
   # 手動同期
   argocd app sync workshop-images
   ```

3. **Initial Build Jobが失敗**
   ```bash
   # Job状態確認
   oc get job trigger-initial-image-builds -n workshop-images
   
   # Jobログ確認
   oc logs job/trigger-initial-image-builds -n workshop-images
   
   # Job削除して再実行（ArgoCD syncで再作成される）
   oc delete job trigger-initial-image-builds -n workshop-images
   ```

### ImageStreamにイメージがない

```bash
# BuildConfigの確認
oc get buildconfig -n workshop-images

# 最新ビルドの確認
oc get builds -n workshop-images --sort-by=.metadata.creationTimestamp

# 手動でビルド開始
oc start-build mirror-eap81-builder -n workshop-images --follow
```

## 新規イメージの追加

新しいイメージを追加する場合：

1. `templates/imagestreams.yaml`に新しいImageStreamを追加
2. `templates/buildconfigs.yaml`に新しいBuildConfigを追加
3. `templates/initial-build-job.yaml`のBUILDCONFIGS配列に追加
4. Commit & Push
5. ArgoCD自動同期により展開

## 定期的な更新

Red Hatレジストリの`:latest`タグは定期的に更新されます。最新イメージを取得するには：

### オプション1: 手動実行

```bash
for bc in mirror-eap81-builder mirror-eap81-runtime mirror-eap74-els; do
  oc start-build ${bc} -n workshop-images
done
```

### オプション2: CronJob（将来の拡張）

定期的な自動更新が必要な場合、CronJobを追加できます：

```yaml
apiVersion: batch/v1
kind: CronJob
metadata:
  name: rebuild-images
  namespace: workshop-images
spec:
  schedule: "0 2 * * 0"  # 毎週日曜日 2:00 AM
  jobTemplate:
    spec:
      template:
        spec:
          # ... Initial Build Jobと同じ内容
```

## 参考リンク

- [Red Hat Container Catalog - JBoss EAP 8](https://catalog.redhat.com/software/containers/jboss-eap-8)
- [OpenShift BuildConfig Documentation](https://docs.openshift.com/container-platform/latest/cicd/builds/understanding-buildconfigs.html)
- [OpenShift ImageStreams](https://docs.openshift.com/container-platform/latest/openshift_images/image-streams-manage.html)
