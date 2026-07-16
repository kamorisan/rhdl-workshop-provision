# JBoss EAP 7.4 アプリケーション移行ワークショップ環境構築手順

## 1. 目的

本ドキュメントは、OpenShift Dev Spaces 上で JBoss EAP 7.4 アプリケーションをビルドし、将来的に JBoss EAP 8.1 へ移行するワークショップ環境について、ここまで実施した作業と、次に実施すべき作業を整理したものです。

対象ユーザー Namespace は次のとおりです。

```text
user01-dev
user02-dev
...
user10-dev
```

作業用リポジトリ：

```text
https://github.com/kamorisan/coolstore-eap7.4to8.1
```

---

# 2. ここまでに実施した作業

## 2.1 PostgreSQL 用 Secret の作成

アプリケーションから PostgreSQL に接続するため、各ユーザー Namespace にデータベース接続用 Secret を作成します。

例：

```yaml
apiVersion: v1
kind: Secret
metadata:
  name: coolstore-database-secret
  namespace: user01-dev
type: Opaque
stringData:
  DB_HOST: coolstore-postgresql
  DB_PORT: "5432"
  DB_NAME: postgres
  DB_USERNAME: postgres
  DB_PASSWORD: <password>
```

適用例：

```bash
oc apply -f coolstore-database-secret.yaml
```

## 2.2 standalone-full.xml のデータベース接続設定変更

EAP の設定ファイルで、データベース接続情報を環境変数から取得するように変更しました。

```xml
<connection-url>
  jdbc:postgresql://${env.DB_HOST:localhost}:${env.DB_PORT:5432}/${env.DB_NAME:postgres}
</connection-url>

<user-name>${env.DB_USERNAME:postgres}</user-name>
<password>${env.DB_PASSWORD:postgres}</password>
```

これにより、イメージ内に接続先やパスワードを固定せず、OpenShift の Secret や環境変数で切り替えられます。

## 2.3 EAP 7.4 ベースイメージの取得

Red Hat Registry にログインし、EAP 7.4 のコンテナイメージを取得しました。

```bash
podman login registry.redhat.io
```

```bash
podman pull \
  registry.redhat.io/jboss-eap-7/eap74-openjdk8-openshift-rhel8:latest
```

今回取得したイメージは、ビルドログ上では EAP 7.4.23 でした。

## 2.4 OpenShift Image Registry へのログイン

OpenShift Image Registry の Route を確認し、作業用環境変数に設定しました。

```bash
oc get route default-route -n openshift-image-registry
export REGISTRY_HOST=<OpenShift Image RegistryのRoute>
```

OpenShift のアクセストークンでログインしました。

```bash
TOKEN="$(oc whoami -t)"
printf '%s' "$TOKEN" | podman login \
  --username unused \
  --password-stdin \
  --tls-verify=false \
  "$REGISTRY_HOST"
```

## 2.5 共通 Namespace 方式の検討

当初は `workshop-system` にベースイメージを置き、各ユーザー Namespace から参照させる方式を検討しました。

```bash
for i in $(seq -w 1 10); do
  oc policy add-role-to-group \
    system:image-puller \
    "system:serviceaccounts:user${i}-dev" \
    -n workshop-system
done
```

ただし、ワークショップでは cross-namespace の pull 権限や ServiceAccount の説明が増えるため、各ユーザー Namespace へ同じイメージを配布する方式へ変更しました。

## 2.6 各ユーザー Namespace への EAP 7.4 イメージ配布

```bash
for i in $(seq -w 1 10); do
  NS="user${i}-dev"

  podman tag \
    registry.redhat.io/jboss-eap-7/eap74-openjdk8-openshift-rhel8:latest \
    "${REGISTRY_HOST}/${NS}/eap74-openjdk8:7.4"

  podman push \
    --remove-signatures \
    --tls-verify=false \
    "${REGISTRY_HOST}/${NS}/eap74-openjdk8:7.4"
done
```

`skipped: already exists` は、同じレイヤーが Registry に存在するため再転送を省略した正常な表示です。

## 2.7 ImageStreamTag の確認

```bash
for i in $(seq -w 1 10); do
  NS="user${i}-dev"
  echo "=== ${NS} ==="
  oc get istag eap74-openjdk8:7.4 -n "$NS"
done
```

すべて同一 digest であることを確認しました。

```text
sha256:ecaa6eaf6d3f261baa2a187e2f26360187141106fe97ac5895e42346ad5586be
```

## 2.8 内部 Registry への Podman ログイン

Dockerfile ではクラスター固有の外部 Route を使わず、内部 Registry の Service 名を使う方針としました。

```text
image-registry.openshift-image-registry.svc:5000
```

Dev Spaces 内の Podman から参照できるよう、内部 Registry にもログインしました。

```bash
INTERNAL_REGISTRY=image-registry.openshift-image-registry.svc:5000
TOKEN="$(oc whoami -t)"

printf '%s' "$TOKEN" | podman login \
  --username unused \
  --password-stdin \
  --tls-verify=false \
  "$INTERNAL_REGISTRY"
```

pull 確認：

```bash
podman pull \
  --tls-verify=false \
  image-registry.openshift-image-registry.svc:5000/user01-dev/eap74-openjdk8:7.4
```

## 2.9 Dockerfile の作成

```dockerfile
FROM maven:3.9.9-eclipse-temurin-8 AS builder

WORKDIR /workspace
COPY pom.xml .
COPY src ./src
RUN mvn -B clean package -DskipTests

FROM image-registry.openshift-image-registry.svc:5000/user01-dev/eap74-openjdk8:7.4

COPY --from=builder \
  --chown=185:0 \
  /workspace/target/ROOT.war \
  /opt/eap/standalone/deployments/ROOT.war

COPY --chown=185:0 \
  standalone-full.xml \
  /opt/eap/standalone/configuration/standalone-full.xml

USER 185
EXPOSE 8080
```

Maven ビルド自体は成功しています。

```text
BUILD SUCCESS
```

## 2.10 Podman ビルド時のストレージ不足

```bash
podman build \
  --tls-verify=false \
  -t coolstore-eap74:local .
```

EAP イメージへの WAR 配置時に次のエラーが発生しました。

```text
no space left on device
```

これはメモリ不足ではなく、Podman の rootless コンテナストレージ不足です。

確認コマンド：

```bash
podman system df
df -h
du -sh ~/.local/share/containers 2>/dev/null
```

不要なイメージやキャッシュを削除しました。

```bash
podman system prune -a -f
podman volume prune -f
buildah rm --all
```

約 3.2GB 解放されましたが、再ビルドでも同じエラーが再発しました。

---

# 3. 現在の課題

## 3.1 Dev Spaces 内 Podman ストレージが不足している

`memoryLimit` を増やしても、今回の問題は基本的に解決しません。確認すべき対象は Podman の `graphroot` です。

```bash
podman info --format '{{.Store.GraphRoot}}'
df -h "$(podman info --format '{{.Store.GraphRoot}}')"
```

## 3.2 ワークショップ参加者全員で再発する可能性がある

各参加者が Dev Spaces 内でビルドすると、Maven イメージ、EAP イメージ、中間レイヤー、最終イメージを各ワークスペースに保持するため、同じ容量不足が起きる可能性があります。

---

# 4. 次に実施すべきこと

## 推奨案：OpenShift BuildConfig でビルドする

```text
Git リポジトリ
    ↓
OpenShift BuildConfig
    ↓
Dockerfile ビルド
    ↓
ImageStream
    ↓
Deployment
```

この方式では、Dev Spaces のローカル Podman ストレージ容量に依存しません。

## 4.1 Dockerfile を全ユーザー共通化する

```dockerfile
ARG EAP_BASE_IMAGE

FROM maven:3.9.9-eclipse-temurin-8 AS builder

WORKDIR /workspace
COPY pom.xml .
COPY src ./src
RUN mvn -B clean package -DskipTests

FROM ${EAP_BASE_IMAGE}

COPY --from=builder \
  --chown=185:0 \
  /workspace/target/ROOT.war \
  /opt/eap/standalone/deployments/ROOT.war

COPY --chown=185:0 \
  standalone-full.xml \
  /opt/eap/standalone/configuration/standalone-full.xml

USER 185
EXPOSE 8080
```

## 4.2 アプリケーション用 ImageStream の作成

```yaml
apiVersion: image.openshift.io/v1
kind: ImageStream
metadata:
  name: coolstore-eap74
  namespace: user01-dev
```

```bash
oc apply -f imagestream.yaml
```

## 4.3 BuildConfig の作成

```yaml
apiVersion: build.openshift.io/v1
kind: BuildConfig
metadata:
  name: coolstore-eap74
  namespace: user01-dev
spec:
  source:
    type: Git
    git:
      uri: https://github.com/kamorisan/coolstore-eap7.4to8.1
      ref: main
    contextDir: .

  strategy:
    type: Docker
    dockerStrategy:
      dockerfilePath: Dockerfile
      buildArgs:
        - name: EAP_BASE_IMAGE
          value: image-registry.openshift-image-registry.svc:5000/user01-dev/eap74-openjdk8:7.4

  output:
    to:
      kind: ImageStreamTag
      name: coolstore-eap74:latest

  triggers:
    - type: ConfigChange
```

```bash
oc apply -f buildconfig.yaml
oc start-build coolstore-eap74 -n user01-dev --follow
```

## 4.4 ビルド結果の確認

```bash
oc get builds -n user01-dev
oc get istag coolstore-eap74:latest -n user01-dev
oc logs buildconfig/coolstore-eap74 -n user01-dev
```

## 4.5 Deployment の作成

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: coolstore-eap74
  namespace: user01-dev
spec:
  replicas: 1
  selector:
    matchLabels:
      app: coolstore-eap74
  template:
    metadata:
      labels:
        app: coolstore-eap74
    spec:
      containers:
        - name: coolstore-eap74
          image: image-registry.openshift-image-registry.svc:5000/user01-dev/coolstore-eap74:latest
          ports:
            - containerPort: 8080
          envFrom:
            - secretRef:
                name: coolstore-database-secret
          securityContext:
            allowPrivilegeEscalation: false
            capabilities:
              drop:
                - ALL
            runAsNonRoot: true
            seccompProfile:
              type: RuntimeDefault
```

## 4.6 Service と Route の作成

```yaml
apiVersion: v1
kind: Service
metadata:
  name: coolstore-eap74
  namespace: user01-dev
spec:
  selector:
    app: coolstore-eap74
  ports:
    - name: http
      port: 8080
      targetPort: 8080
---
apiVersion: route.openshift.io/v1
kind: Route
metadata:
  name: coolstore-eap74
  namespace: user01-dev
spec:
  to:
    kind: Service
    name: coolstore-eap74
  port:
    targetPort: http
  tls:
    termination: edge
```

確認：

```bash
oc get pods -n user01-dev
oc get route coolstore-eap74 -n user01-dev
```

---

# 5. 代替案：Podman ストレージを増やす場合

Podman ビルドを演習として残す場合は、Podman 専用 PVC を追加します。

```yaml
components:
  - name: dev-tools
    container:
      image: registry.redhat.io/devspaces/udi-rhel9:latest
      volumeMounts:
        - name: podman-storage
          path: /podman-storage

  - name: podman-storage
    volume:
      size: 15Gi
```

Podman の保存先を変更します。

```bash
mkdir -p ~/.config/containers
cat > ~/.config/containers/storage.conf <<'EOC'
[storage]
driver = "overlay"
graphroot = "/podman-storage"
runroot = "/tmp/podman-run"
EOC
```

確認：

```bash
podman info --format '{{.Store.GraphRoot}}'
```

容量目安：最低 10Gi、推奨 15〜20Gi。

ただし、ワークショップ全体の安定性を優先する場合は BuildConfig 方式を推奨します。

---

# 6. ワークショップ向け推奨構成

```text
EAP 7.4 ベースイメージ
  → 各ユーザー Namespace に事前配布

アプリケーションビルド
  → OpenShift BuildConfig

アプリケーション実行
  → Deployment / Service / Route

DB 接続情報
  → Secret

開発・修正
  → OpenShift Dev Spaces
```

主な利点：

- Red Hat Registry の認証情報を参加者へ配布しなくてよい
- cross-namespace の pull 権限が不要
- 外部 Registry Route を Dockerfile に固定しなくてよい
- Dev Spaces の Podman ストレージ不足を回避できる
- 各参加者の Namespace 内で完結できる
- EAP 7.4 と EAP 8.1 の比較がしやすい

---

# 7. 作業チェックリスト

- [x] EAP 7.4 ベースイメージ取得
- [x] 各ユーザー Namespace へのベースイメージ配布
- [x] ImageStreamTag の digest 確認
- [x] standalone-full.xml の環境変数対応
- [x] Maven ビルド成功確認
- [x] Podman のストレージ不足原因確認
- [ ] Dockerfile の Build Argument 対応
- [ ] ImageStream 作成
- [ ] BuildConfig 作成
- [ ] OpenShift 上でアプリケーションイメージをビルド
- [ ] Deployment 作成
- [ ] PostgreSQL 接続確認
- [ ] Service / Route 作成
- [ ] アプリケーション動作確認
- [ ] user02-dev〜user10-dev への展開テンプレート化
- [ ] EAP 8.1 用ベースイメージ準備
- [ ] MTA による EAP 7.4 → EAP 8.1 分析
- [ ] EAP 8.1 向け修正
- [ ] EAP 8.1 上で再ビルド・再デプロイ
- [ ] 移行前後の差分確認

---

# 8. 直近の次アクション

1. Dockerfile を `ARG EAP_BASE_IMAGE` 方式へ変更する
2. `user01-dev` に ImageStream を作成する
3. `user01-dev` に BuildConfig を作成する
4. OpenShift 上で Docker build を実行する
5. 生成イメージから Deployment を作成する
6. PostgreSQL 接続を確認する
7. Route 経由で Coolstore アプリケーションを確認する
8. 成功した YAML をテンプレート化し、`user02-dev`〜`user10-dev` に展開する
