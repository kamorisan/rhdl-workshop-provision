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
   - 各ユーザーnamespace (`user01-devspaces` ~ `user10-devspaces`) に `che-code-spring-to-quarkus-workshop` テンプレートを作成
   - che-code IDE（VS Code互換）の定義を含む
   - リソース制限: CPU 1000m, Memory 2Gi

3. **DevWorkspace作成**
   - 10個の `spring-to-quarkus-workshop` ワークスペースを作成
   - dev-toolsコンテナ: CPU 1000m, Memory 6Gi
   - 合計リソース: CPU 2000m, Memory 8Gi (LimitRange内)

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
| `DEVFILE_URL` | `https://raw.githubusercontent.com/...` | devfile.yamlのURL |

例：
```bash
USER_COUNT=5 ./scripts/workspace/create-all-workspaces.sh
```

## 作成されるリソース

### DevWorkspaceTemplate (che-code-spring-to-quarkus-workshop)

各ユーザーnamespaceに1つずつ作成されます（合計10個）。

**コンポーネント**:
- `che-code-injector`: che-codeファイルをコピーするinitコンテナ
- `che-code-runtime`: IDE実行環境
  - Image: `registry.redhat.io/devspaces/udi-rhel9:latest`
  - CPU: 100m - 1000m
  - Memory: 512Mi - 2Gi
  - Endpoints: 3100 (main), 13131-13133 (redirects)

**イベント**:
- `preStart`: che-code-injectorを実行
- `postStart`: che-codeを起動 (`/checode/entrypoint-volume.sh`)

### DevWorkspace (spring-to-quarkus-workshop)

各ユーザーnamespaceに1つずつ作成されます（合計10個）。

**コンポーネント**:
- `dev-tools`: 開発環境
  - Image: `registry.redhat.io/devspaces/udi-rhel9:latest`
  - CPU: 500m - 1000m
  - Memory: 2Gi - 6Gi
  - Volume: m2 (10Gi), checode (ephemeral)

**Projects**:
- `spring-to-quarkus-sample`: https://github.com/kamorisan/spring-to-quarkus-sample

**Commands**:
- `oc-auto-login`: OpenShiftに自動ログイン
- `setup-mta-config`: MTA設定をコピー
- `maven-build`: ビルド
- `maven-test`: テスト
- `run-app`: アプリケーション実行

**Events**:
- `postStart`: `setup-mta-config` を実行

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
   oc get devworkspace spring-to-quarkus-workshop -n user01-devspaces -o yaml
   ```

### che-codeが起動しない

1. **che-code プロセス確認**
   ```bash
   POD=$(oc get pods -n user01-devspaces -o name | head -1)
   oc exec -n user01-devspaces ${POD##*/} -c dev-tools -- ps aux | grep node
   ```

2. **entrypoint-logs確認**
   ```bash
   oc exec -n user01-devspaces ${POD##*/} -c dev-tools -- cat /checode/entrypoint-logs.txt
   ```

3. **DevWorkspaceTemplate確認**
   ```bash
   oc get devworkspacetemplate che-code-spring-to-quarkus-workshop -n user01-devspaces -o yaml
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
oc get devworkspace --all-namespaces | grep spring-to-quarkus

# 全DevWorkspaceTemplate一覧
oc get devworkspacetemplate --all-namespaces | grep che-code-spring-to-quarkus

# 特定ユーザーのワークスペース起動テスト
oc patch devworkspace spring-to-quarkus-workshop -n user01-devspaces --type merge -p '{"spec":{"started":true}}'
oc get devworkspace spring-to-quarkus-workshop -n user01-devspaces
```

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
