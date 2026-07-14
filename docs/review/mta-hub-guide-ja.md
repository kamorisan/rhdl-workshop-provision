# MTA Hub ガイド
## 機能、サポートレベル、ユースケース、構築・設定方法

## 1. 結論

MTA Hubそのものは、Migration Toolkit for Applications（MTA）のサーバー側中核コンポーネントとして、MTA UIとともに提供される正式機能である。

ただし、MTA Hubに関連するすべての機能がGAというわけではない。MTA 8.1では、機能ごとにサポートレベルが異なる。

| 項目 | サポートレベル | 補足 |
|---|---|---|
| MTA UI / Hub基盤 | GA | MTA OperatorでOpenShiftへ導入 |
| Hub API / 認証 / DB | GA | MTA UIのバックエンド機能 |
| 集中設定管理 | GA扱い | MTA 8.1のNew Features and Enhancementsに記載 |
| LLM Proxy | GA扱い | MTA 8.1のNew Features and Enhancementsに記載 |
| Analysis Profile | Technology Preview | 本番利用は非推奨 |
| HubからのProfile Sync | Technology Preview | Analysis Profile機能に依存 |
| Solution Server | Technology Preview相当 | Developer Lightspeed for MTA自体がTechnology Preview |
| Developer Lightspeed for MTA | Technology Preview | 本番SLA対象外 |
| Agent Mode | Technology Preview / 実験的 | ワークショップ・検証向け |

重要なのは、**MTA HubはGAだが、Hubを使ったProfile SyncやDeveloper Lightspeed関連機能にはTechnology Previewが含まれる**という点である。

したがって、今回のようなハンズオンワークショップには非常に適しているが、本番業務での標準化基盤として採用する場合は、利用する個別機能のサポートレベルを確認する必要がある。

---

## 2. MTA Hubとは

MTA Hubは、OpenShift上にMTA Operatorで構築されるMTA環境の中核バックエンドである。

単独の別製品ではなく、MTA UI、API、認証、データベース、解析設定、ルール、Developer Lightspeed関連機能などを集中管理するサーバー側コンポーネントである。

```text
OpenShift
└── MTA
    ├── MTA Web UI
    ├── Hub API
    ├── Hub Database
    ├── Keycloak / Red Hat build of Keycloak
    ├── Analyzer
    ├── Task Manager
    ├── Profile / Custom Rules管理
    ├── LLM Proxy
    └── Solution Server（オプション）
```

クライアント側は、次のコンポーネントからHubへ接続できる。

- MTA Web UI
- MTA CLI
- MTA VS Code Extension
- Dev Spaces上のVS Code
- 自動化ツール

---

## 3. MTA Hubの主な機能

### 3.1 MTA UIのバックエンド

MTA Hubは、MTA Web UIが利用するバックエンドAPIとデータ管理機能を提供する。

MTA UIでは次の操作が可能。

- Application Inventory管理
- Assessment
- Analysis
- Credentials管理
- Source Repository管理
- Custom Rules管理
- Migration Wave管理
- Jira連携
- Profile管理
- Platform Awareness
- Asset Generation

### 3.2 解析設定の集中管理

MTA 8.1では、UI、CLI、VS Code Extension間で解析設定とカスタムルールを標準化するための集中管理機能が追加された。

アーキテクトはHub側で次を管理する。

- Source technology
- Target technology
- Analysis mode
- Dependency analysis
- Custom rules
- Default rules
- Label selector
- Exclude packages
- Known libraries
- Analysis Profile

```text
MTA Hub
├── Spring Boot → Quarkus Profile
├── WebLogic → EAP Profile
├── Cloud Readiness Profile
└── Custom Rules
        ↓
VS Code / Dev Spaces / CLI
```

### 3.3 Analysis Profile

Analysis Profileは、解析条件とルールをまとめた再利用可能な設定単位である。

代表項目:

- Profile名
- Source
- Target
- Dependenciesを含めるか
- Known librariesを含めるか
- Analysis mode
- Label selector
- Custom rules
- Exclude packages

MTA 8.1では、Analysis ProfileはTechnology Previewである。

### 3.4 Profile Sync

VS Code ExtensionやMTA CLIはHubからProfileとCustom Rulesを同期できる。

同期先:

```text
.konveyor/profiles/
```

MTA CLI例:

```bash
mta-cli config login
mta-cli config sync \
  --url https://github.com/example/app \
  --application-path /projects/app \
  --insecure
```

### 3.5 LLM Proxy

MTA 8.1では、クライアントがLLM APIキーを直接保持せず、Hub側Proxyを経由してLLMへ接続できる。

```text
Dev Spaces / VS Code
        ↓ Keycloak JWT
MTA Hub / LLM Proxy
        ↓ Cluster Secret
LLM API / MaaS / OpenShift AI
```

メリット:

- APIキーを各Workspaceへ配布しなくてよい
- APIキーを利用者に見せずに済む
- APIキーのローテーションを集中管理できる
- モデル変更を管理者側で制御できる
- 複数人ワークショップで設定差異を減らせる

### 3.6 Solution Server

Solution Serverは、過去に採用されたコード修正例や移行パターンを蓄積し、次回以降のコード修正提案へ活用する。

主な役割:

- Accepted Solutionの保存
- Solved Examplesの蓄積
- Migration Hintの生成
- 組織内の移行知識の再利用
- LLMへ渡すコンテキストの強化

最初のワークショップでは無効、発展編で有効にする方が安全である。

---

## 4. 想定ユースケース

### 4.1 複数人ハンズオンワークショップ

今回のユースケースに最も適している。

Hubなしでは各WorkspaceにLocal Profile、Custom Rules、provider-settings.yaml、LLM API Keyを個別配布する必要がある。

Hubありでは、共通Profile、共通Rules、LLM Proxy、認証を中央管理できる。

### 4.2 組織内の移行標準化

- WebLogic → EAP
- Spring Boot → Quarkus
- Java EE → Jakarta EE
- OpenJDKアップグレード
- Cloud Readiness
- Containerization
- 社内独自フレームワーク移行

### 4.3 カスタムルールの集中管理

- 社内共通ログAPIの置換
- 独自認証ライブラリの移行
- 古いJDBC Driverの検出
- 非推奨APIの検出
- Quarkusで利用不可のライブラリ検出

### 4.4 LLM APIキーの集中管理

各Workspaceへキーを配るのではなく、Hub側Secretで管理する。

---

## 5. ワークショップ向け推奨アーキテクチャ

```text
OpenShift Cluster
│
├── OpenShift Dev Spaces
│   ├── user01 Workspace
│   ├── user02 Workspace
│   ├── user03 Workspace
│   └── ...
│
├── MTA
│   ├── MTA UI
│   ├── Hub API
│   ├── Keycloak
│   ├── Hub DB
│   ├── LLM Proxy
│   └── Solution Server（任意）
│
├── OpenShift GitOps
│   ├── Namespace
│   ├── RBAC
│   ├── ResourceQuota
│   ├── NetworkPolicy
│   └── MTA / Dev Spaces設定
│
└── External LLM / MaaS
    └── gpt-oss-120bなど
```

推奨段階:

- Phase 1: MTA Hub + Profile Sync + LLM Proxy、Solution Serverなし
- Phase 2: 上記にSolution Serverを追加

---

## 6. 前提条件

- OpenShift Container Platform
- MTA 8.1 Operator
- StorageClass
- RWO Persistent Volume
- 必要に応じてRWX Persistent Volume
- Red Hat build of KeycloakまたはMTA内蔵認証
- LLM API
- LLM API Key
- OpenShift Dev Spaces 3.29
- MTA VS Code Extension
- Java 17以上
- Maven 3.9.9以上
- Git

---

## 7. MTA Hubの構築

### 7.1 MTA Operatorの導入

OperatorHubからMigration Toolkit for Applications Operatorをインストールする。

推奨Namespace:

```text
openshift-mta
```

確認:

```bash
oc get csv -n openshift-mta
oc get pods -n openshift-mta
```

### 7.2 Tackle CRの作成

```yaml
apiVersion: tackle.konveyor.io/v1alpha1
kind: Tackle
metadata:
  name: mta
  namespace: openshift-mta
spec:
  feature_auth_required: true
  feature_isolate_namespace: true
```

実際のapiVersionやkindは導入したOperatorのCRDを確認する。

```bash
oc api-resources | grep -i tackle
oc explain tackle.spec
```

### 7.3 ストレージ設定

MTA 8.1の代表的なデフォルト:

| 項目 | デフォルト |
|---|---:|
| Hub DB | 10Gi |
| Hub Bucket | 100Gi |
| Keycloak DB | 1Gi |
| Cache | 100Gi |
| Analyzer Memory | 4Gi |
| Analyzer CPU | 1 |

代表設定例:

```yaml
spec:
  hub_database_volume_size: 10Gi
  hub_bucket_volume_size: 100Gi
  keycloak_database_data_volume_size: 1Gi
  analyzer_container_requests_memory: 4Gi
  analyzer_container_limits_memory: 8Gi
  analyzer_container_requests_cpu: "1"
  analyzer_container_limits_cpu: "2"
```

### 7.4 認証設定

複数人ワークショップでは認証を有効にする。

```yaml
spec:
  feature_auth_required: true
```

### 7.5 Route確認

```bash
oc get route -n openshift-mta
```

MTA UI URL例:

```text
https://mta-openshift-mta.apps.cluster.example.com
```

Hub endpoint例:

```text
https://mta-openshift-mta.apps.cluster.example.com/hub
```

---

## 8. Hub側設定

### 8.1 ユーザー・ロール

- Administrator
- Architect
- Migrator

ワークショップでは、講師をAdministrator / Architect、参加者をMigratorとする。

### 8.2 Analysis Profile作成

例:

```text
Name: spring-to-quarkus-workshop
Source: springboot
Target: quarkus
Mode: source-only または full
Default Rules: Enabled
Custom Rules: Workshop rules
Dependencies: Enabled
```

### 8.3 Custom Rules登録

- 手動Upload
- Git Repository
- Subversion Repository

ワークショップではGit Repository方式が推奨。

### 8.4 LLM Proxy設定

LLM APIキーはクラスタSecretへ登録する。

```yaml
apiVersion: v1
kind: Secret
metadata:
  name: mta-llm-secret
  namespace: openshift-mta
type: Opaque
stringData:
  OPENAI_API_KEY: "<api-key>"
```

Base URL例:

```text
https://maas-rhdp.apps.maas.redhatworkshops.io/v1
```

### 8.5 Solution Server設定

VS Code設定例:

```json
{
  "mta-vscode-extension.solutionServer": {
    "url": "https://mta.example.com/hub/services/kai/api",
    "enabled": true,
    "auth": {
      "enabled": true,
      "insecure": false,
      "realm": "mta"
    }
  }
}
```

---

## 9. Dev Spaces / VS Code側設定

### 9.1 必要な拡張

- Migration Toolkit for Applications
- MTA Core
- MTA Java
- Language Support for Java by Red Hat

### 9.2 Hub Configuration

```text
Enable Hub: ON
Hub URL: https://mta-openshift-mta.apps.cluster.example.com
Skip SSL certificate verification: 必要な場合のみON
Enable Authentication: ON
Username: MTAユーザー
Password: MTAパスワード
Profile Sync: ON
Solution Server: 必要に応じてON
```

### 9.3 CLI接続

```bash
mta-cli config login
```

```text
Host: https://mta-openshift-mta.apps.cluster.example.com/hub
Username: workshop-user01
Password: ********
```

同期:

```bash
mta-cli config sync \
  --url https://github.com/kamorisan/spring-to-quarkus-sample \
  --application-path /projects/spring-to-quarkus-sample \
  --insecure
```

---

## 10. GitOpsで管理すべきもの

### GitOps対象

- MTA Operator Subscription
- OperatorGroup
- Namespace
- Tackle CR
- Storage設定
- NetworkPolicy
- ResourceQuota
- Route設定
- LLM Secret
- Custom Rules Repository
- Workshop Profile作成用Job
- User / Role初期化
- Dev Spaces設定

### GitOps管理に注意が必要

- Hub DB内部データ
- Analysis結果
- Solution Server学習データ
- ユーザー個別設定
- Password
- Runtime Token

---

## 11. 同時実行時の設計ポイント

### MTA側

- Analyzer PodのCPU・メモリ
- Hub APIの同時接続数
- DB性能
- Task数
- Solution Server負荷

### LLM側

- Rate Limit
- Token Limit
- Concurrent Requests
- Timeout
- Model Latency
- Usage Quota

### Dev Spaces側

- Workspace CPU
- Workspace Memory
- Java Language Server
- Analyzer RPC
- PVC
- Node Capacity

推奨目安:

```text
Dev Spaces Workspace: 2 CPU / 8Gi Memory
MTA Analyzer: 1〜2 CPU / 4〜8Gi Memory
LLM: 参加人数分の同時実行を事前検証
```

---

## 12. セキュリティ

- LLM APIキーは各Workspaceへ配布しない
- LLM Proxyを利用する
- Keycloak認証を有効にする
- TLS検証Skipはワークショップ限定
- SecretをGitへ平文保存しない
- External SecretsまたはSealed Secretsを使う
- NetworkPolicyで接続先を制限する
- 参加者はMigratorロールのみ付与する
- Solution Serverへ機密コードを保存しない
- ワークショップ終了後にユーザーとデータを削除する

---

## 13. ワークショップ向け推奨構成

最初の実装:

```text
MTA Hub
+ Authentication
+ Common Profile
+ Custom Rules
+ LLM Proxy
- Solution Server
```

発展構成:

```text
MTA Hub
+ Authentication
+ Common Profile
+ Custom Rules
+ LLM Proxy
+ Solution Server
```

---

## 14. サポートレベルに関する最終判断

MTA Hub基盤はGAとして利用できる。

一方で、今回のワークショップで重要になる次の機能はTechnology Previewを含む。

- Analysis Profile
- Profile Sync
- Developer Lightspeed for MTA
- Solution Server
- Agent Mode

したがって、今回の用途では次の表現が適切。

> MTA HubはGAのMTA基盤機能である。  
> ただし、Hubを利用したAnalysis Profile同期やDeveloper Lightspeed関連機能の一部はTechnology Previewであり、本番SLA対象外である。  
> ハンズオン、PoC、技術検証には適しているが、本番標準化基盤として採用する場合は、利用機能ごとにサポートレベルを確認する必要がある。

---

## 15. 参考資料

- Migration Toolkit for Applications 8.1 Release Notes
- Installing the migration toolkit for applications
- Configuring and managing the Migration Toolkit for Applications user interface
- Configuring and using the Visual Studio Code Extension for MTA
- Using the migration toolkit for applications command-line interface
- Configuring and Using Red Hat Developer Lightspeed for MTA
