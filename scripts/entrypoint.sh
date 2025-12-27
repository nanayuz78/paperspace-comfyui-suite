#!/usr/bin/env bash
set -euo pipefail

STORAGE_BASE_DIR="/storage/sd-suite"
STORAGE_COMFYUI_DIR="${STORAGE_BASE_DIR}/comfyui"
COMFYUI_APP_BASE="/opt/app/ComfyUI"

# 1. 永続ストレージのディレクトリ作成
mkdir -p "${STORAGE_COMFYUI_DIR}/input" "${STORAGE_COMFYUI_DIR}/output" \
         "${STORAGE_COMFYUI_DIR}/custom_nodes" "${STORAGE_COMFYUI_DIR}/user"

# 2. シンボリックリンクの作成 (高速)
link_dir() {
    local src="$1"; local dst="$2";
    if [ -L "$src" ]; then return 0; fi
    if [ -d "$src" ] && [ -n "$(ls -A "$src" 2>/dev/null || true)" ]; then
        cp -an "$src"/. "$dst"/ 2>/dev/null || true
        rm -rf "$src"
    fi
    ln -sfn "$dst" "$src"
}

for d in input output custom_nodes user; do
    link_dir "${COMFYUI_APP_BASE}/${d}" "${STORAGE_COMFYUI_DIR}/${d}"
done

# 3. バックグラウンドでのセットアップ処理 (& を使用)
# Paperspaceに「起動成功」をすぐ伝えるため、これらは裏で走らせます
(
    echo "[Background] Starting updates and dependency checks..."
    
    # ComfyUI本体の更新 (オプション)
    if [ "${COMFYUI_AUTO_UPDATE:-1}" = "1" ]; then
        cd "${COMFYUI_APP_BASE}" && git pull --ff-only origin master 2>/dev/null || true
    fi

    # 既存カスタムノードの依存関係インストール
    shopt -s nullglob
    local reqs=("${STORAGE_COMFYUI_DIR}/custom_nodes"/*/requirements.txt)
    for req in "${reqs[@]}"; do
        echo "[Background] Installing deps for: $(basename "$(dirname "$req")")"
        pip install --upgrade-strategy only-if-needed -r "$req" || true
    done
    
    echo "[Background] All background tasks completed."
) &

# 4. Supervisorの起動 (フォアグラウンド)
echo "Starting Supervisor..."
exec supervisord -c /etc/supervisord.conf