# OpenShift Dev SpacesでMTA VS Code拡張を自動インストールする方法

## 1. 結論

OpenShift Dev Spaces上のVS Codeで、以下のMTA拡張をWorkspace起動時に自動インストールしたい場合、

- <https://open-vsx.org/extension/redhat/mta-vscode-extension>

推奨する方法は、Workspaceにcloneされるアプリケーションリポジトリへ、次のファイルを配置する方法である。

```text
.vscode/extensions.json
```

内容は以下。

```json
{
  "recommendations": [
    "redhat.mta-vscode-extension",
    "redhat.java"
  ]
}
```

MTA拡張に加えて、Javaアプリケーションの解析やDeveloper Lightspeed for MTAの利用に必要となる、`Language Support for Java by Red Hat`も合わせて指定する。

---

## 2. 現在のdevfile.yamlでエラーになる主な原因

対象のdevfile.yaml:

- <https://raw.githubusercontent.com/kamorisan/rhdl-workshop-provision/refs/heads/main/devfile.yaml>

主な問題として、次の可能性がある。

1. YAMLの構造や改行が正しく解釈されていない
2. VS Code拡張のインストールを`commands`だけで実現しようとしている
3. 拡張のインストール方式がDev Spacesの標準的な方法に沿っていない
4. `oc login`やパスワードがdevfile内に含まれている
5. MTA拡張に必要なメモリが不足する可能性がある

---

## 3. 推奨する構成

### 3.1 アプリケーションリポジトリ側

Workspaceにcloneされるリポジトリへ、`.vscode/extensions.json`を追加する。

今回の対象リポジトリ:

```text
https://github.com/kamorisan/spring-to-quarkus-sample
```

配置構成:

```text
spring-to-quarkus-sample/
├── .vscode/
│   └── extensions.json
├── pom.xml
└── src/
```

`.vscode/extensions.json`:

```json
{
  "recommendations": [
    "redhat.mta-vscode-extension",
    "redhat.java"
  ]
}
```

### 3.2 拡張ID

Open VSXのURL:

```text
https://open-vsx.org/extension/redhat/mta-vscode-extension
```

このURLから、拡張IDは次の形式になる。

```text
<publisher>.<extension>
```

したがって、MTA拡張のIDは次の通り。

```text
redhat.mta-vscode-extension
```

Java拡張は次の通り。

```text
redhat.java
```

---

## 4. 修正版devfile.yaml

```yaml
schemaVersion: 2.3.0

metadata:
  name: spring-to-quarkus-workshop
  displayName: Spring to Quarkus Migration Workshop
  description: >-
    Workshop environment for migrating a Spring Boot application
    to Quarkus by using MTA and Developer Lightspeed.
  language: java
  projectType: maven
  tags:
    - Java
    - Spring Boot
    - Quarkus
    - Migration
  version: 1.0.0

projects:
  - name: spring-to-quarkus-sample
    git:
      remotes:
        origin: https://github.com/kamorisan/spring-to-quarkus-sample.git
      checkoutFrom:
        revision: main

components:
  - name: dev-tools
    container:
      image: quay.io/devfile/universal-developer-image:ubi8-latest
      memoryRequest: 2Gi
      memoryLimit: 8Gi
      cpuRequest: 500m
      cpuLimit: 2000m
      mountSources: true
      sourceMapping: /projects
      env:
        - name: MAVEN_OPTS
          value: -Xmx2g
      volumeMounts:
        - name: m2
          path: /home/user/.m2

  - name: m2
    volume:
      size: 10Gi

commands:
  - id: maven-build
    exec:
      component: dev-tools
      workingDir: ${PROJECT_SOURCE}/spring-to-quarkus-sample
      commandLine: mvn clean package -DskipTests
      label: Build
      group:
        kind: build
        isDefault: true

  - id: maven-test
    exec:
      component: dev-tools
      workingDir: ${PROJECT_SOURCE}/spring-to-quarkus-sample
      commandLine: mvn test
      label: Test
      group:
        kind: test

  - id: run-app
    exec:
      component: dev-tools
      workingDir: ${PROJECT_SOURCE}/spring-to-quarkus-sample
      commandLine: mvn spring-boot:run
      label: Run Application
      group:
        kind: run
        isDefault: true
```

---

## 5. 主な修正ポイント

### 5.1 schemaVersionを2.3.0へ変更

Dev Spaces 3.29で利用する前提では、次のようにする。

```yaml
schemaVersion: 2.3.0
```

正常に生成されたDevWorkspaceでも、`schemaVersion: 2.3.0`が利用されていた。

### 5.2 拡張インストール用のcommandを削除

次のようなcommandを定義しても、拡張機能は自動インストールされない。

```yaml
commands:
  - id: install-mta-extension
```

単にメッセージを表示するだけの処理であれば、削除する。

VS Code拡張は`.vscode/extensions.json`から導入する。

### 5.3 oc loginをdevfileから削除

Workspaceコンテナ内では、Dev SpacesによってOpenShiftユーザーの認証情報が利用可能になる構成が一般的である。

そのため、次のような処理は原則不要。

```bash
oc login \
  -u "${USERNAME}" \
  -p "openshift"
```

特に、共通パスワードをdevfileへ直接記載するのは避ける。

Workspace起動後に次のコマンドで確認する。

```bash
oc whoami
oc project
oc get pods
```

### 5.4 メモリを増やす

MTA VS Code拡張は、Analyzer RPCやJava Language Serverを利用する。

そのため、4Giでは不足する可能性がある。

推奨例:

```yaml
memoryRequest: 2Gi
memoryLimit: 8Gi
```

クラスタリソースに余裕がない場合は、6Giから検証することも可能。

### 5.5 Mavenローカルリポジトリを永続化

Maven依存関係の再ダウンロードを避けるため、`.m2`をVolumeへマウントする。

```yaml
volumeMounts:
  - name: m2
    path: /home/user/.m2
```

```yaml
- name: m2
  volume:
    size: 10Gi
```

---

## 6. extensions.jsonを置く場所

`.vscode/extensions.json`は、devfile.yamlを管理しているリポジトリではなく、Workspace内へcloneされるプロジェクトリポジトリへ配置する。

今回のdevfileでは次のリポジトリがcloneされる。

```yaml
projects:
  - name: spring-to-quarkus-sample
    git:
      remotes:
        origin: https://github.com/kamorisan/spring-to-quarkus-sample.git
```

したがって、配置先は次のリポジトリ。

```text
https://github.com/kamorisan/spring-to-quarkus-sample
```

`rhdl-workshop-provision`側にだけ`.vscode/extensions.json`を配置しても、そのリポジトリ自体がWorkspaceへcloneされなければ、VS Codeは認識しない。

---

## 7. devfile.yamlだけで完結させる代替案

アプリケーションリポジトリへ`.vscode/extensions.json`を追加できない場合は、VSIXファイルをWorkspace起動時にダウンロードして導入する方法もある。

概念例:

```yaml
components:
  - name: dev-tools
    container:
      image: quay.io/devfile/universal-developer-image:ubi8-latest
      env:
        - name: DEFAULT_EXTENSIONS
          value: /tmp/mta-vscode-extension.vsix

commands:
  - id: download-mta-extension
    exec:
      component: dev-tools
      commandLine: |
        set -e
        curl --fail --location \
          "${MTA_EXTENSION_VSIX_URL}" \
          --output /tmp/mta-vscode-extension.vsix

events:
  postStart:
    - download-mta-extension
```

ただし、この方式には次の課題がある。

- VSIXの直接ダウンロードURLを固定する必要がある
- 拡張バージョン更新時の追従が必要
- Workspace起動時に外部アクセスが必要
- ダウンロード失敗時に拡張が入らない
- Open VSXへの接続性が必要
- `DEFAULT_EXTENSIONS`の適用タイミングとの整合性確認が必要

そのため、今回の用途では`.vscode/extensions.json`方式を第一推奨とする。

---

## 8. 最終的な推奨構成

```text
rhdl-workshop-provision/
└── devfile.yaml

spring-to-quarkus-sample/
├── .vscode/
│   └── extensions.json
├── pom.xml
└── src/
```

`extensions.json`:

```json
{
  "recommendations": [
    "redhat.mta-vscode-extension",
    "redhat.java"
  ]
}
```

`devfile.yaml`では、WorkspaceのCPU、メモリ、Maven Volume、Gitリポジトリ、BuildやRunコマンドを管理する。

VS Code拡張の導入は、`.vscode/extensions.json`へ分離する。

---

## 9. 反映時の注意

既存Workspaceでは、`.vscode/extensions.json`を追加しても、直ちに期待どおり反映されない場合がある。

確実に確認するには、次のいずれかを行う。

1. Gitリポジトリを最新化する
2. Workspaceを停止して再起動する
3. 既存Workspaceを削除して再作成する

ワークショップの事前準備では、新規Workspace作成時に適用される状態を基準に検証するのが望ましい。

---

## 10. 結論

MTA VS Code拡張をDev SpacesのWorkspace起動時に自動インストールするには、次の構成が最もシンプルで保守しやすい。

1. アプリケーションリポジトリへ`.vscode/extensions.json`を配置する
2. `redhat.mta-vscode-extension`をrecommendationsへ追加する
3. Java拡張として`redhat.java`も追加する
4. devfile.yamlから拡張インストール用の独自commandを削除する
5. `oc login`やパスワードをdevfileへ埋め込まない
6. MTA利用を考慮してWorkspaceメモリを6〜8Gi程度確保する
7. Mavenの`.m2`をVolumeへ永続化する

この構成により、devfile.yamlはWorkspace環境の定義へ集中し、VS Code拡張の管理はプロジェクトリポジトリ側へ分離できる。
