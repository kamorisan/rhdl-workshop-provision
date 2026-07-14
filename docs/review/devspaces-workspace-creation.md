# Dev Spaces Workspace 自動作成のトラブルシューティング

## 概要

OpenShift Dev Spaces (3.29.0) でWorkspaceをGitOpsまたはスクリプトで自動作成する際に発生した問題と解決策をまとめたドキュメントです。

## 試行した方法

### 1. GitOpsによる自動作成（失敗）

**アプローチ:**
- Helm チャートでDevWorkspaceマニフェストを生成
- ArgoCD Applicationでデプロイ

**発生した問題:**

#### 問題1: `controller.devfile.io/creator` ラベルの動的取得

```yaml
# 問題のあるマニフェスト
metadata:
  labels:
    controller.devfile.io/creator: "{{ user_uid }}"  # 動的な値が必要
```

**原因:**
- DevWorkspace作成時に`controller.devfile.io/creator`ラベルが必須
- このラベルにはOpenShift Userオブジェクトのmetadata.uidを設定する必要がある
- Helmテンプレートでは`oc get user`の結果を取得できない

**結論:**
- GitOpsでは動的なユーザーUID取得が不可能
- Helmのlookup機能もRuntime APIアクセスに制限がある

---

### 2. Ansibleによる自動作成（部分的成功）

**アプローチ:**
- `kubernetes.core.k8s_info`モジュールでユーザーUIDを取得
- `kubernetes.core.k8s`モジュールでDevWorkspace作成

**実装:**

```yaml
# ansible/roles/devworkspaces/tasks/main.yml
- name: Get user UIDs for DevWorkspace creator labels
  kubernetes.core.k8s_info:
    api_version: user.openshift.io/v1
    kind: User
    name: "{{ item.username }}"
  register: user_info
  loop: "{{ workshop_users }}"

- name: Create user UID mapping
  ansible.builtin.set_fact:
    user_uid_map: "{{ user_uid_map | default({}) | combine({item.item.username: item.resources[0].metadata.uid}) }}"
  loop: "{{ user_info.results }}"
```

**発生した問題:**

#### 問題2: creatorラベルが空文字になる

**原因:**
- kubeadminユーザーで作成すると、DevWorkspace Admission WebhookがcreatorラベルをkubeadminのUIDで上書きしようとする
- kubeadminはOpenShift Userオブジェクトを持たないため、空文字になる

**教訓:**
- **DevWorkspaceは必ず該当ユーザーとしてログインして作成する必要がある**
- Webhookが現在の認証ユーザーのUIDを自動設定する

---

### 3. スクリプトによる自動作成（部分的成功）

**アプローチ:**
- 各ユーザーとして`oc login`
- そのユーザーでDevWorkspace作成

**実装:**

```bash
#!/bin/bash
for i in $(seq -f "%02g" 1 10); do
  USERNAME="user${i}"
  NAMESPACE="${USERNAME}-devspaces"
  
  # 重要: ユーザーとしてログイン
  oc login --insecure-skip-tls-verify=true \
    https://api.cluster-59m78.59m78.sandbox1272.opentlc.com:6443 \
    -u ${USERNAME} -p openshift
  
  # DevWorkspace作成
  cat <<EOF | oc apply -f -
apiVersion: workspace.devfile.io/v1alpha2
kind: DevWorkspace
metadata:
  name: spring-to-quarkus
  namespace: ${NAMESPACE}
spec:
  started: false
  routingClass: che
  template:
    # ...
EOF
done
```

**発生した問題:**

#### 問題3: Namespaceの不一致

**エラー:**
- WorkspaceがDashboardに表示されない

**原因:**
```yaml
# CheClusterの設定
spec:
  devEnvironments:
    defaultNamespace:
      template: <username>-devspaces  # ← これ
```

- 最初は`user01-dev`にDevWorkspaceを作成していた
- Dev Spaces DashboardはCheClusterの`defaultNamespace.template`で指定されたnamespaceのWorkspaceのみ表示する

**解決策:**
- `<username>-devspaces` namespaceにDevWorkspaceを作成する必要がある

#### 問題4: Namespace権限不足

**エラー:**
```
Error from server (Forbidden): User "user02" cannot get resource "devworkspaces" 
in API group "workspace.devfile.io" in the namespace "user02-devspaces"
```

**原因:**
- user01-devspacesはDev Spacesが自動作成したため、user01にadmin権限が付与されていた
- user02-10のnamespaceは手動作成したため、権限がなかった

**解決策:**
```bash
for i in $(seq -f "%02g" 1 10); do
  oc adm policy add-role-to-user admin user${i} -n user${i}-devspaces
done
```

---

#### 問題5: Editor Contributionの設定

**試行1: uri形式**

```yaml
spec:
  contributions:
    - name: editor
      uri: che-incubator/che-code/latest
```

**エラー:**
```
failed to resolve component editor by URI: failed to fetch file from che-incubator/che-code/latest: 
Get "che-incubator/che-code/latest": unsupported protocol scheme ""
```

**原因:**
- `uri:`形式はHTTP(S) URLまたはdevfile registry URLを想定
- `che-incubator/che-code/latest`はレジストリパスだが、プロトコルスキームがない

---

**試行2: contributionsなし（期待: 自動注入）**

```yaml
spec:
  started: false
  routingClass: che
  template:
    components:
      - name: dev-tools
        container:
          image: quay.io/devfile/universal-developer-image:ubi8-latest
```

**結果:**
- Workspaceは作成されるが、IDE URLが生成されない
- Traefik ConfigMapが空（`routers: {}`, `services: {}`）

**エラー:**
```
The workspace has not received an IDE URL in the last 20 seconds.
```

**原因:**
- Dev Spacesはエディターコンポーネントがないとroutingを設定しない
- CheCluster設定の`defaultEditor`は**新規作成時のデフォルト**であり、既存DevWorkspaceには自動注入されない

---

**試行3: kubernetes.name形式でDevWorkspaceTemplateを参照**

```yaml
# DevWorkspaceTemplate作成
apiVersion: workspace.devfile.io/v1alpha2
kind: DevWorkspaceTemplate
metadata:
  name: che-code-editor
  namespace: user01-devspaces
spec:
  components:
    - container:
        image: registry.redhat.io/devspaces/code-rhel9@sha256:02c8f907...
      name: che-code-injector
```

```yaml
# DevWorkspaceで参照
spec:
  contributions:
    - name: editor
      kubernetes:
        name: che-code-editor
```

**エラー:**
```
Error creating DevWorkspace deployment: Init Container che-code-injector has state ImagePullBackOff
Failed to pull image: manifest unknown
```

**原因:**
- 使用したイメージdigestが存在しない、または認証エラー
- Red Hat Container Catalogのイメージタグ/digestが環境やバージョンで異なる

---

## 現状の制限事項

### GitOpsでの自動作成が困難な理由

1. **動的ユーザーUID取得の困難性**
   - Helmではランタイム情報（ユーザーUID）を取得できない
   - 外部データソースとの連携（External Secrets Operatorなど）も複雑

2. **Editor Contributionの複雑性**
   - 正しいイメージdigestの特定が困難
   - Dev Spacesバージョンごとにイメージが変わる
   - DevWorkspaceTemplateの正確な定義が必要

3. **Webhookによる制御**
   - `controller.devfile.io/creator`ラベルはWebhookが上書きする
   - 作成者の認証コンテキストが必須

### スクリプトでの自動作成の制限

1. **Editor未設定の問題**
   - contributionsなしでは起動できない
   - DevWorkspaceTemplateの作成とメンテナンスが必要

2. **イメージの可用性**
   - Red Hat Registryのイメージ認証
   - バージョンごとのdigest変更

## 推奨される運用方法

### 方法1: Dashboard上でのユーザー手動作成（推奨）

**手順:**
1. Dev Spaces Dashboard: https://devspaces.apps.cluster-59m78.59m78.sandbox1272.opentlc.com
2. ユーザーでログイン（user01 / openshift）
3. 「Create Workspace」ボタン
4. 「Import from Git」タブ
5. リポジトリURL: https://github.com/kamorisan/spring-to-quarkus-sample
6. 「Create & Open」

**メリット:**
- Dev Spacesが正しいeditor設定で自動作成
- ユーザーごとの権限が自動的に正しく設定される
- トラブルシューティングが容易

**デメリット:**
- 各ユーザーが手動操作する必要がある
- 大規模展開時の手間

---

### 方法2: devfile.yamlをリポジトリに配置

**手順:**

1. リポジトリのルートに`devfile.yaml`を配置:

```yaml
schemaVersion: 2.2.0
metadata:
  name: spring-to-quarkus
projects:
  - name: spring-petclinic
    git:
      remotes:
        origin: https://github.com/kamorisan/spring-to-quarkus-sample
      checkoutFrom:
        revision: main
components:
  - name: dev-tools
    container:
      image: quay.io/devfile/universal-developer-image:ubi8-latest
      memoryLimit: 4Gi
      mountSources: true
```

2. DashboardでURL指定:
   - URL: https://github.com/kamorisan/rhdl-workshop-provision/blob/main/devfile.yaml

**メリット:**
- バージョン管理されたWorkspace定義
- 一貫性のある環境

---

### 方法3: 事前作成 + 停止状態で配布

**実装:**

```bash
# スクリプト: scripts/create-devworkspaces.sh
for i in $(seq -f "%02g" 1 10); do
  oc login -u user${i} -p openshift
  cat <<EOF | oc apply -f -
apiVersion: workspace.devfile.io/v1alpha2
kind: DevWorkspace
metadata:
  name: spring-to-quarkus
  namespace: user${i}-devspaces
spec:
  started: false  # 停止状態
  routingClass: che
  template:
    # 最小限の定義
    projects:
      - name: app
        git:
          remotes:
            origin: https://github.com/example/repo
    components:
      - name: tools
        container:
          image: quay.io/devfile/universal-developer-image:ubi8-latest
          memoryLimit: 2Gi
EOF
done
```

**注意点:**
- **editorなしでは起動できない**
- Dashboardには表示されるが、起動時にエラーになる
- ユーザーが再作成する必要がある可能性

**結論:**
現時点では**方法1（ユーザー手動作成）**が最も確実で推奨される運用方法。

---

## トラブルシューティングチェックリスト

### Workspaceが表示されない場合

- [ ] Namespaceが`<username>-devspaces`になっているか
- [ ] CheClusterの`defaultNamespace.template`設定を確認
- [ ] `controller.devfile.io/creator`ラベルが正しいユーザーUIDか

### Workspaceが起動しない場合

- [ ] `contributions`でeditorが設定されているか
- [ ] DevWorkspaceRoutingが"Ready"状態か
- [ ] Traefik ConfigMapにroutersが定義されているか
- [ ] Podがすべて"Running"状態か
- [ ] ImagePullBackOffエラーがないか

### 確認コマンド

```bash
# Workspace状態確認
oc get devworkspace -n user01-devspaces

# Routing確認
oc get devworkspacerouting -n user01-devspaces

# Pod状態
oc get pods -n user01-devspaces

# Events確認
oc get events -n user01-devspaces --sort-by='.lastTimestamp' | tail -20

# Traefik設定確認
oc get configmap -n user01-devspaces -o yaml | grep -A20 "routers:"

# Creator label確認
oc get devworkspace <name> -n user01-devspaces \
  -o jsonpath='{.metadata.labels.controller\.devfile\.io/creator}'

# User UID確認
oc get user user01 -o jsonpath='{.metadata.uid}'
```

---

## 参考: 他のワークショップの実装

### Camel Workshop (成功例)

```yaml
# DevWorkspaceTemplate作成
apiVersion: workspace.devfile.io/v1alpha2
kind: DevWorkspaceTemplate
metadata:
  name: che-code-camelk-ws
  namespace: user${m}-devspaces
spec:
  # che-code editor定義
  components:
    - container:
        image: registry.redhat.io/devspaces/code-rhel8@sha256:...
      name: che-code-injector

# DevWorkspaceから参照
spec:
  contributions:
    - kubernetes:
        name: che-code-camelk-ws
      name: editor
```

**成功要因:**
- 動作確認済みのイメージdigestを使用
- ユーザーごとにDevWorkspaceTemplateを作成
- スクリプトで各ユーザーとしてログインして作成

---

## 今後の改善案

1. **DevWorkspaceTemplate共有化**
   - 全ユーザーで共通のDevWorkspaceTemplateをopenshift-devspaces namespaceに配置
   - namespace間の参照が可能か検証

2. **CheCluster defaultEditor活用**
   - CheClusterでデフォルトeditorを設定
   - 最小限のDevWorkspace定義で自動注入されるか検証

3. **GitOps + Post-Sync Hook**
   - ArgoCD Post-Sync HookでAnsible Playbookを実行
   - ユーザーUIDを取得してDevWorkspace作成

4. **Operator開発**
   - Custom Operator for Workshop Workspace Provisioning
   - User作成時に自動的にDevWorkspaceを作成するController

---

## まとめ

| 方法 | 自動化レベル | 成功率 | 推奨度 | 備考 |
|------|------------|--------|--------|------|
| GitOps | 高 | 低 | ❌ | ユーザーUID取得不可、editor設定困難 |
| Ansible | 高 | 中 | ⚠️ | creatorラベル問題、editor設定困難 |
| スクリプト（ユーザーログイン） | 中 | 中 | ⚠️ | editor設定が課題 |
| Dashboard手動作成 | 低 | 高 | ✅ | 最も確実、ユーザー操作必要 |
| devfile.yaml + URL | 低 | 高 | ✅ | 一貫性あり、ユーザー操作必要 |

**最終推奨:**
- ワークショップ環境では**Dashboard + devfile.yaml URLからの作成**を案内する
- 事前準備としてnamespaceと権限のみをGitOpsで管理
- DevWorkspace自体はユーザーに作成してもらう

---

## 関連ファイル

- スクリプト: `scripts/create-devworkspaces.sh`
- devfile定義: `devfile.yaml`
- Ansibleロール: `ansible/roles/devworkspaces/`
- GitOpsマニフェスト: `gitops/workshop/resources/templates/`

## 更新履歴

- 2026-07-13: 初版作成（試行錯誤の記録）
