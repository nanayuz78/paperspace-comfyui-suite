#!/usr/bin/env bash
# 重い処理をバックグラウンドで行うためのスクリプト

MAMBA_ROOT_PREFIX=/opt/conda
COMFYUI_APP_BASE="/opt/app/ComfyUI"
STORAGE_COMFYUI_DIR="/storage/sd-suite/comfyui"
COMFYUI_CUSTOM_NODES_DIR="${STORAGE_COMFYUI_DIR}/custom_nodes"

# Diagnostics: print versions
echo "=== Jupyter diagnostics (pyenv) ==="
micromamba run -p ${MAMBA_ROOT_PREFIX}/envs/pyenv python -V || true
micromamba run -p ${MAMBA_ROOT_PREFIX}/envs/pyenv jupyter lab --version || true
echo "=== end diagnostics ==="

# update_comfyui (Original logic moved here)
update_comfyui() {
  local auto="${COMFYUI_AUTO_UPDATE:-1}"
  if [ "$auto" = "0" ] || [ "$auto" = "false" ]; then return 0; fi
  if [ ! -d "${COMFYUI_APP_BASE}/.git" ]; then return 0; fi
  echo "Updating ComfyUI in ${COMFYUI_APP_BASE} ..."
  (
    cd "${COMFYUI_APP_BASE}"
    git pull --ff-only origin master 2>/dev/null || git pull --ff-only origin main 2>/dev/null || true
    micromamba run -p ${MAMBA_ROOT_PREFIX}/envs/pyenv pip install -r /opt/app/ComfyUI/requirements.txt
  )
}

# install_custom_node_deps_every_start (Original logic moved here)
install_custom_node_deps_every_start() {
  local auto="${COMFYUI_CUSTOM_NODES_AUTO_INSTALL_DEPS:-1}"
  if [ "$auto" = "0" ] || [ "$auto" = "false" ]; then return 0; fi
  if [ ! -d "${COMFYUI_CUSTOM_NODES_DIR}" ]; then return 0; fi

  echo "Ensuring Python deps for custom nodes..."
  shopt -s nullglob
  local reqs=("${COMFYUI_CUSTOM_NODES_DIR}"/*/requirements.txt)
  for req in "${reqs[@]}"; do
    node_dir="$(dirname "$req")"
    echo "  → Installing deps for: $(basename "$node_dir")"
    micromamba run -p ${MAMBA_ROOT_PREFIX}/envs/pyenv pip install --upgrade-strategy only-if-needed -r "$req" || true
  done
  shopt -u nullglob
}

update_comfyui
install_custom_node_deps_every_start
echo "Background setup finished."