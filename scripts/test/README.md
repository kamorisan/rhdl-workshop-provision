# テスト用スクリプト

このディレクトリには、開発・検証用のテストスクリプトが含まれています。

## 📝 注意事項

- すべてのテストスクリプトは `ansible/inventory/test/hosts.yml` を使用します
- テスト用設定は2ユーザー、Solution Server無効がデフォルトです
- 本番環境では使用しないでください

## 🧪 テストスクリプト

### test-full.sh ⭐ 推奨
GitOps機能を含む完全なテスト

**使用方法**:
```bash
./scripts/test/test-full.sh
```

**前提条件**:
- GitHubにpush済み
- `gitops_repo_url` が正しく設定されている

**所要時間**: 20-30分

---

### test-quick-start.sh
対話的なクイックテスト（test-full.shとほぼ同じ）

**使用方法**:
```bash
./scripts/test/test-quick-start.sh
```

---

### test-without-gitops.sh
GitOps無しの最小限テスト

**使用方法**:
```bash
./scripts/test/test-without-gitops.sh
```

**テスト範囲**: Preflight + ユーザー作成のみ

**所要時間**: 5分

---

## 🎯 推奨テストフロー

```bash
# 1. Git初期設定（初回のみ）
cd /path/to/workshop-provisioning
./scripts/setup-git.sh

# 2. テスト設定確認
vim ansible/inventory/test/hosts.yml
# gitops_repo_url, cluster_api_url, llm設定を確認

# 3. フルテスト実行
./scripts/test/test-full.sh

# 4. ステータス確認
./scripts/status-check.sh

# 5. クリーンアップ
./scripts/cleanup-gitops.sh all
```

---

## ⚙️ テスト設定

テスト用の設定ファイル: `ansible/inventory/test/hosts.yml`

デフォルト設定:
- ユーザー数: 2
- Solution Server: 無効
- Operator Channels: stable (Dev Spaces), stable-v8.1 (MTA)
- Workspace Resources: CPU 2000m, Memory 8Gi

設定変更例:
```bash
# ユーザー数変更
ansible-playbook ansible/playbooks/bootstrap.yml \
  -i ansible/inventory/test/hosts.yml \
  -e workshop_user_count=5

# Solution Server有効化（LLM API Key必要）
ansible-playbook ansible/playbooks/bootstrap.yml \
  -i ansible/inventory/test/hosts.yml \
  -e solution_server_enabled=true \
  --ask-vault-pass
```

---

## 🔍 テスト結果確認

### ステータス確認
```bash
./scripts/status-check.sh
```

### ユーザー資格情報
```bash
cat artifacts/workshop-users.csv
./scripts/generate-user-list.sh html
```

### GitOps Applications
```bash
oc get applications -n openshift-gitops
```

### ユーザーNamespace
```bash
oc get namespaces | grep user0
```

### Workspace
```bash
oc get devworkspace -A
```

---

## 🧹 テスト後のクリーンアップ

### 推奨: 完全削除
```bash
export CLEANUP_ROOT=true
./scripts/cleanup-gitops.sh all
```

### ユーザーのみ削除
```bash
./scripts/cleanup-gitops.sh users
```

---

## 📊 テスト比較

| テスト | GitOps | Operators | Platform | Users | 所要時間 |
|--------|--------|-----------|---------|-------|---------|
| test-full.sh | ✓ | ✓ | ✓ | ✓ | 20-30分 |
| test-quick-start.sh | ✓ | ✓ | ✓ | ✓ | 20-30分 |
| test-without-gitops.sh | ✗ | ✗ | ✗ | ✓ | 5分 |

---

## 💡 Tips

### 複数回テストする場合
```bash
# 1回目のテスト
./scripts/test/test-full.sh

# クリーンアップ
./scripts/cleanup-gitops.sh all

# 2回目のテスト
./scripts/test/test-full.sh
```

### Git無しでクイックテスト
```bash
# GitHubにpushできない場合
./scripts/test/test-without-gitops.sh
```

### 監視しながらテスト
```bash
# ターミナル1: テスト実行
./scripts/test/test-full.sh

# ターミナル2: Applications監視
watch -n 5 'oc get applications -n openshift-gitops'

# ターミナル3: Pod監視
watch -n 5 'oc get pods -A | grep -E "gitops|devspaces|mta|user0"'
```

---

## 🆘 トラブルシューティング

### テストが失敗する場合

1. **Preflight失敗**
   ```bash
   # クラスター接続確認
   oc whoami
   oc auth can-i '*' '*' --all-namespaces
   ```

2. **GitOps同期エラー**
   ```bash
   # リポジトリURL確認
   vim ansible/inventory/test/hosts.yml
   # gitops_repo_url が正しいか確認
   ```

3. **Operator失敗**
   ```bash
   # Operator状態確認
   oc get csv -A
   oc get subscription -A
   ```

4. **ログ確認**
   ```bash
   ls -lt artifacts/*.log | head -1
   tail -f artifacts/<latest-log>
   ```

---

## 📚 関連ドキュメント

- [../README.md](../README.md) - 本番用スクリプト
- [../../docs/TROUBLESHOOTING.md](../../docs/TROUBLESHOOTING.md) - トラブルシューティング
- [../../TEST_RUN.md](../../TEST_RUN.md) - 詳細テスト手順
