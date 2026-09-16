# OpenShift Pipelines Operator Configuration

このディレクトリには、OpenShift Pipelines (Tekton) Operatorの設定が含まれています。

## ファイル構成

### subscription.yaml
OpenShift Pipelines Operatorのサブスクリプション定義。

- **Channel:** `latest`
- **Install Plan:** `Automatic`
- **Sync Wave:** `-70` (Operators phase)

### tektonconfig.yaml
Tekton Pipelinesのグローバル設定（TektonConfig CR）。

**重要な設定:**

#### 1. Affinity Assistant無効化
```yaml
pipeline:
  coschedule: disabled
```

**理由:**
- デフォルト設定（`coschedule: workspaces`）では、同じPVCを使用する複数のTaskを同じノードにスケジュールするために`affinity-assistant`というPodが作成される
- Workshop環境では以下の問題が発生する可能性がある:
  - affinity-assistant Pod自体の起動失敗
  - PVCのnode affinityとPodのaffinity要求の競合
  - 限られたworker nodeでのスケジューリング失敗

**影響:**
- 各TaskRunは独立してスケジュールされる
- RWO PVCの場合、Kubernetes自体がPod-to-Nodeの親和性を保証する
- より柔軟なスケジューリングが可能になる

#### 2. その他の設定

| 設定項目 | 値 | 説明 |
|---------|-----|------|
| `enable-api-fields` | `beta` | Beta機能を有効化 |
| `enable-custom-tasks` | `true` | カスタムTaskの利用を許可 |
| `enable-step-actions` | `true` | StepActionsの利用を許可 |
| `default-service-account` | `pipeline` | デフォルトのServiceAccount |
| `set-security-context` | `false` | OpenShift SCCとの互換性のため無効 |
| `running-in-environment-with-injected-sidecars` | `true` | Service Mesh等のsidecar環境での実行を想定 |

## GitOpsデプロイメント

このディレクトリは`workshop-operators` Applicationによって管理されています。

**Sync Wave順序:**
1. **Wave -70**: Subscription (Operatorインストール)
2. **Wave -60**: TektonConfig (Operator設定)

**変更の反映:**

1. ローカルで変更を加える
2. GitHubにpush
3. Argo CDが自動的にsync（3分以内）
4. TektonConfig変更後、Tekton Pipelines Controllerが自動的に再起動される

```bash
# 変更をpush
git add gitops/operators/pipelines/
git commit -m "Update TektonConfig: disable affinity assistant"
git push origin main

# Argo CD同期確認
oc get application workshop-operators -n openshift-gitops

# TektonConfig適用確認
oc get tektonconfig config -o yaml | grep coschedule

# 設定反映確認（feature-flags ConfigMap）
oc get cm feature-flags -n openshift-pipelines -o yaml | grep coschedule
```

## トラブルシューティング

### Issue 1: TektonConfigの変更が反映されない

**症状:**
```bash
oc get cm feature-flags -n openshift-pipelines -o yaml | grep coschedule
# coschedule: workspaces （変更されていない）
```

**対処法:**
```bash
# TektonConfig確認
oc get tektonconfig config -o yaml | grep coschedule

# Tekton Operator再起動
oc rollout restart deployment/openshift-pipelines-operator -n openshift-operators

# 5分待機してConfigMap再確認
sleep 300
oc get cm feature-flags -n openshift-pipelines -o yaml | grep coschedule
```

### Issue 2: Pipeline実行時にaffinity-assistantエラー

**症状:**
TaskRun Podが`Pending`状態で、以下のエラーが表示される:
```
node(s) didn't match pod affinity rules
```

**確認:**
```bash
# 現在のcoschedule設定確認
oc get cm feature-flags -n openshift-pipelines -o yaml | grep coschedule

# PipelineRun削除して再実行
oc delete pipelinerun <pipelinerun-name> -n <namespace>
```

**一時的な手動対応:**
```bash
# feature-flags ConfigMapを直接編集
oc patch cm feature-flags -n openshift-pipelines \
  --type merge -p '{"data":{"coschedule":"disabled"}}'

# Tekton Controller再起動
oc rollout restart deployment/tekton-pipelines-controller -n openshift-pipelines
```

## 参考資料

- [Tekton Pipelines Documentation](https://tekton.dev/docs/pipelines/)
- [OpenShift Pipelines Documentation](https://docs.openshift.com/pipelines/)
- [TektonConfig API Reference](https://tekton.dev/docs/operator/tektonconfig/)
- [Affinity Assistant Design](https://github.com/tektoncd/pipeline/blob/main/docs/affinity-assistant-and-podtemplates.md)

---

**作成日:** 2026-09-16  
**最終更新:** 2026-09-16
