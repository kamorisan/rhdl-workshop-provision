# Scripts Reorganization Plan

## Current Structure (14 scripts + 1 Python)

```
scripts/
├── add-mta-extension.sh                      # ❓ 廃止候補？
├── cleanup-gitops.sh                         # GitOps管理
├── create-devworkspaces.sh                   # Workspace作成（古い）
├── create-workspaces-from-devfile.sh         # Workspace作成（古い）
├── create-workspaces-via-api.sh              # Workspace作成（API経由）
├── create-workspaces-with-secrets.sh         # ✅ Workspace作成（推奨）
├── generate-user-list.sh                     # ユーザー管理
├── initial-setup.sh                          # セットアップ
├── replicate-workspaces-from-reference.sh    # Workspace複製（古い？）
├── replicate-workspaces.sh                   # Workspace複製（古い？）
├── replicate_workspaces.py                   # Workspace複製（Python版）
├── reset-gitops.sh                           # GitOps管理
├── setup-git.sh                              # Git設定
├── setup-user-secrets.sh                     # Secret管理
├── status-check.sh                           # ステータス確認
└── test/                                     # テストスクリプト
    ├── README.md
    ├── test-full.sh
    ├── test-quick-start.sh
    └── test-without-gitops.sh
```

## Proposed New Structure

```
scripts/
├── README.md                                 # 📚 使い方ガイド
│
├── setup/                                    # 🛠️ 初期セットアップ
│   ├── initial-setup.sh                      # 全体セットアップ
│   ├── setup-git.sh                          # Git設定
│   └── setup-user-secrets.sh                 # Secret配布
│
├── workspace/                                # 💼 Workspace管理
│   ├── create-workspaces-with-secrets.sh     # ✅ 推奨：Secret付きWorkspace作成
│   ├── create-workspaces-via-api.sh          # API経由作成
│   └── deprecated/                           # 廃止予定スクリプト
│       ├── create-devworkspaces.sh
│       ├── create-workspaces-from-devfile.sh
│       ├── replicate-workspaces.sh
│       ├── replicate-workspaces-from-reference.sh
│       └── replicate_workspaces.py
│
├── user/                                     # 👥 ユーザー管理
│   └── generate-user-list.sh
│
├── gitops/                                   # 🔄 GitOps操作
│   ├── cleanup-gitops.sh                     # クリーンアップ
│   └── reset-gitops.sh                       # リセット
│
├── ops/                                      # 🔍 運用・監視
│   └── status-check.sh                       # ステータス確認
│
└── test/                                     # 🧪 テスト
    ├── README.md
    ├── test-full.sh
    ├── test-quick-start.sh
    └── test-without-gitops.sh

```

## Migration Strategy

### Phase 1: Create new directories
```bash
mkdir -p scripts/{setup,workspace/deprecated,user,gitops,ops}
```

### Phase 2: Move files
```bash
# Setup scripts
mv initial-setup.sh setup/
mv setup-git.sh setup/
mv setup-user-secrets.sh setup/

# Active workspace scripts
mv create-workspaces-with-secrets.sh workspace/
mv create-workspaces-via-api.sh workspace/

# Deprecated workspace scripts
mv create-devworkspaces.sh workspace/deprecated/
mv create-workspaces-from-devfile.sh workspace/deprecated/
mv replicate-workspaces.sh workspace/deprecated/
mv replicate-workspaces-from-reference.sh workspace/deprecated/
mv replicate_workspaces.py workspace/deprecated/

# User management
mv generate-user-list.sh user/

# GitOps operations
mv cleanup-gitops.sh gitops/
mv reset-gitops.sh gitops/

# Operations
mv status-check.sh ops/
```

### Phase 3: Delete obsolete scripts
```bash
# Check if add-mta-extension.sh is still needed
rm add-mta-extension.sh  # 機能がdevfile.yamlに統合済みなら削除
```

### Phase 4: Create README.md with usage guide

## Questions to Answer

1. **add-mta-extension.sh** - まだ使用中？devfile.yamlで拡張機能は自動インストール済み
2. **replicate-* スクリプト群** - create-workspaces-with-secrets.sh に統合されたので廃止？
3. **Python版 replicate_workspaces.py** - 保持する必要あり？

## Recommended Main Entry Points (After Reorganization)

```bash
# 初期セットアップ
./scripts/setup/initial-setup.sh

# Workspace作成（推奨）
./scripts/workspace/create-workspaces-with-secrets.sh

# ステータス確認
./scripts/ops/status-check.sh

# テスト実行
./scripts/test/test-quick-start.sh
```
