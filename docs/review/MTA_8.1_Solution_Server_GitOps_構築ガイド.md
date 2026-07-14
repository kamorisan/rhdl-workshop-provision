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
