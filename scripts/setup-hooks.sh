#!/usr/bin/env bash
# 安装 Git 钩子：把 core.hooksPath 指向仓库内的 .githooks
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

if [ ! -d .git ]; then
  echo "错误: 当前目录不是 Git 仓库，先执行 git init" >&2
  exit 1
fi

git config core.hooksPath .githooks
chmod +x .githooks/* 2>/dev/null || true
chmod +x scripts/*.sh 2>/dev/null || true

echo "已启用钩子目录: .githooks"
git config --get core.hooksPath
