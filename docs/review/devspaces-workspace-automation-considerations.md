# OpenShift Dev Spaces Workspace自動作成に関する考察

## 1. 背景

OpenShift Dev Spaces 3.29.0 において、次の構成を目指す。

### GitOpsで管理する範囲

- CheCluster設定
- Namespace
- ResourceQuota / LimitRange
- NetworkPolicy
- RoleBinding
- 共通設定
- Workshop用リポジトリ
- `devfile.yaml`
- 必要に応じたDashboardのサンプル定義

### スクリプトで自動化する範囲

- 各ユーザーのWorkspace作成
- 各ユーザーの認証コンテキストでの作成
- 作成結果の確認
- 冪等な再実行
- 必要に応じたWorkspaceの停止状態での事前配布

---

## 2. 正常に作成されたDevWorkspaceから分かること

DashboardまたはFactory URL経由で正常に作成されたDevWorkspaceでは、Editorはイメージを直接指定するのではなく、`DevWorkspaceTemplate`を参照している。

```yaml
spec:
  contributions:
    - kubernetes:
        name: che-code-spring-to-quarkus-sample-dnat
      name: editor
```

このことから、Workspace作成時には少なくとも次の2リソースがセットで必要になる。

1. `DevWorkspace`
2. Editor用の`DevWorkspaceTemplate`

例:

```text
DevWorkspace:
  spring-to-quarkus-sample-dnat

DevWorkspaceTemplate:
  che-code-spring-to-quarkus-sample-dnat
```

つまり、`DevWorkspace`だけを直接作成しても、Editor用Templateが存在しなければIDE URLやRoutingが正しく生成されない可能性が高い。

---

## 3. 正常系DevWorkspaceに含まれる重要な設定

正常に起動したDevWorkspaceには、次の要素が含まれていた。

### 3.1 Editor Contribution

```yaml
spec:
  contributions:
    - name: editor
      kubernetes:
        name: che-code-spring-to-quarkus-sample-dnat
```

Editor本体は`DevWorkspaceTemplate`として別リソースに定義されている。

### 3.2 Dev Spaces管理用属性

```yaml
spec:
  template:
    attributes:
      controller.devfile.io/bootstrap-devworkspace: true
      controller.devfile.io/devworkspace-config:
        name: devworkspace-config
        namespace: openshift-devspaces
      controller.devfile.io/scc: container-build
      controller.devfile.io/storage-type: per-workspace
```

これらはDev SpacesがWorkspaceを起動・構成する際に利用する重要な属性である。

### 3.3 開発コンテナ

```yaml
components:
  - name: universal-developer-image
    container:
      env:
        - name: HOST_USERS
          value: "true"
      image: registry.redhat.io/devspaces/udi-rhel9@sha256:84c9b0e6ab68cbd4978b00ddcff085b0e3a944a5ad031f0a21a53a661b3f97ab
      sourceMapping: /projects
```

### 3.4 Gitリポジトリ

```yaml
projects:
  - name: spring-to-quarkus-sample
    git:
      remotes:
        origin: https://github.com/kamorisan/spring-to-quarkus-sample.git
```

### 3.5 Factory作成情報

```yaml
metadata:
  annotations:
    che.eclipse.org/che-editor: che-incubator/che-code/latest
    che.eclipse.org/devfile-source: |
      scm:
        repo: https://github.com/kamorisan/spring-to-quarkus-sample.git
        fileName: repo
      factory:
        params: url=https://github.com/kamorisan/spring-to-quarkus-sample
```

この情報から、DashboardまたはFactory URL経由でWorkspaceが生成されたことが分かる。

---

## 4. 再利用してはいけないフィールド

正常系DevWorkspaceのYAMLをテンプレートとして再利用する場合、次の項目は含めてはいけない。

```yaml
metadata:
  resourceVersion:
  uid:
  creationTimestamp:
  generation:
  managedFields:
  finalizers:
status:
```

これらはKubernetesまたはDevWorkspace Controllerが動的に設定する。

次のフィールドもスクリプトで固定しない。

```yaml
metadata:
  labels:
    controller.devfile.io/creator: ...
```

`controller.devfile.io/creator`は、各ユーザーの認証コンテキストで作成した際にAdmission WebhookまたはDevWorkspace側の処理に任せる。

次の動的annotationも設定しない。

```yaml
metadata:
  annotations:
    che.eclipse.org/last-updated-timestamp:
    controller.devfile.io/started-at:
```

---

## 5. 最小化したDevWorkspaceの例

```yaml
apiVersion: workspace.devfile.io/v1alpha2
kind: DevWorkspace
metadata:
  name: spring-to-quarkus-sample-user01
  namespace: user01-devspaces
  annotations:
    che.eclipse.org/che-editor: che-incubator/che-code/latest
    che.eclipse.org/devfile: |
      schemaVersion: 2.3.0
    che.eclipse.org/devfile-source: |
      scm:
        repo: https://github.com/kamorisan/spring-to-quarkus-sample.git
        fileName: repo
      factory:
        params: url=https://github.com/kamorisan/spring-to-quarkus-sample
spec:
  contributions:
    - name: editor
      kubernetes:
        name: che-code-spring-to-quarkus-sample-user01
  routingClass: che
  started: false
  template:
    attributes:
      controller.devfile.io/bootstrap-devworkspace: true
      controller.devfile.io/devworkspace-config:
        name: devworkspace-config
        namespace: openshift-devspaces
      controller.devfile.io/scc: container-build
      controller.devfile.io/storage-type: per-workspace
    components:
      - name: universal-developer-image
        container:
          env:
            - name: HOST_USERS
              value: "true"
          image: registry.redhat.io/devspaces/udi-rhel9@sha256:84c9b0e6ab68cbd4978b00ddcff085b0e3a944a5ad031f0a21a53a661b3f97ab
          sourceMapping: /projects
    projects:
      - name: spring-to-quarkus-sample
        git:
          remotes:
            origin: https://github.com/kamorisan/spring-to-quarkus-sample.git
```

ただし、このDevWorkspaceだけでは不十分であり、参照先のEditor用`DevWorkspaceTemplate`が必要になる。

---

## 6. 自動化方式

### 6.1 方式A: DevWorkspaceとDevWorkspaceTemplateを複製する

正常に生成されたEditor用`DevWorkspaceTemplate`を取得し、不要なmetadataを削除した上で、ユーザーごとに名前とNamespaceを置換して作成する。

処理の流れ:

1. `user01`で正常なWorkspaceをDashboardから作成
2. Editor用`DevWorkspaceTemplate`を取得
3. 動的metadataとstatusを削除
4. ユーザーごとにTemplate名を変更
5. 各ユーザーNamespaceへ`DevWorkspaceTemplate`を作成
6. 各ユーザーとして対応する`DevWorkspace`を作成
7. Workspace状態を確認

命名例:

```text
DevWorkspace:
  spring-to-quarkus-sample-user02

DevWorkspaceTemplate:
  che-code-spring-to-quarkus-sample-user02
```

#### メリット

- 完全な事前作成が可能
- Dashboard操作が不要
- Editorを含めたWorkspaceを再現できる
- 短期のワークショップ環境では実装しやすい

#### デメリット

- Dev Spaces 3.29のEditor内部定義に依存する
- Dev Spacesアップグレード時にTemplate更新が必要
- Editorイメージのdigestが古くなる可能性がある
- 製品内部仕様への依存が強い

---

### 6.2 方式B: Factory作成フローをスクリプトから呼び出す

管理者スクリプトから各ユーザーの認証コンテキストで、Dev Spaces DashboardまたはFactory URLと同等の作成処理を呼び出す。

概念的な処理:

```text
管理者スクリプト
  ↓
各ユーザーとして認証
  ↓
Gitリポジトリまたはdevfile URLを指定
  ↓
Dev SpacesのWorkspace作成処理
  ↓
Editor Contribution等をDev Spacesが補完
  ↓
DevWorkspaceとDevWorkspaceTemplateを生成
```

#### メリット

- Editor Templateを独自に管理しなくてよい
- Dev Spacesバージョンに対応したEditorイメージが使われる
- creatorラベルや内部annotationを製品側に任せられる
- Dashboardと同等の生成結果を得やすい

#### デメリット

- Dashboard内部APIが正式公開APIでない可能性がある
- Dev Spacesのバージョン変更でAPIが変わる可能性がある
- OAuthやユーザートークンの取り扱いが必要
- 実装前にブラウザの開発者ツール等でリクエスト内容を確認する必要がある

---

## 7. 推奨順位

### 第1候補

各ユーザーの認証コンテキストでDev SpacesのFactory作成フローを呼び出す。

これが最も製品標準の動作に近く、Editorや内部設定をDev Spaces側へ委譲できる。

### 第2候補

正常なDevWorkspaceとDevWorkspaceTemplateを取得し、ユーザーごとに複製する。

Dev Spaces 3.29で固定された短期ワークショップ環境では、現実的な選択肢となる。

### 第3候補

Editor用DevWorkspaceTemplateをGitOpsで固定管理する。

長期運用ではアップグレード追従が必要となるため、優先度は低い。

---

## 8. GitOpsとスクリプトの責務分担

### GitOpsで管理

```text
CheCluster
Namespace
RoleBinding / Role
ResourceQuota
LimitRange
NetworkPolicy
共通ConfigMap / Secret
Workshop用リポジトリ
devfile.yaml
Dashboardサンプル定義
```

### スクリプトまたはDev Spacesで生成

```text
DevWorkspace
Editor用DevWorkspaceTemplate
Workspace固有のPVC
DevWorkspaceRouting
Workspace用ServiceAccount
Workspace用Secret
Workspace Pod / Deployment
```

DevWorkspaceそのものをArgo CDの継続的な管理対象にすると、ユーザーによる起動・停止・削除とGitOpsのdesired stateが衝突する可能性がある。

そのため、DevWorkspaceはGitOps管理対象から外し、初期作成と削除をスクリプトで制御する方が適切である。

---

## 9. スクリプト実装時の要件

### 9.1 ユーザー認証コンテキスト

DevWorkspaceは各ユーザーとして作成する。

```bash
oc login "${API_URL}"   --username="${USERNAME}"   --password="${WORKSHOP_USER_PASSWORD}"   --insecure-skip-tls-verify=true
```

ユーザーごとに一時的な`KUBECONFIG`を分けると、認証状態の混在を防げる。

### 9.2 冪等性

既にWorkspaceが存在する場合は作成をスキップする。

```bash
if oc get devworkspace "${WORKSPACE_NAME}"     -n "${NAMESPACE}" >/dev/null 2>&1; then
  echo "Workspace already exists"
  exit 0
fi
```

### 9.3 停止状態での作成

事前配布する場合は、リソース消費を抑えるために次の設定とする。

```yaml
spec:
  started: false
```

### 9.4 パスワード管理

ユーザーパスワードをGitリポジトリやスクリプトへ直接記述しない。

利用候補:

- 環境変数
- Sealed Secrets
- External Secrets Operator
- Vault
- OpenShift Secret
- 実行時入力

### 9.5 権限確認

事前に各ユーザーの権限を確認する。

```bash
oc auth can-i create devworkspaces.workspace.devfile.io   -n user01-devspaces   --as=user01
```

Namespaceへ一律に`admin`ロールを付与するのではなく、Dev Spacesが自動生成したRoleBindingを参考に最小権限化する。

---

## 10. 次に確認すべき情報

Editor用`DevWorkspaceTemplate`の実体を確認する。

```bash
oc get devworkspacetemplate   che-code-spring-to-quarkus-sample-dnat   -n user01-devspaces   -o yaml
```

併せて`ownerReferences`も確認する。

```bash
oc get devworkspacetemplate   che-code-spring-to-quarkus-sample-dnat   -n user01-devspaces   -o jsonpath='{.metadata.ownerReferences}'
```

確認ポイント:

- Editorイメージ
- イメージdigest
- command / args
- volume mount
- endpoint
- environment variables
- ownerReferences
- Workspace削除時の連動削除
- Template名とWorkspace名の依存関係
- Namespaceをまたいだ参照可否
- 複数Workspaceで共通Templateを再利用できるか

---

## 11. 結論

管理者スクリプトによる各ユーザーのWorkspace自動作成は実現可能である。

ただし、DevWorkspace単体を直接作成するだけでは不十分であり、Editor用`DevWorkspaceTemplate`との組み合わせが必要となる。

推奨する構成は次の通り。

1. CheCluster、Namespace、RBAC、Quota、NetworkPolicy、devfile等はGitOpsで管理する
2. DevWorkspaceはGitOpsの継続管理対象から外す
3. スクリプトは各ユーザーの認証コンテキストで実行する
4. creatorラベルは手動設定せず、Dev Spaces側へ任せる
5. 第一候補としてFactory作成フローの再利用を検討する
6. Factory APIの利用が難しい場合は、正常系のDevWorkspaceTemplateを複製する
7. Workspaceは停止状態で事前作成する
8. 作成処理は冪等にする
9. Dev Spacesアップグレード時にはEditor Templateの互換性を再確認する

ワークショップ環境が短期間かつDev Spaces 3.29で固定されるのであれば、正常系のDevWorkspaceとDevWorkspaceTemplateを基準にした複製方式は、実用的な選択肢となる。
