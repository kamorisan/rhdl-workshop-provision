# MTA 8.1 Solution Server（Kai）GitOps構築ガイド

## 1. 目的

本書は、Red Hat OpenShift 上に GitOps で構築した Migration Toolkit for Applications（MTA）8.1 環境において、Red Hat Developer Lightspeed for MTA の **Solution Server（Kai）** を有効化するための設計・実装・確認手順をまとめたものです。

対象環境の前提は次のとおりです。

- MTA Operator をインストール済み
- `openshift-mta` Namespace に `Tackle` カスタムリソースをデプロイ済み
- OpenShift GitOps（Argo CD）でマニフェストを管理
- Visual Studio Code または OpenShift Dev Spaces から MTA Hub を利用
- LLM は OpenAI互換API、OpenShift AI、OpenAIなどを利用
- 現在の `Tackle` CRでは `spec.kai.enabled: false`

Solution Server は、承認されたコード修正や手動修正を Solved Example として蓄積し、後続の移行でLLMが生成する修正提案の精度向上に利用します。

> **重要**
>
> MTA 8.1 の Developer Lightspeed for MTA / Solution Server は Technology Preview です。本番業務の必須機能としてではなく、検証、デモ、ワークショップ用途として扱うことを推奨します。

---

## 2. Solution Serverの構成

Solution Serverを有効化すると、MTA Operatorは概ね次のコンポーネントを管理します。

```text
VS Code / OpenShift Dev Spaces
            |
            | MTA Hub URL
            v
+----------------------------------+
| MTA Hub                          |
|                                  |
|  +----------------------------+  |
|  | Kai API / Solution Server  |  |
|  +----------------------------+  |
|              |                   |
|  +----------------------------+  |
|  | Kai Database               |  |
|  | Solved Examples / Hints    |  |
|  +----------------------------+  |
+----------------------------------+
            |
            | OpenAI互換API
            v
      LLM / OpenShift AI
```

Solution Server APIはMTA Hub経由で公開されるため、通常はKai専用Routeを追加作成する必要はありません。

---

## 3. GitOps設計方針

### 3.1 管理対象

Gitリポジトリには次のリソースを格納します。

- `Tackle` カスタムリソース
- Secretの参照定義
- ExternalSecretまたはSealedSecret
- 必要に応じたStorageClass・PVC関連設定
- Argo CD Application
- 検証用JobやSmoke Test（任意）

### 3.2 Gitに格納してはいけないもの

次の値を平文でGitにコミットしないでください。

- LLM APIキー
- OpenAI APIキー
- OpenShift AI推論エンドポイントのBearer Token
- MTA管理者パスワード
- Keycloakクライアントシークレット

推奨方式は次のいずれかです。

1. External Secrets Operator + Vault / AWS Secrets Manager等
2. Bitnami Sealed Secrets
3. OpenShift GitOpsのVault Plugin
4. 手動Secret作成（検証用のみ）

---

## 4. 推奨リポジトリ構成

```text
gitops/
├── applications/
│   └── mta-instance.yaml
└── components/
    └── mta/
        ├── base/
        │   ├── kustomization.yaml
        │   ├── namespace.yaml
        │   ├── tackle.yaml
        │   └── externalsecret-kai-api-keys.yaml
        └── overlays/
            └── workshop/
                ├── kustomization.yaml
                └── tackle-patch.yaml
```

MTA OperatorのインストールとMTAインスタンスは、別のArgo CD Applicationに分けることを推奨します。

```text
Application: mta-operator
  Sync Wave: -30

Application: mta-instance
  Sync Wave: -20
```

Secret同期用Operatorを別管理する場合は、さらに前段に配置します。

```text
External Secrets Operator: -40
MTA Operator:              -30
MTA Instance:              -20
Dev Spaces設定:            -10
Workshop workloads:          0
```

---

## 5. 事前確認

### 5.1 MTA OperatorとTackle CR

```bash
oc get csv -n openshift-mta
oc get tackle -n openshift-mta
```

### 5.2 使用可能なCRDスキーマ

MTAのバージョンやOperator更新により、Kai設定のフィールド名が異なる場合があります。まず、実際のCRDを確認してください。

```bash
oc explain tackle.spec.kai
oc explain tackle.spec.kai --recursive
```

または、

```bash
oc get crd tackles.tackle.konveyor.io -o yaml \
  | yq '.spec.versions[] | select(.served == true) |
        .schema.openAPIV3Schema.properties.spec.properties.kai'
```

現在の環境では次の形式が存在しています。

```yaml
spec:
  kai:
    enabled: false
```

そのため、本書ではこのスキーマを優先します。

公式ドキュメントには旧形式として次のフィールドが記載される場合があります。

```yaml
spec:
  kai_solution_server_enabled: true
  kai_llm_provider: OpenAI
  kai_llm_model: <model-name>
  kai_llm_baseurl: <base-url>
```

実環境のCRDに存在しないフィールドを追加してもOperatorに無視される、またはAdmissionで拒否される可能性があります。必ず `oc explain` を正としてください。

### 5.3 Storage

Solution Serverのデータベースには、少なくとも **5GiのRWO永続ボリューム**が必要です。

確認例：

```bash
oc get storageclass
oc get pvc -n openshift-mta
```

動的プロビジョニング可能なデフォルトStorageClassがあれば、OperatorがPVCを作成できます。

---

## 6. LLM SecretのGitOps管理

MTA Solution ServerがLLMへ接続するため、`openshift-mta` Namespaceに `kai-api-keys` Secretを用意します。

代表的なキーは次のとおりです。

```text
OPENAI_API_BASE
OPENAI_API_KEY
```

OpenShift AIなど、OpenAI互換APIを利用する場合も同じ形式を使用できます。

### 6.1 ExternalSecretの例

```yaml
apiVersion: external-secrets.io/v1beta1
kind: ExternalSecret
metadata:
  name: kai-api-keys
  namespace: openshift-mta
  annotations:
    argocd.argoproj.io/sync-wave: "-25"
spec:
  refreshInterval: 1h
  secretStoreRef:
    kind: ClusterSecretStore
    name: workshop-secret-store
  target:
    name: kai-api-keys
    creationPolicy: Owner
  data:
    - secretKey: OPENAI_API_BASE
      remoteRef:
        key: mta/kai
        property: openai_api_base
    - secretKey: OPENAI_API_KEY
      remoteRef:
        key: mta/kai
        property: openai_api_key
```

SecretがTackleより先に作成されるよう、Sync WaveをTackleより小さい値にします。

### 6.2 SealedSecretの例

```yaml
apiVersion: bitnami.com/v1alpha1
kind: SealedSecret
metadata:
  name: kai-api-keys
  namespace: openshift-mta
  annotations:
    argocd.argoproj.io/sync-wave: "-25"
spec:
  encryptedData:
    OPENAI_API_BASE: <sealed-value>
    OPENAI_API_KEY: <sealed-value>
  template:
    metadata:
      name: kai-api-keys
      namespace: openshift-mta
    type: Opaque
```

### 6.3 手動作成例（検証用途のみ）

```bash
oc create secret generic kai-api-keys \
  -n openshift-mta \
  --from-literal=OPENAI_API_BASE='https://<openai-compatible-endpoint>/v1' \
  --from-literal=OPENAI_API_KEY='<api-key>'
```

Secretの中身を表示せず、存在だけ確認します。

```bash
oc get secret kai-api-keys -n openshift-mta
oc get secret kai-api-keys -n openshift-mta \
  -o jsonpath='{.data}' | jq 'keys'
```

期待値：

```json
[
  "OPENAI_API_BASE",
  "OPENAI_API_KEY"
]
```

---

## 7. Tackle CRの変更

### 7.1 現在の設定

現在はSolution Serverが無効です。

```yaml
spec:
  kai:
    enabled: false
```

### 7.2 GitOps用マニフェスト例

まず、CRDで利用可能なKai配下のフィールドを確認します。

```bash
oc explain tackle.spec.kai --recursive
```

`enabled` のみが提供される場合は、LLMの接続情報を `kai-api-keys` Secretに格納し、次のようにします。

```yaml
apiVersion: tackle.konveyor.io/v1alpha1
kind: Tackle
metadata:
  name: mta
  namespace: openshift-mta
  annotations:
    argocd.argoproj.io/sync-wave: "-20"
  labels:
    app.kubernetes.io/managed-by: openshift-gitops
    app.kubernetes.io/part-of: developer-lightspeed-workshop
spec:
  feature_auth_required: false

  analyzer_container_requests_cpu: "1"
  analyzer_container_requests_memory: 4Gi
  analyzer_container_limits_cpu: "2"
  analyzer_container_limits_memory: 8Gi

  cache_data_volume_size: 100Gi
  hub_bucket_volume_size: 100Gi
  hub_database_volume_size: 10Gi
  keycloak_database_data_volume_size: 1Gi

  kai:
    enabled: true
```

### 7.3 Kustomize Patch例

既存のTackleマニフェストを直接複製せず、overlayでKaiのみ有効化する構成を推奨します。

`overlays/workshop/tackle-patch.yaml`

```yaml
apiVersion: tackle.konveyor.io/v1alpha1
kind: Tackle
metadata:
  name: mta
  namespace: openshift-mta
spec:
  kai:
    enabled: true
```

`overlays/workshop/kustomization.yaml`

```yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization

resources:
  - ../../base

patches:
  - path: tackle-patch.yaml
```

### 7.4 旧スキーマを利用する場合

実際のCRDに以下のフィールドが存在する場合に限り、旧形式を利用します。

```yaml
spec:
  kai_solution_server_enabled: true
  kai_llm_provider: OpenAI
  kai_llm_model: <model-name>
  kai_llm_baseurl: https://<openai-compatible-endpoint>/v1
```

確認：

```bash
oc explain tackle.spec.kai_solution_server_enabled
oc explain tackle.spec.kai_llm_provider
oc explain tackle.spec.kai_llm_model
oc explain tackle.spec.kai_llm_baseurl
```

存在しない場合は使用しないでください。

---

## 8. Argo CD Application例

```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: mta-instance
  namespace: openshift-gitops
  annotations:
    argocd.argoproj.io/sync-wave: "-20"
spec:
  project: workshop-platform
  source:
    repoURL: https://git.example.com/workshop/platform-gitops.git
    targetRevision: main
    path: components/mta/overlays/workshop
  destination:
    server: https://kubernetes.default.svc
    namespace: openshift-mta
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
    syncOptions:
      - CreateNamespace=true
      - RespectIgnoreDifferences=true
      - ApplyOutOfSyncOnly=true
```

### 8.1 削除時の注意

`prune: true` にすると、Gitから削除したリソースはArgo CDにより削除されます。ただし、次のリソースは慎重に扱ってください。

- Kai Database PVC
- Hub Database PVC
- Hub Bucket PVC
- Solved Exampleのデータ

ワークショップの使い捨て環境ではPVCも削除対象にできますが、継続利用環境ではPVCを別Applicationで管理する、または削除保護を設定する方が安全です。

例：

```yaml
metadata:
  annotations:
    argocd.argoproj.io/sync-options: Prune=false
```

PVCをGit管理していない場合でも、OperatorやCR削除に伴う挙動を事前検証してください。

---

## 9. Sync順序

推奨順序は次のとおりです。

| Sync Wave | リソース |
|---:|---|
| -40 | External Secrets Operator / Sealed Secrets |
| -30 | MTA Operator |
| -25 | `kai-api-keys` Secret / ExternalSecret |
| -20 | `Tackle` CR |
| -10 | Dev Spaces / Workspace設定 |
| 0 | ワークショップアプリ |

Secretが後から作成された場合、Operatorの次回Reconcileで認識されることがあります。即時反映が必要な場合は、GitOpsの外でCRを手動編集せず、Syncまたは再Reconcileを行います。

Operatorが対応している場合の強制Reconcile例：

```bash
oc annotate tackle mta \
  -n openshift-mta \
  konveyor.io/force-reconcile="$(date +%s)" \
  --overwrite
```

この操作を恒常的なマニフェストへ時刻付きで書くと、毎回差分が生じるため、障害対応時の運用コマンドとして扱います。

---

## 10. デプロイ確認

### 10.1 Tackleの状態

```bash
oc get tackle mta -n openshift-mta -o yaml
```

Kai関連だけ確認：

```bash
oc get tackle mta -n openshift-mta -o yaml \
  | yq '.spec.kai, .status.conditions'
```

期待する状態の例：

```yaml
spec:
  kai:
    enabled: true
```

Statusでは、少なくとも次のConditionがTrueになることを確認します。

```text
KaiSolutionServerReady=True
KaiAPIKeysConfigured=True
Running=True
Successful=True
Failure=False
```

### 10.2 Deployment / Service

```bash
oc get deploy,svc -n openshift-mta \
  | grep -E 'kai-(api|db|importer)'
```

期待される主なリソース：

```text
kai-api
kai-db
kai-importer
```

実際の名称はOperatorバージョンにより異なる場合があります。

### 10.3 Pod

```bash
oc get pods -n openshift-mta \
  | grep -E 'kai|solution'
```

### 10.4 PVC

```bash
oc get pvc -n openshift-mta \
  | grep -E 'kai|solution'
```

PVCが `Pending` の場合は、StorageClass、容量、AccessModeを確認します。

```bash
oc describe pvc <kai-pvc-name> -n openshift-mta
```

### 10.5 ログ

```bash
oc logs deployment/kai-api -n openshift-mta --tail=200
oc logs deployment/kai-db -n openshift-mta --tail=200
oc logs deployment/kai-importer -n openshift-mta --tail=200
```

Deployment名が異なる場合：

```bash
oc get deploy -n openshift-mta | grep kai
```

---

## 11. VS Code / Dev Spaces側の設定

MTA拡張機能のHub Configurationを次のように設定します。

| 項目 | 設定 |
|---|---|
| Enable Hub | ON |
| Hub URL | MTA UI URL |
| Skip SSL certificate verification | 証明書エラー時のみON |
| Enable authentication | `feature_auth_required` に合わせる |
| Solution Server | ON |
| Profile Sync | ON |

今回の構成では、

```yaml
spec:
  feature_auth_required: false
```

であるため、VS Code側も次の設定です。

```text
Enable authentication: OFF
Solution Server: ON
Profile Sync: ON
```

Hub URLには、拡張機能の画面説明に従い、まずMTA UIのベースURLを指定します。

```text
https://mta-openshift-mta.apps.<cluster-domain>
```

`/hub` 付きが必要かどうかは、利用しているMTA拡張機能のバージョンと実装に依存する可能性があります。ベースURLで失敗する場合に、次を確認します。

```text
https://mta-openshift-mta.apps.<cluster-domain>/hub
```

設定変更後はVS CodeウィンドウまたはDev Spacesワークスペースを再読み込みします。

```text
Developer: Reload Window
```

---

## 12. Smoke Test

### 12.1 Hub疎通

Dev Spacesターミナルから確認します。

```bash
curl -k -I https://mta-openshift-mta.apps.<cluster-domain>/
curl -k -I https://mta-openshift-mta.apps.<cluster-domain>/hub/
```

### 12.2 Kai APIがHub経由で利用可能か確認

公開パスはバージョン差があるため、Routeを新規作成せず、まずHubログとKai APIログを確認します。

```bash
oc logs deployment/kai-api -n openshift-mta --tail=200
```

VS CodeでSolution ServerをONにした直後にアクセスログが出ることを確認します。

### 12.3 LLM接続

```bash
oc logs deployment/kai-api -n openshift-mta --tail=300 \
  | grep -i -E 'llm|openai|model|provider|error'
```

---

## 13. トラブルシューティング

### 13.1 `KaiSolutionServerReady=False`

確認：

```bash
oc get pods -n openshift-mta | grep kai
oc describe deploy kai-api -n openshift-mta
oc logs deploy/kai-api -n openshift-mta --tail=300
```

主な原因：

- `kai.enabled` が反映されていない
- Secretが存在しない
- PVCがPending
- イメージPull失敗
- LLMエンドポイントへ接続できない
- CRDスキーマとマニフェストが不一致

### 13.2 `KaiAPIKeysConfigured=False`

```bash
oc get secret kai-api-keys -n openshift-mta
```

キー名確認：

```bash
oc get secret kai-api-keys -n openshift-mta \
  -o jsonpath='{.data}' | jq 'keys'
```

期待値：

```text
OPENAI_API_BASE
OPENAI_API_KEY
```

ExternalSecret利用時：

```bash
oc get externalsecret kai-api-keys -n openshift-mta
oc describe externalsecret kai-api-keys -n openshift-mta
```

### 13.3 `Failed to connect to Hub solution server`

確認順序：

1. `spec.kai.enabled: true`
2. `KaiSolutionServerReady=True`
3. `kai-api` PodがReady
4. Hub URLへ疎通可能
5. VS CodeのSolution ServerがON
6. 認証設定がMTA側と一致
7. TLS証明書が信頼されている
8. VS CodeをReload済み

### 13.4 Argo CDで設定が戻される

手動で `oc edit tackle` を実施しても、Argo CDのSelf HealによりGitの内容へ戻されます。

修正は必ずGitリポジトリで行い、Pull Request、Merge、Argo CD Syncの順で反映してください。

### 13.5 Secret更新後も反映されない

次を実施します。

```bash
oc annotate tackle mta \
  -n openshift-mta \
  konveyor.io/force-reconcile="$(date +%s)" \
  --overwrite
```

または、Argo CDで対象Applicationを再Syncします。

---

## 14. 運用上の推奨

### ワークショップ環境

- `feature_auth_required: false` は閉じた検証環境に限定
- Solution Serverは参加者共通で利用可能
- LLM APIの使用量制限を設定
- ワークショップ終了後にKai DBを削除するか判断
- APIキーはExternalSecretまたはSealedSecretで管理

### 継続利用環境

- MTA認証を有効化
- 利用者ごとのRBACを設定
- Kai DBのバックアップ方針を定義
- LLM APIキーのローテーションを実施
- NetworkPolicyで通信先を制限
- API利用量、失敗率、レイテンシを監視
- Technology Previewであることを利用者へ明示

---

## 15. 実装チェックリスト

### GitOps

- [ ] MTA OperatorとMTA Instanceを別Applicationに分離
- [ ] Secret管理方式を決定
- [ ] Sync Waveを設定
- [ ] `prune` とPVC削除方針を確認
- [ ] `selfHeal` を有効化
- [ ] 手動変更を前提にしない

### MTA

- [ ] `oc explain tackle.spec.kai --recursive` を確認
- [ ] `spec.kai.enabled: true`
- [ ] `kai-api-keys` Secret作成
- [ ] 5Gi以上のRWOストレージを確保
- [ ] `KaiSolutionServerReady=True`
- [ ] `KaiAPIKeysConfigured=True`

### VS Code / Dev Spaces

- [ ] Enable Hub: ON
- [ ] Solution Server: ON
- [ ] Profile Sync: ON
- [ ] 認証設定がMTA側と一致
- [ ] Hub URL疎通確認
- [ ] VS CodeをReload

---

## 16. 参考となる最小構成

### `tackle.yaml`

```yaml
apiVersion: tackle.konveyor.io/v1alpha1
kind: Tackle
metadata:
  name: mta
  namespace: openshift-mta
  annotations:
    argocd.argoproj.io/sync-wave: "-20"
spec:
  feature_auth_required: false
  hub_database_volume_size: 10Gi
  hub_bucket_volume_size: 100Gi
  cache_data_volume_size: 100Gi
  keycloak_database_data_volume_size: 1Gi
  analyzer_container_requests_cpu: "1"
  analyzer_container_requests_memory: 4Gi
  analyzer_container_limits_cpu: "2"
  analyzer_container_limits_memory: 8Gi
  kai:
    enabled: true
```

### `externalsecret-kai-api-keys.yaml`

```yaml
apiVersion: external-secrets.io/v1beta1
kind: ExternalSecret
metadata:
  name: kai-api-keys
  namespace: openshift-mta
  annotations:
    argocd.argoproj.io/sync-wave: "-25"
spec:
  refreshInterval: 1h
  secretStoreRef:
    kind: ClusterSecretStore
    name: workshop-secret-store
  target:
    name: kai-api-keys
    creationPolicy: Owner
  data:
    - secretKey: OPENAI_API_BASE
      remoteRef:
        key: mta/kai
        property: openai_api_base
    - secretKey: OPENAI_API_KEY
      remoteRef:
        key: mta/kai
        property: openai_api_key
```

### `kustomization.yaml`

```yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization

resources:
  - tackle.yaml
  - externalsecret-kai-api-keys.yaml
```

---

## 17. 参考資料

- MTA 8.1 Configuring and Using Red Hat Developer Lightspeed for MTA
- MTA 8.1 Configuring and using the Visual Studio Code Extension for MTA
- MTA 8.1 Installing the migration toolkit for applications

公式ドキュメントでは、Solution Server用に追加の5Gi RWOストレージが必要であり、`kai-api-keys` SecretにLLMのBase URLとAPIキーを設定します。また、Solution Server APIはMTA Hub経由で提供され、追加Routeは不要とされています。

---

## 18. MTA Operator 8.1.2でSolution Serverが起動しない場合の追加考察

### 18.1 CSVから確認できること

MTA Operator 8.1.2のClusterServiceVersion（CSV）には、Solution Server関連のコンテナイメージが明示的に含まれています。

```yaml
relatedImages:
  - name: mta-solution-server-rhel9
    image: registry.redhat.io/mta/mta-solution-server-rhel9@sha256:...
  - name: lightspeed-stack-rhel9
    image: registry.redhat.io/lightspeed-core/lightspeed-stack-rhel9@sha256:...
```

また、Operator Deploymentには次の環境変数があります。

```yaml
- name: RELATED_IMAGE_KAI
  value: registry.redhat.io/mta/mta-solution-server-rhel9@sha256:...
- name: RELATED_IMAGE_LIGHTSPEED_STACK
  value: registry.redhat.io/lightspeed-core/lightspeed-stack-rhel9@sha256:...
```

したがって、MTA Operator 8.1.2自体はSolution Serverをデプロイする能力を持っています。

一方で、`Tackle` CRに次だけを設定しても、起動に必要な構成が不足する可能性があります。

```yaml
spec:
  kai:
    enabled: true
```

### 18.2 起動失敗の主な原因候補

Solution Serverの起動失敗時は、次の順で確認します。

1. `kai-api-keys` Secretが存在しない
2. Secretのキー名がOperatorの期待値と一致しない
3. LLM Provider、Model、Base URLの設定が不足している
4. Tackle CRのフィールド名がOperator 8.1.2のCRDと一致していない
5. Kai DB用PVCがPending
6. Solution Server PodがLLMエンドポイントへ接続できない
7. 認証無効構成とVS Code接続要件が衝突している

実際に次のConditionがある場合、

```yaml
type: KaiAPIKeysConfigured
status: "False"
reason: SecretNotFound
message: No API keys secret found. Some LLM providers may not work without authentication.
```

まず `kai-api-keys` Secretを最優先で確認します。

### 18.3 CSVのサンプルだけではKai設定は分からない

CSVの `alm-examples` や `operatorframework.io/initialization-resource` には、通常、最小のTackle CRしか掲載されていません。

```yaml
spec:
  feature_auth_required: "false"
```

このサンプルにKai関連設定がないことは、Solution Serverが未対応であることを意味しません。

CSVは主に次を確認するために利用します。

- Operatorバージョン
- Related Images
- Operatorの依存関係
- CRDの所有関係
- Operator Deploymentの環境変数

Kaiの正確な設定項目は、CSVではなく実際のCRDスキーマで確認します。

```bash
oc explain tackle.spec --recursive | grep -i -A5 -B3 kai
oc explain tackle.spec.kai --recursive
```

さらに、次の旧形式フィールドが存在するか確認します。

```bash
oc explain tackle.spec.kai_solution_server_enabled
oc explain tackle.spec.kai_llm_provider
oc explain tackle.spec.kai_llm_model
oc explain tackle.spec.kai_llm_baseurl
```

### 18.4 CRD差異への対応方針

MTAのドキュメント、Operator実装、CRDの更新タイミングにより、Kai関連のフィールドが次の2形式で見つかる可能性があります。

#### 形式A: ネスト形式

```yaml
spec:
  kai:
    enabled: true
```

#### 形式B: フラット形式

```yaml
spec:
  kai_solution_server_enabled: true
  kai_llm_provider: OpenAI
  kai_llm_model: <model-name>
  kai_llm_baseurl: https://<endpoint>/v1
```

どちらを使うかは、必ずクラスター上のCRDを正とします。

```bash
oc get crd tackles.tackle.konveyor.io -o yaml \
  | yq '.spec.versions[] |
        select(.served == true) |
        .schema.openAPIV3Schema.properties.spec.properties |
        with_entries(select(.key | test("kai"; "i")))'
```

CRDに存在しないフィールドをGitOpsマニフェストへ書かないでください。

### 18.5 `kai-api-keys` Secretの確認

まずSecretの存在を確認します。

```bash
oc get secret kai-api-keys -n openshift-mta
```

キー名だけ確認します。

```bash
oc get secret kai-api-keys -n openshift-mta \
  -o jsonpath='{.data}' | jq 'keys'
```

OpenAI互換APIを使う場合の代表例：

```json
[
  "OPENAI_API_BASE",
  "OPENAI_API_KEY"
]
```

GitOpsでは、次のようなExternalSecretを利用します。

```yaml
apiVersion: external-secrets.io/v1beta1
kind: ExternalSecret
metadata:
  name: kai-api-keys
  namespace: openshift-mta
  annotations:
    argocd.argoproj.io/sync-wave: "-25"
spec:
  refreshInterval: 1h
  secretStoreRef:
    kind: ClusterSecretStore
    name: workshop-secret-store
  target:
    name: kai-api-keys
    creationPolicy: Owner
  data:
    - secretKey: OPENAI_API_BASE
      remoteRef:
        key: mta/kai
        property: openai_api_base
    - secretKey: OPENAI_API_KEY
      remoteRef:
        key: mta/kai
        property: openai_api_key
```

### 18.6 OpenAI互換Base URLの注意

Base URLには通常、`/v1/chat/completions` まで含めず、OpenAI互換APIのルートを指定します。

```text
推奨:
https://maas-rhdp.apps.maas.redhatworkshops.io/v1

通常は避ける:
https://maas-rhdp.apps.maas.redhatworkshops.io/v1/chat/completions
```

Provider実装がChat Completionsのパスを内部付加するため、完全パスを入れると二重付加される可能性があります。

### 18.7 反映後の確認コマンド

```bash
oc get tackle mta -n openshift-mta -o json \
  | jq '.status.conditions[] |
        select(.type | test("Kai|Failure|Successful|Running"))'
```

期待値：

```text
KaiSolutionServerReady=True
KaiAPIKeysConfigured=True
Running=True
Successful=True
Failure=False
```

デプロイ済みリソースを確認します。

```bash
oc get deploy,svc,pod,pvc -n openshift-mta \
  | grep -E 'kai|solution'
```

Podの状態が不正常な場合：

```bash
oc get pods -n openshift-mta | grep kai
oc describe pod <kai-pod-name> -n openshift-mta
```

ログ確認：

```bash
oc get deploy -n openshift-mta | grep kai
oc logs deploy/kai-api -n openshift-mta --all-containers --tail=300
oc logs deploy/kai-db -n openshift-mta --all-containers --tail=300
oc logs deploy/kai-importer -n openshift-mta --all-containers --tail=300
```

実際のDeployment名が異なる場合は、`oc get deploy` の結果に合わせます。

### 18.8 GitOpsでの修正順序

推奨する反映順序は次のとおりです。

```text
1. Secret Store / External Secrets Operator
2. kai-api-keys ExternalSecret
3. kai-api-keys Secret生成確認
4. Tackle CRでKaiを有効化
5. Argo CD Sync
6. Tackle Status確認
7. Kai Pod / PVC / Logs確認
8. VS Code側でSolution Serverを有効化
```

Sync Waveの例：

| Sync Wave | リソース |
|---:|---|
| -40 | External Secrets Operator |
| -30 | MTA Operator |
| -25 | `kai-api-keys` ExternalSecret |
| -20 | `Tackle` CR |
| -10 | Dev Spaces設定 |

SecretとTackle CRを同じWaveにしないことを推奨します。

### 18.9 認証無効構成に関する注意

現在の構成が次の場合、

```yaml
spec:
  feature_auth_required: false
```

MTA UI / Hubの認証は無効です。

ただし、次は別々に確認する必要があります。

1. Solution Serverコンポーネントが正常起動するか
2. MTA Hub経由でSolution Server APIへ到達できるか
3. VS Code拡張が認証無効のHub構成でSolution Serverを利用できるか

KaiのPodが正常起動していても、VS Code側だけが次のエラーになる可能性があります。

```text
Failed to connect to Hub solution server
```

その場合は、起動失敗ではなく、VS Code拡張とHubの認証・URL・バージョン互換性の問題として切り分けます。

### 18.10 実装時の判断基準

次の状態なら、MTA側のSolution Serverは正常です。

```text
kai-api-keys Secretあり
KaiAPIKeysConfigured=True
KaiSolutionServerReady=True
Kai PodがReady
Kai DB PVCがBound
Kai APIログに致命的エラーなし
```

この状態でVS Code接続だけ失敗する場合は、次を確認します。

- Hub URLのベースURL / `/hub` の違い
- Solution Server設定のON/OFF
- `feature_auth_required` とVS Code側認証設定の整合性
- MTA VS Code Extensionのバージョン
- TLS証明書
- Dev SpacesからMTA Routeへの疎通

---

## 19. `KAI_LLM_PARAMS` が `null` の場合の原因と修正

### 19.1 事象

`kai-api` Deploymentを確認した際に、次のような設定になっている場合があります。

```yaml
- name: KAI_LLM_PARAMS
  value: '{
    "model": null,
    "model_provider": null,
    "configurable_fields": {
      "temperature": null,
      "max_tokens": null,
      "max_retries": null,
      "base_url": null,
      "kwargs": {}
    }
  }'
```

同時に、APIキーとBase URLはSecretから正しく注入されていることがあります。

```yaml
- name: OPENAI_API_BASE
  valueFrom:
    secretKeyRef:
      name: kai-api-keys
      key: OPENAI_API_BASE

- name: OPENAI_API_KEY
  valueFrom:
    secretKeyRef:
      name: kai-api-keys
      key: OPENAI_API_KEY
```

この状態では、Secretは正しく参照されていますが、Solution Serverが利用するLLMのProviderとModelが未設定です。

### 19.2 状態の解釈

この状態は次のように整理できます。

```text
MTA Hub接続              正常
Solution Server起動      正常
kai-api-keys Secret      正常
OPENAI_API_KEY注入       正常
OPENAI_API_BASE注入      正常
LLM Provider             未設定
LLM Model                未設定
KAI_LLM_PARAMS           不完全
```

そのため、VS Code側では次のようなエラーになる可能性があります。

```text
Failed to establish connection to the model.

401 You didn't provide an API key.
You need to provide your API key in an Authorization header
using Bearer auth.
```

401という表示でも、Secret自体が空とは限りません。LLMクライアントの初期化に必要なProviderとModelが未設定のため、正しい認証付きリクエストが構築されていない可能性があります。

### 19.3 確認コマンド

`KAI_LLM_PARAMS` の値を確認します。

```bash
oc get deploy kai-api -n openshift-mta -o json \
  | jq -r '
    .spec.template.spec.containers[]
    | select(.name=="kai-solution-server")
    | .env[]
    | select(.name=="KAI_LLM_PARAMS")
    | .value
  ' | jq
```

問題がある場合の例：

```json
{
  "model": null,
  "model_provider": null,
  "configurable_fields": {
    "temperature": null,
    "max_tokens": null,
    "max_retries": null,
    "base_url": null,
    "kwargs": {}
  }
}
```

### 19.4 CRDで利用可能なフィールドを確認

Tackle CRへ設定を追加する前に、実際のCRDを確認します。

```bash
oc explain tackle.spec --recursive \
  | grep -i -A5 -B3 -E 'kai|llm|model|provider'
```

個別確認：

```bash
oc explain tackle.spec.kai --recursive
oc explain tackle.spec.kai_solution_server_enabled
oc explain tackle.spec.kai_llm_provider
oc explain tackle.spec.kai_llm_model
oc explain tackle.spec.kai_llm_baseurl
```

クラスター上のCRD定義を直接確認する場合：

```bash
oc get crd tackles.tackle.konveyor.io -o yaml \
  | yq '.spec.versions[] |
        select(.served == true) |
        .schema.openAPIV3Schema.properties.spec.properties |
        with_entries(select(.key | test("kai|llm"; "i")))'
```

### 19.5 Tackle CRの修正例

CRDがフラット形式をサポートしている場合は、次のように設定します。

```yaml
apiVersion: tackle.konveyor.io/v1alpha1
kind: Tackle
metadata:
  name: mta
  namespace: openshift-mta
spec:
  feature_auth_required: false

  kai:
    enabled: true

  kai_solution_server_enabled: true
  kai_llm_provider: OpenAI
  kai_llm_model: codellama-7b-instruct
  kai_llm_baseurl: https://maas-rhdp.apps.maas.redhatworkshops.io/v1
```

モデル名は、実際にMAASまたはOpenAI互換APIで公開されているモデルIDと完全一致させます。

例：

```yaml
kai_llm_model: codellama-7b-instruct
```

### 19.6 Base URLの指定

通常はOpenAI互換APIのベースURLを指定します。

```text
推奨:
https://maas-rhdp.apps.maas.redhatworkshops.io/v1
```

次のようにChat Completionsの完全パスまで指定するのは避けます。

```text
非推奨:
https://maas-rhdp.apps.maas.redhatworkshops.io/v1/chat/completions
```

Provider実装が内部で `/chat/completions` を付加する場合、完全パスを指定するとURLが重複する可能性があります。

### 19.7 GitOps Patch例

既存のTackle CRをKustomizeで管理している場合は、OverlayにPatchを追加します。

`overlays/workshop/tackle-kai-patch.yaml`

```yaml
apiVersion: tackle.konveyor.io/v1alpha1
kind: Tackle
metadata:
  name: mta
  namespace: openshift-mta
spec:
  kai:
    enabled: true
  kai_solution_server_enabled: true
  kai_llm_provider: OpenAI
  kai_llm_model: codellama-7b-instruct
  kai_llm_baseurl: https://maas-rhdp.apps.maas.redhatworkshops.io/v1
```

`overlays/workshop/kustomization.yaml`

```yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization

resources:
  - ../../base

patches:
  - path: tackle-kai-patch.yaml
```

### 19.8 反映順序

推奨順序：

```text
1. kai-api-keys Secretを作成
2. Secretのキー名を確認
3. Tackle CRへLLM Provider / Model / Base URLを追加
4. Argo CD Sync
5. Tackle CRのReconcile
6. kai-api Deployment更新確認
7. KAI_LLM_PARAMS確認
8. VS CodeをReload
```

Sync Wave例：

| Sync Wave | リソース |
|---:|---|
| -25 | `kai-api-keys` ExternalSecret |
| -20 | `Tackle` CR |

### 19.9 反映後の期待値

Argo CD Sync後、次を確認します。

```bash
oc get deploy kai-api -n openshift-mta -o json \
  | jq -r '
    .spec.template.spec.containers[]
    | select(.name=="kai-solution-server")
    | .env[]
    | select(.name=="KAI_LLM_PARAMS")
    | .value
  ' | jq
```

期待例：

```json
{
  "model": "codellama-7b-instruct",
  "model_provider": "OpenAI",
  "configurable_fields": {
    "temperature": null,
    "max_tokens": null,
    "max_retries": null,
    "base_url": "https://maas-rhdp.apps.maas.redhatworkshops.io/v1",
    "kwargs": {}
  }
}
```

少なくとも、次が `null` でなくなることを確認します。

```text
model
model_provider
```

### 19.10 Pod再起動とReconcile

Tackle CR変更後はOperatorがDeploymentを更新します。

```bash
oc rollout status deployment/kai-api -n openshift-mta
```

必要に応じてReconcileを促します。

```bash
oc annotate tackle mta \
  -n openshift-mta \
  konveyor.io/force-reconcile="$(date +%s)" \
  --overwrite
```

これは障害対応用の一時操作として扱い、時刻付きannotationをGit管理しないでください。

### 19.11 ログ確認

```bash
oc logs deploy/kai-api \
  -n openshift-mta \
  -c kai-solution-server \
  --tail=300
```

認証・モデル関連に絞る場合：

```bash
oc logs deploy/kai-api \
  -n openshift-mta \
  -c kai-solution-server \
  --tail=500 \
  | grep -i -E '401|authorization|api.key|model|provider|openai'
```

### 19.12 VS Code側の注意

Solution Server側の設定が正常でも、VS Code側で次が表示される場合があります。

```text
No active profile selected
```

この場合は、Hubから同期した分析プロファイルを選択します。

また、`provider-settings.yaml` を直接利用する構成では、対象モデルに `&active` が付いていることを確認します。

```yaml
models:
  workshop-model: &active
    environment:
      OPENAI_API_BASE: "https://maas-rhdp.apps.maas.redhatworkshops.io/v1"
      OPENAI_API_KEY: "<api-key>"
    args:
      model: "codellama-7b-instruct"
```

Solution Server用Secretと、VS Code側のProvider設定は別経路として扱います。

### 19.13 判定基準

次の状態なら、MTA側のLLM設定は正常です。

```text
kai-api-keys Secretあり
OPENAI_API_KEY注入済み
OPENAI_API_BASE注入済み
KAI_LLM_PARAMS.model設定済み
KAI_LLM_PARAMS.model_provider設定済み
KaiSolutionServerReady=True
KaiAPIKeysConfigured=True
kai-api Pod Ready
```

この状態で401が続く場合は、次を確認します。

- APIキーそのものの有効性
- MAAS側がBearer Tokenを要求しているか
- モデルIDの誤り
- Base URLの誤り
- VS Code側のProvider設定
- MTA拡張機能とMTA Operatorのバージョン整合性

