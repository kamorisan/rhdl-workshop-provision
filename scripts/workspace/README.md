# DevWorkspace Creation Scripts

このディレクトリには、OpenShift Dev Spaces ワークスペースを自動作成するスクリプトが含まれています。

**重要**: 現在はスクリプトベースでワークスペースを作成していますが、将来的にGitOps化する予定です。詳細は [../../docs/GITOPS_MIGRATION_TODO.md](../../docs/GITOPS_MIGRATION_TODO.md) を参照してください。

## ファイル構成

### 実行スクリプト

| ファイル | 説明 |
|---------|------|
| `setup-all-workspaces.sh` | **メインスクリプト** - 以下の3ステップを順次実行 |
| `setup-user-permissions.sh` | Step 1: ユーザー権限設定（view/edit role付与） |
| `setup-che-code-templates.sh` | Step 2: DevWorkspaceTemplate作成（che-code IDE定義） |
| `create-all-workspaces.sh` | Step 3: DevWorkspace作成（10ユーザー分） |

### テンプレート

| ファイル | 説明 |
|---------|------|
| `devworkspace-template.yaml` | DevWorkspaceのYAMLテンプレート（sed置換用） |

### その他

| ディレクトリ/ファイル | 説明 |
|---------|------|
| `deprecated/` | 古いスクリプト（非推奨、削除予定） |

## 使い方

### 全ワークスペースの作成

```bash
cd /path/to/workshop-provisioning
./scripts/workspace/setup-all-workspaces.sh
```

このスクリプトは以下を実行します：

1. **ユーザー権限設定**
   - user01-10 に view/edit role を付与
   - 対象namespace: `user*-dev`, `user*-devspaces`, `openshift-devspaces`

2. **DevWorkspaceTemplate作成**
   - 各ユーザーnamespace (`user01-devspaces` ~ `user10-devspaces`) に `che-code-coolstore-modernization-workshop` テンプレートを作成
   - che-code IDE（VS Code互換）の定義を含む
   - VS Code拡張機能を自動インストール:
     - Migration Toolkit for Applications (MTA) Core
     - Language Support for Java
     - XML Language Support
   - リソース制限: CPU 1000m, Memory 2Gi

3. **DevWorkspace作成**
   - 10個の `coolstore-modernization-workshop` ワークスペースを作成
   - 各ユーザーのGiteaリポジトリ (`http://gitea-http.gitea.svc.cluster.local:3000/userXX/coolstore-eap7`) を自動クローン
   - dev-toolsコンテナ: CPU 500m-1000m, Memory 2Gi-6Gi
   - 合計リソース: CPU ~2000m, Memory ~8Gi (LimitRange内)

### 個別ステップの再実行

必要に応じて、各ステップを個別に実行できます：

```bash
# ユーザー権限のみ再設定
./scripts/workspace/setup-user-permissions.sh

# DevWorkspaceTemplateのみ再作成
./scripts/workspace/setup-che-code-templates.sh

# DevWorkspaceのみ再作成
./scripts/workspace/create-all-workspaces.sh
```

## 環境変数

スクリプトは以下の環境変数をサポートしています（デフォルト値あり）：

| 変数 | デフォルト | 説明 |
|------|-----------|------|
| `USER_COUNT` | `10` | ユーザー数 |
| `USERNAME_PREFIX` | `user` | ユーザー名プレフィックス |
| `NAMESPACE_SUFFIX` | `-devspaces` | namespace接尾辞 |

例：
```bash
USER_COUNT=5 ./scripts/workspace/create-all-workspaces.sh
```

## 作成されるリソース

### DevWorkspaceTemplate (che-code-coolstore-modernization-workshop)

各ユーザーnamespaceに1つずつ作成されます（合計10個）。

**コンポーネント**:
- `che-code-injector`: che-codeファイルをコピーするinitコンテナ
- `che-code-runtime`: IDE実行環境
  - Image: `registry.redhat.io/devspaces/udi-rhel9:latest`
  - CPU: 100m - 1000m
  - Memory: 512Mi - 2Gi
  - Endpoints: 3100 (main), 13131-13133 (redirects)
  - VS Code Extensions:
    - `redhat.mta-core` (1.5.0)
    - `redhat.vscode-java` (1.33.0)
    - `redhat.vscode-xml` (0.27.0)

**イベント**:
- `preStart`: che-code-injectorを実行
- `postStart`: che-codeを起動 (`/checode/entrypoint-volume.sh`)

### DevWorkspace (coolstore-modernization-workshop)

各ユーザーnamespaceに1つずつ作成されます（合計10個）。

**Contributions**:
- `editor`: カスタムDevWorkspaceTemplate (`che-code-coolstore-modernization-workshop`) を参照
  - che-code IDE本体とVS Code拡張機能を自動注入

**コンポーネント**:
- `dev-tools`: 開発環境
  - Image: `registry.redhat.io/devspaces/udi-rhel9:latest`
  - CPU: 500m - 1000m
  - Memory: 2Gi - 6Gi
  - Volume: m2 (10Gi - Maven local repository)

**Projects**:
- `coolstore-eap7`: 各ユーザーのGiteaリポジトリ
  - URL: `http://gitea-http.gitea.svc.cluster.local:3000/userXX/coolstore-eap7`
  - 認証: ユーザー名とパスワードをURL埋め込み
  - Branch: `main`

**Commands**:
- `oc-auto-login`: OpenShiftに自動ログイン
- `setup-mta-config`: MTA設定をコピー
- `maven-build`: ビルド
- `maven-test`: テスト
- `run-app`: アプリケーション実行

**Events**:
- `postStart`: 
  1. `setup-mta-config` - MTA provider設定を配置
  2. `oc-auto-login` - OpenShiftへ自動ログイン

## アーキテクチャ

### che-code エディター注入の仕組み

DevWorkspaceは、カスタムDevWorkspaceTemplateを`spec.contributions`から参照することで、che-code（VS Code互換IDE）を注入します。

```yaml
spec:
  contributions:
    - name: editor
      kubernetes:
        name: che-code-coolstore-modernization-workshop
```

このContributionにより、以下が自動的に実行されます：

1. **preStart**: `che-code-injector` が `/checode` ディレクトリへエディターファイルを配置
2. **postStart**: `/checode/entrypoint-volume.sh` がche-codeサーバーを起動
3. **Extensions**: Open VSX Registryから指定のVS Code拡張機能をダウンロード・インストール
4. **Endpoints**: Port 3100でche-codeを公開、DevWorkspace Routingが外部URLを生成

### Gitリポジトリクローンの仕組み

DevWorkspace Operatorは、`spec.template.projects`で指定されたGitリポジトリを自動クローンします。

```yaml
projects:
  - name: coolstore-eap7
    git:
      remotes:
        origin: http://user02:openshift@gitea-http.gitea.svc.cluster.local:3000/user02/coolstore-eap7
      checkoutFrom:
        revision: main
```

**重要**: 
- 内部Service名 (`gitea-http.gitea.svc.cluster.local`) を使用
- 認証情報をURL埋め込み形式で指定
- Pod起動時に `/projects/coolstore-eap7` へ自動クローン

### ターミナルの動作

DevWorkspaceで開いたワークスペースでは、以下のターミナル操作が可能です：

| 操作 | 動作 | コンテナ |
|-----|------|---------|
| `Terminal` → `New Terminal` | デフォルトbashターミナル | `dev-tools` |
| `Terminal` → `New Terminal (Select a Container)` | コンテナ選択UI | 任意 |
| Explorer → 右クリック → `Open in Integrated Terminal` | 選択ディレクトリでターミナルを開く | `dev-tools` |

**実装の仕組み**:
- カスタムDevWorkspaceTemplateの`che-code-runtime`コンポーネントが、`dev-tools`コンテナへche-code関連プロセスを注入
- `ptyHost`プロセスが`dev-tools`コンテナ内で稼働
- VS Code標準の`New Terminal`が`dev-tools`コンテナのbashを起動

## トラブルシューティング

### ワークスペースが起動しない

1. **LimitRange確認**
   ```bash
   oc get limitrange workshop-limits -n user01-devspaces -o yaml
   ```
   Container max: CPU 2000m, Memory 8Gi である必要があります

2. **Pod状態確認**
   ```bash
   oc get pods -n user01-devspaces
   oc describe pod <pod-name> -n user01-devspaces
   ```

3. **DevWorkspace状態確認**
   ```bash
   oc get devworkspace coolstore-modernization-workshop -n user01-devspaces -o yaml
   ```

### che-codeが起動しない

1. **che-code プロセス確認**
   ```bash
   POD=$(oc get pods -n user01-devspaces -l controller.devfile.io/devworkspace_name=coolstore-modernization-workshop -o jsonpath='{.items[0].metadata.name}')
   oc exec -n user01-devspaces $POD -c dev-tools -- ps aux | grep node
   ```

2. **entrypoint-logs確認**
   ```bash
   oc exec -n user01-devspaces $POD -c dev-tools -- cat /checode/entrypoint-logs.txt
   ```

3. **Port 3100確認**
   ```bash
   oc exec -n user01-devspaces $POD -c dev-tools -- ps aux | grep 3100
   ```
   
   期待される出力:
   ```
   /checode/checode-linux-libc/ubi9/node out/server-main.js --host 127.0.0.1 --port 3100
   ```

4. **DevWorkspaceTemplate確認**
   ```bash
   oc get devworkspacetemplate che-code-coolstore-modernization-workshop -n user01-devspaces -o yaml
   ```

### Gitリポジトリがクローンされない

1. **クローンエラーログ確認**
   ```bash
   oc exec -n user01-devspaces $POD -c dev-tools -- cat /projects/project-clone-errors.log
   ```

2. **Gitea Service確認**
   ```bash
   oc get svc -n gitea gitea-http
   ```
   
   Service名が `gitea-http` であることを確認

3. **DNS解決確認**
   ```bash
   oc exec -n user01-devspaces $POD -c dev-tools -- nslookup gitea-http.gitea.svc.cluster.local
   ```

4. **Gitea認証確認**
   ```bash
   oc exec -n user01-devspaces $POD -c dev-tools -- curl -u user01:openshift http://gitea-http.gitea.svc.cluster.local:3000/user01/coolstore-eap7
   ```

### VS Code拡張機能がインストールされない

1. **Extension Host確認**
   ```bash
   oc exec -n user01-devspaces $POD -c dev-tools -- ps aux | grep extensionHost
   ```

2. **拡張機能ログディレクトリ確認**
   ```bash
   oc exec -n user01-devspaces $POD -c dev-tools -- ls -la /checode/remote/data/logs/*/exthost*/
   ```
   
   期待されるディレクトリ:
   - `redhat.mta-core/`
   - `redhat.mta-java/`
   - `redhat.vscode-java/`
   - `redhat.vscode-xml/`

3. **DevWorkspaceTemplateの拡張機能定義確認**
   ```bash
   oc get devworkspacetemplate che-code-coolstore-modernization-workshop -n user01-devspaces \
     -o jsonpath='{.spec.components[1].attributes.che-code\.eclipse\.org/vscode-extensions}' | jq .
   ```

### ターミナルが開かない

1. **ptyHostプロセス確認**
   ```bash
   oc exec -n user01-devspaces $POD -c dev-tools -- ps aux | grep ptyHost
   ```
   
   期待される出力:
   ```
   /checode/checode-linux-libc/ubi9/node .../bootstrap-fork --type=ptyHost
   ```

2. **ptyhost.log確認**
   ```bash
   oc exec -n user01-devspaces $POD -c dev-tools -- sh -c 'ls -la /checode/remote/data/logs/*/ptyhost.log'
   ```

3. **bash確認**
   ```bash
   oc exec -n user01-devspaces $POD -c dev-tools -- which bash
   oc exec -n user01-devspaces $POD -c dev-tools -- bash --version
   ```

### ユーザーがワークスペースを見られない

1. **権限確認**
   ```bash
   oc get rolebinding -n user01-devspaces | grep user01
   ```

2. **正しいnamespaceにログイン**
   - Dev Spaces UIには**user01-devspaces** namespaceのワークスペースが表示されます
   - user01-dev namespaceではありません

## 検証

全ワークスペースが正常に作成されたか確認：

```bash
# 全DevWorkspace一覧
oc get devworkspace --all-namespaces | grep coolstore-modernization

# 全DevWorkspaceTemplate一覧
oc get devworkspacetemplate --all-namespaces | grep che-code-coolstore

# 特定ユーザーのワークスペース起動テスト
oc patch devworkspace coolstore-modernization-workshop -n user01-devspaces --type merge -p '{"spec":{"started":true}}'
oc get devworkspace coolstore-modernization-workshop -n user01-devspaces

# ブラウザアクセス用URL取得
oc get devworkspace coolstore-modernization-workshop -n user01-devspaces -o jsonpath='{.status.mainUrl}'
```

### 完全な動作確認

1. **ブラウザでWorkspaceを開く**
   - Dev Spaces Dashboard → user01 → coolstore-modernization-workshop → Open

2. **che-code起動確認**
   - VS Code互換画面が表示される
   - Extensions viewでMTA、Java、XMLがインストール済み

3. **Git Clone確認**
   - Explorer → `/projects/coolstore-eap7` が存在
   - `.devspaces/`, `s2i/`, `src/` などが見える

4. **ターミナル確認**
   ```bash
   # 標準ターミナル
   Terminal → New Terminal
   
   # 以下を実行
   pwd            # /projects/coolstore-eap7
   whoami         # user
   oc whoami      # user01
   oc project -q  # user01-dev
   mvn --version  # Maven 3.x
   java --version # Java 17
   ```

5. **MTA Extension確認**
   - Output → Migration Toolkit for Applications を選択
   - MTA Coreログが表示される（分析実行後）

## GitOps移行計画

現在のスクリプトベースの実装は、将来的にGitOpsに移行する予定です。

移行時の対応：
1. `gitops/workshop/devspaces/` にHelmテンプレートを作成
2. Argo CD Applicationを作成
3. このディレクトリのスクリプトを非推奨化

詳細は [../../docs/GITOPS_MIGRATION_TODO.md](../../docs/GITOPS_MIGRATION_TODO.md) を参照してください。

## 関連ドキュメント

- [GitOps Migration TODO](../../docs/GITOPS_MIGRATION_TODO.md) - GitOps化の詳細手順
- [Main README](../../README.md) - プロジェクト全体のドキュメント
- [DevWorkspace API](https://github.com/devfile/api) - DevWorkspace CRD仕様
- [Red Hat OpenShift Dev Spaces Documentation](https://docs.redhat.com/en/documentation/red_hat_openshift_dev_spaces) - 公式ドキュメント
