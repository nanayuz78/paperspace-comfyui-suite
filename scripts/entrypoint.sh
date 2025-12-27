#!/usr/bin/env bash
set -euo pipefail

MAMBA_ROOT_PREFIX=/opt/conda
STORAGE_BASE_DIR="/storage/sd-suite"
STORAGE_COMFYUI_DIR="${STORAGE_BASE_DIR}/comfyui"
STORAGE_JLAB_DIR="${STORAGE_BASE_DIR}/jlab"
JLAB_EXTENSIONS_DIR="${STORAGE_JLAB_DIR}/extensions"
COMFYUI_APP_BASE="/opt/app/ComfyUI"
COMFYUI_CUSTOM_NODES_DIR="${STORAGE_COMFYUI_DIR}/custom_nodes"

mkdir -p "${STORAGE_COMFYUI_DIR}/input" \
 "${STORAGE_COMFYUI_DIR}/output" \
 "${STORAGE_COMFYUI_DIR}/custom_nodes" \
 "${STORAGE_COMFYUI_DIR}/user" \
 "${JLAB_EXTENSIONS_DIR}"

install_jlab_extensions() {
  micromamba run -p ${MAMBA_ROOT_PREFIX}/envs/pyenv pip install /opt/app/jlab_extensions/jupyterlab_comfyui_cockpit-0.1.0-py3-none-any.whl
  shopt -s nullglob
  local extensions=("$JLAB_EXTENSIONS_DIR"/*.whl)
  if [ ${#extensions[@]} -gt 0 ]; then
    micromamba run -p ${MAMBA_ROOT_PREFIX}/envs/pyenv pip install --no-cache-dir "${extensions[@]}"
  fi
  shopt -u nullglob
}

update_comfyui() {
  local auto="${COMFYUI_AUTO_UPDATE:-1}"
  if [ "$auto" = "0" ] || [ "$auto" = "false" ] || [ ! -d "${COMFYUI_APP_BASE}/.git" ]; then
    return 0
  fi
  (
    cd "${COMFYUI_APP_BASE}"
    git pull --ff-only origin master 2>/dev/null || git pull --ff-only origin main 2>/dev/null || true
    micromamba run -p ${MAMBA_ROOT_PREFIX}/envs/pyenv pip install -r /opt/app/ComfyUI/requirements.txt
  )
}

update_preinstalled_nodes() {
  local auto="${COMFYUI_CUSTOM_NODES_AUTO_UPDATE:-1}"
  if [ "$auto" = "0" ] || [ "$auto" = "false" ]; then return 0; fi
  local nodes=("ComfyUI-Manager" "ComfyUI-ProxyFix")
  for node in "${nodes[@]}"; do
    local node_path="${COMFYUI_CUSTOM_NODES_DIR}/${node}"
    if [ -d "$node_path/.git" ]; then
      (cd "$node_path" && git pull --ff-only origin master 2>/dev/null || git pull --ff-only origin main 2>/dev/null || true)
    fi
  done
}

install_custom_node_deps_every_start() {
  local auto="${COMFYUI_CUSTOM_NODES_AUTO_INSTALL_DEPS:-1}"
  if [ "$auto" = "0" ] || [ "$auto" = "false" ] || [ ! -d "${COMFYUI_CUSTOM_NODES_DIR}" ]; then return 0; fi
  shopt -s nullglob
  local reqs=("${COMFYUI_CUSTOM_NODES_DIR}"/*/requirements.txt)
  for req in "${reqs[@]}"; do
    (cd "$(dirname "$req")" && micromamba run -p ${MAMBA_ROOT_PREFIX}/envs/pyenv pip install --upgrade-strategy only-if-needed -r "requirements.txt" || true)
  done
  shopt -u nullglob
}

link_dir() {
  local src="$1"; local dst="$2";
  if [ -L "$src" ]; then return 0; fi
  if [ -d "$src" ] && [ -n "$(ls -A "$src" 2>/dev/null || true)" ]; then
    cp -an "$src"/. "$dst"/ 2>/dev/null || true
    rm -rf "$src"
  fi
  ln -sfn "$dst" "$src"
}

# インフラ準備 (Jupyter拡張のみ同期実行)
install_jlab_extensions

for d in input output custom_nodes user; do
  link_dir "${COMFYUI_APP_BASE}/${d}" "${STORAGE_COMFYUI_DIR}/${d}"
done

# 重い処理をバックグラウンドに逃がして、即座にJupyterを立ち上げる
(
  update_comfyui
  update_preinstalled_nodes
  install_custom_node_deps_every_start
) &

echo "Starting Supervisor (ComfyUI)..."
supervisord -c /etc/supervisord.conf

if [ "$#" -gt 0 ]; then
  exec micromamba run -p ${MAMBA_ROOT_PREFIX}/envs/pyenv "$@"
else
  exec micromamba run -p ${MAMBA_ROOT_PREFIX}/envs/pyenv \
    jupyter lab --ip=0.0.0.0 --port=8888 --no-browser --ServerApp.token= --ServerApp.password=
fi