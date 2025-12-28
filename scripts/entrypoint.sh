#!/usr/bin/env bash
set -euo pipefail

MAMBA_ROOT_PREFIX=/opt/conda
STORAGE_BASE_DIR="/storage/sd-suite"
STORAGE_COMFYUI_DIR="${STORAGE_BASE_DIR}/comfyui"
STORAGE_JLAB_DIR="${STORAGE_BASE_DIR}/jlab"
JLAB_EXTENSIONS_DIR="${STORAGE_JLAB_DIR}/extensions"
COMFYUI_APP_BASE="/opt/app/ComfyUI"
COMFYUI_CUSTOM_NODES_DIR="${STORAGE_COMFYUI_DIR}/custom_nodes"

# --- 1. ディレクトリ準備 (即時実行) ---
mkdir -p "${STORAGE_COMFYUI_DIR}/input" \
 "${STORAGE_COMFYUI_DIR}/output" \
 "${STORAGE_COMFYUI_DIR}/custom_nodes" \
 "${STORAGE_COMFYUI_DIR}/user" \
 "${JLAB_EXTENSIONS_DIR}"

link_dir() {
  local src="$1"; local dst="$2";
  if [ -L "$src" ]; then return 0; fi
  if [ -d "$src" ] && [ -n "$(ls -A "$src" 2>/dev/null || true)" ]; then
    echo "Migrating $src to $dst..."
    mkdir -p "$dst"
    cp -an "$src"/. "$dst"/ 2>/dev/null || true
    rm -rf "$src"
  fi
  ln -sfn "$dst" "$src"
}

for d in input output custom_nodes user; do
  link_dir "${COMFYUI_APP_BASE}/${d}" "${STORAGE_COMFYUI_DIR}/${d}"
done

# --- 2. 非同期処理 (バックグラウンド実行) ---
(
  echo "--- Start Background Setup ---" | tee /tmp/setup_async.log

  # JupyterLab Extension install
  micromamba run -p ${MAMBA_ROOT_PREFIX}/envs/pyenv pip install --no-cache-dir /opt/app/jlab_extensions/*.whl >> /tmp/setup_async.log 2>&1 || true

  # ComfyUI Update
  if [ "${COMFYUI_AUTO_UPDATE:-1}" != "0" ]; then
    echo "Updating ComfyUI..." >> /tmp/setup_async.log
    (
      cd "${COMFYUI_APP_BASE}"
      git pull --ff-only origin master 2>/dev/null || git pull --ff-only origin main 2>/dev/null || true
      micromamba run -p ${MAMBA_ROOT_PREFIX}/envs/pyenv pip install -r requirements.txt >> /tmp/setup_async.log 2>&1
    )
  fi

  # Custom Nodes Deps Update
  if [ "${COMFYUI_CUSTOM_NODES_AUTO_INSTALL_DEPS:-1}" != "0" ]; then
    echo "Updating Custom Node Deps..." >> /tmp/setup_async.log
    shopt -s nullglob
    for req in "${COMFYUI_CUSTOM_NODES_DIR}"/*/requirements.txt; do
      micromamba run -p ${MAMBA_ROOT_PREFIX}/envs/pyenv pip install --upgrade-strategy only-if-needed -r "$req" >> /tmp/setup_async.log 2>&1 || true
    done
    shopt -u nullglob
  fi

  # 最後にComfyUIを再起動してライブラリを反映
  echo "Restarting ComfyUI to apply changes..." >> /tmp/setup_async.log
  supervisorctl -c /etc/supervisord.conf restart comfyui || true

  echo "--- Background Setup Finished ---" >> /tmp/setup_async.log
) &

# --- 3. プロセス実行 ---
echo "Starting Supervisor..."
supervisord -c /etc/supervisord.conf

echo "Launching JupyterLab..."
if [ "$#" -gt 0 ]; then
  exec micromamba run -p ${MAMBA_ROOT_PREFIX}/envs/pyenv "$@"
else
  exec micromamba run -p ${MAMBA_ROOT_PREFIX}/envs/pyenv \
    jupyter lab --ip=0.0.0.0 --port=8888 --no-browser --ServerApp.token= --ServerApp.password=
fi