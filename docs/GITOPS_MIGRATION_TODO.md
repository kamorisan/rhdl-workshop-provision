# DevSpaces Workspace GitOps Migration TODO

## 現状

**ワークスペース作成は現在スクリプトベース（GitOps未対応）**

### 現在のスクリプト構成

```
scripts/workspace/
├── setup-all-workspaces.sh          # メインスクリプト（全体オーケストレーション）
├── setup-user-permissions.sh        # ユーザー権限設定（view/edit role付与）
├── setup-che-code-templates.sh      # DevWorkspaceTemplate作成（各user*-devspaces namespaceに）
├── create-all-workspaces.sh         # DevWorkspace作成（10ユーザー分）
└── devworkspace-template.yaml       # DevWorkspaceのYAMLテンプレート
```

### 現在作成されるリソース

1. **DevWorkspaceTemplate** (`che-code-spring-to-quarkus-workshop`)
   - 各ユーザーnamespace (user01-devspaces ~ user10-devspaces) に個別作成
   - che-code IDEをdev-toolsコンテナに統合
   - postStartイベントで `/checode/entrypoint-volume.sh` を起動
   - エンドポイント: 3100 (main), 13131-13133 (redirects)

2. **DevWorkspace** (`spring-to-quarkus-workshop`)
   - 各ユーザーnamespaceに1つずつ（10個）
   - `spec.contributions` で同namespace内のDevWorkspaceTemplateを参照
   - `spec.template` に devfile内容を展開（projects, components, commands, events）
   - 重要: **`-devspaces` namespaceに作成**（UIから見えるようにするため）

3. **User Permissions** (RoleBinding)
   - view/edit role を各ユーザーに付与
   - 対象namespace: `user*-dev`, `user*-devspaces`, `openshift-devspaces`

## なぜGitOps移行が必要か

**ユーザーの原則**: 「手動確認は再現性がないので、スクリプトで通せるように開発して」

現在の問題点:
1. **宣言的状態なし** - スクリプト実行結果がGitに記録されない
2. **Argo CD追跡なし** - ワークスペースがArgo CD管理下にない
3. **冪等性が保証されていない** - 再実行時の動作がスクリプトのロジックに依存
4. **ドリフト検出不可** - 手動変更を検出できない
5. **GitOpsの原則違反** - インフラの真実の情報源がGitにない

## 移行計画

### Phase 1: Helmテンプレート作成

`gitops/workshop/devspaces/` ディレクトリ構成:

```
gitops/workshop/devspaces/
├── Chart.yaml
├── values.yaml
└── templates/
    ├── devworkspace-template.yaml    # DevWorkspaceTemplate (10個)
    ├── devworkspace.yaml              # DevWorkspace (10個)
    └── rolebinding.yaml               # User permissions
```

#### templates/devworkspace-template.yaml

```yaml
{{- range $i := untilStep 1 (add1 .Values.workshop.userCount | int) 1 }}
{{- $id := printf "%02d" $i }}
{{- $username := printf "%s%s" $.Values.workshop.usernamePrefix $id }}
{{- $namespace := printf "%s-devspaces" $username }}
---
apiVersion: workspace.devfile.io/v1alpha2
kind: DevWorkspaceTemplate
metadata:
  name: che-code-spring-to-quarkus-workshop
  namespace: {{ $namespace }}
  annotations:
    argocd.argoproj.io/sync-wave: "20"
  labels:
    app.kubernetes.io/managed-by: openshift-gitops
    app.kubernetes.io/part-of: developer-lightspeed-workshop
    workshop.user: {{ $username }}
spec:
  commands:
    - id: init-container-command
      apply:
        component: che-code-injector
  components:
    - name: che-code-injector
      container:
        image: registry.redhat.io/devspaces/code-rhel8:latest
        command:
          - /entrypoint-init-container.sh
        volumeMounts:
          - name: checode
            path: /checode
    - name: che-code-runtime
      attributes:
        app.kubernetes.io/component: che-code-runtime
        app.kubernetes.io/part-of: che-code.eclipse.org
        controller.devfile.io/container-contribution: true
      container:
        image: registry.redhat.io/devspaces/udi-rhel9:latest
        cpuRequest: 100m
        cpuLimit: 1000m
        memoryRequest: 512Mi
        memoryLimit: 2Gi
        sourceMapping: /projects
        volumeMounts:
          - name: checode
            path: /checode
        endpoints:
          - name: che-code
            attributes:
              type: main
              cookiesAuthEnabled: true
              discoverable: false
              urlRewriteSupported: true
            targetPort: 3100
            exposure: public
            protocol: https
            secure: true
          - name: code-redirect-1
            targetPort: 13131
            exposure: public
            protocol: https
          - name: code-redirect-2
            targetPort: 13132
            exposure: public
            protocol: https
          - name: code-redirect-3
            targetPort: 13133
            exposure: public
            protocol: https
    - name: checode
      volume:
        ephemeral: true
  events:
    preStart:
      - init-container-command
{{- end }}
```

#### templates/devworkspace.yaml

```yaml
{{- range $i := untilStep 1 (add1 .Values.workshop.userCount | int) 1 }}
{{- $id := printf "%02d" $i }}
{{- $username := printf "%s%s" $.Values.workshop.usernamePrefix $id }}
{{- $namespace := printf "%s-devspaces" $username }}
---
apiVersion: workspace.devfile.io/v1alpha2
kind: DevWorkspace
metadata:
  name: spring-to-quarkus-workshop
  namespace: {{ $namespace }}
  annotations:
    argocd.argoproj.io/sync-wave: "30"
  labels:
    app.kubernetes.io/managed-by: openshift-gitops
    app.kubernetes.io/part-of: developer-lightspeed-workshop
    workshop.user: {{ $username }}
    workshop.type: developer-lightspeed
spec:
  started: false
  routingClass: che
  contributions:
    - name: editor
      kubernetes:
        name: che-code-spring-to-quarkus-workshop
  template:
    attributes:
      controller.devfile.io/storage-type: per-workspace
      controller.devfile.io/scc: container-build
    projects:
      - name: spring-to-quarkus-sample
        git:
          remotes:
            origin: https://github.com/kamorisan/spring-to-quarkus-sample
          checkoutFrom:
            revision: main
    components:
      - name: dev-tools
        container:
          image: registry.redhat.io/devspaces/udi-rhel9:latest
          memoryRequest: 2Gi
          memoryLimit: 8Gi
          cpuRequest: 500m
          cpuLimit: 2000m
          mountSources: true
          sourceMapping: /projects
          volumeMounts:
            - name: m2
              path: /home/user/.m2
            - name: checode
              path: /checode
          env:
            - name: MAVEN_OPTS
              value: "-Xmx2g"
          endpoints:
            - name: che-code
              attributes:
                type: main
                cookiesAuthEnabled: true
                discoverable: false
                urlRewriteSupported: true
              targetPort: 3100
              exposure: public
              protocol: https
              secure: true
            - name: code-redirect-1
              targetPort: 13131
              exposure: public
              protocol: https
            - name: code-redirect-2
              targetPort: 13132
              exposure: public
              protocol: https
            - name: code-redirect-3
              targetPort: 13133
              exposure: public
              protocol: https
      - name: m2
        volume:
          size: 10Gi
      - name: checode
        volume:
          ephemeral: true
    commands:
      - id: start-che-code
        exec:
          component: dev-tools
          commandLine: |
            nohup /checode/entrypoint-volume.sh > /checode/entrypoint-logs.txt 2>&1 &
          label: "Start Che-Code IDE"
          group:
            kind: run
            isDefault: false
      - id: oc-auto-login
        exec:
          component: dev-tools
          commandLine: |
            #!/bin/bash
            USERNAME=$(echo "${DEVWORKSPACE_NAMESPACE}" | sed 's/-devspaces$//')
            OCP_API=$(oc whoami --show-server 2>/dev/null || echo "https://kubernetes.default.svc")
            if oc login --insecure-skip-tls-verify=true "$OCP_API" -u "$USERNAME" -p "openshift" >/dev/null 2>&1; then
              echo "✅ Logged in as $USERNAME"
            else
              echo "⚠️ Auto-login skipped"
            fi
            exit 0
          workingDir: ${PROJECT_SOURCE}
          label: "Auto-login to OpenShift"
          group:
            kind: run
            isDefault: false
      - id: setup-mta-config
        exec:
          component: dev-tools
          commandLine: |
            SETTINGS_DIR="/checode/remote/data/User/globalStorage/redhat.mta-core/settings"
            SOURCE_FILE="/projects/spring-to-quarkus-sample/.devspaces/provider-settings.yaml"
            mkdir -p "$SETTINGS_DIR"
            sleep 10
            if [ -f "$SOURCE_FILE" ]; then
              cp -f "$SOURCE_FILE" "$SETTINGS_DIR/provider-settings.yaml"
              echo "✅ MTA provider settings configured from project"
            else
              echo "⚠️ Source file not found"
            fi
            exit 0
          workingDir: /projects
          label: "Setup MTA Configuration"
          group:
            kind: run
            isDefault: false
      - id: maven-build
        exec:
          component: dev-tools
          commandLine: mvn clean package -DskipTests
          workingDir: ${PROJECT_SOURCE}/spring-to-quarkus-sample
          label: "Build"
          group:
            kind: build
            isDefault: true
      - id: maven-test
        exec:
          component: dev-tools
          commandLine: mvn test
          workingDir: ${PROJECT_SOURCE}/spring-to-quarkus-sample
          label: "Test"
          group:
            kind: test
      - id: run-app
        exec:
          component: dev-tools
          commandLine: mvn spring-boot:run
          workingDir: ${PROJECT_SOURCE}/spring-to-quarkus-sample
          label: "Run Application"
          group:
            kind: run
            isDefault: true
    events:
      postStart:
        - start-che-code
        - setup-mta-config
{{- end }}
```

#### templates/rolebinding.yaml

```yaml
{{- range $i := untilStep 1 (add1 .Values.workshop.userCount | int) 1 }}
{{- $username := printf "%s%02d" $.Values.workshop.usernamePrefix $i }}
{{- range $ns := list (printf "%s-dev" $username) (printf "%s-devspaces" $username) }}
---
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: {{ $username }}-view
  namespace: {{ $ns }}
  annotations:
    argocd.argoproj.io/sync-wave: "15"
  labels:
    app.kubernetes.io/managed-by: openshift-gitops
    app.kubernetes.io/part-of: developer-lightspeed-workshop
    workshop.user: {{ $username }}
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: view
subjects:
- apiGroup: rbac.authorization.k8s.io
  kind: User
  name: {{ $username }}
---
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: {{ $username }}-edit
  namespace: {{ $ns }}
  annotations:
    argocd.argoproj.io/sync-wave: "15"
  labels:
    app.kubernetes.io/managed-by: openshift-gitops
    app.kubernetes.io/part-of: developer-lightspeed-workshop
    workshop.user: {{ $username }}
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: edit
subjects:
- apiGroup: rbac.authorization.k8s.io
  kind: User
  name: {{ $username }}
{{- end }}
{{- end }}
```

### Phase 2: Argo CD Application作成

**gitops/argocd/workshop-devspaces.yaml**:

```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: workshop-devspaces
  namespace: openshift-gitops
  labels:
    app.kubernetes.io/part-of: developer-lightspeed-workshop
spec:
  project: default
  source:
    repoURL: https://github.com/kamorisan/rhdl-workshop-provision
    targetRevision: main
    path: gitops/workshop/devspaces
    helm:
      valueFiles:
        - values.yaml
  destination:
    server: https://kubernetes.default.svc
  syncPolicy:
    automated:
      prune: false  # ワークスペースを自動削除しない
      selfHeal: true
    syncOptions:
      - CreateNamespace=false  # workshop/namespaces appが作成済み
```

### Phase 3: Root Applicationに追加

`gitops/argocd/root-application.yaml` に追加:

```yaml
---
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: workshop-devspaces
  namespace: openshift-gitops
  finalizers:
    - resources-finalizer.argocd.argoproj.io
spec:
  source:
    path: gitops/argocd
    repoURL: https://github.com/kamorisan/rhdl-workshop-provision
    targetRevision: main
  destination:
    namespace: openshift-gitops
    server: https://kubernetes.default.svc
  project: default
```

### Phase 4: スクリプトの扱い

**維持するスクリプト** (Ansibleから初回のみ実行):
- なし（全てGitOpsへ）

**非推奨としてマーク** (先頭にWarning追加):
```bash
echo "⚠️  WARNING: This script is deprecated."
echo "    Use GitOps instead: gitops/workshop/devspaces"
echo "    This script will be removed in future versions."
echo ""
read -p "Continue anyway? (y/N): " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    exit 1
fi
```

対象:
- `setup-che-code-templates.sh`
- `create-all-workspaces.sh`
- `setup-all-workspaces.sh`
- `setup-user-permissions.sh` (RoleBindingもGitOps化)

## 移行手順

1. **Helmテンプレート作成**
   ```bash
   mkdir -p gitops/workshop/devspaces/templates
   # 上記テンプレートファイルを作成
   ```

2. **ローカルでテスト**
   ```bash
   cd gitops/workshop/devspaces
   helm template . --debug
   ```

3. **Argo CD Application作成**
   ```bash
   oc apply -f gitops/argocd/workshop-devspaces.yaml
   ```

4. **初回同期**
   ```bash
   # Argo CD UIまたはCLIで同期
   argocd app sync workshop-devspaces
   ```

5. **検証**
   ```bash
   # 10ユーザー全てのワークスペース確認
   oc get devworkspace --all-namespaces | grep spring-to-quarkus
   
   # Argo CD管理下にあることを確認
   argocd app get workshop-devspaces
   ```

6. **スクリプト非推奨化**
   - 各スクリプトにWarning追加
   - README更新

7. **ドキュメント更新**
   - デプロイ手順をGitOpsベースに書き換え
   - スクリプトの説明を削除

## 注意事項

### Sync Wave順序
```
0:  Namespaces (workshop/namespaces)
15: RoleBindings (user permissions)
20: DevWorkspaceTemplates (IDE definition)
30: DevWorkspaces (actual workspaces)
```

### Prune設定
- `prune: false` - ワークスペースを誤って削除しないため
- ユーザーが作業中のワークスペースを保護

### namespace指定の重要性
- DevWorkspaceは**必ず`-devspaces` namespace**に作成
- `-dev` namespaceではUIから見えない

## 関連ファイル

現在のスクリプト:
- `/Users/kamori/vscode/developer-lightspeed/workshop-provisioning/scripts/workspace/*`

現在の設定:
- `devfile.yaml` - ワークスペース定義
- `spring-to-quarkus-sample/.devspaces/provider-settings.yaml` - LLM設定

GitOps構成:
- `gitops/workshop/namespaces/` - Namespace作成（既存）
- `gitops/workshop/resources/` - ResourceQuota, ConfigMap, Secret（既存）
- `gitops/workshop/devspaces/` - **未作成（移行先）**

## 参考

- Camel Workshop実装: `/Users/kamori/vscode/camel_workshop/camelk-ws/provision/openshift/02_devspaces/`
- DevWorkspace API: https://github.com/devfile/api
- Argo CD Sync Waves: https://argo-cd.readthedocs.io/en/stable/user-guide/sync-waves/
