#!/usr/bin/env bash
set -euo pipefail

MAMBA_ROOT_PREFIX=/opt/conda
STORAGE_BASE_DIR="/storage/sd-suite"
STORAGE_COMFYUI_DIR="${STORAGE_BASE_DIR}/comfyui"
STORAGE_JLAB_DIR="${STORAGE_BASE_DIR}/jlab"
JLAB_EXTENSIONS_DIR="${STORAGE_JLAB_DIR}/extensions"
STORAGE_SYSTEM_BASE="${STORAGE_BASE_DIR}/system"
COMFYUI_APP_BASE="/opt/app/ComfyUI"
COMFYUI_CUSTOM_NODES_DIR="${STORAGE_COMFYUI_DIR}/custom_nodes"

# Create directories (sudo を追加して権限エラーを回避)
sudo mkdir -p "${STORAGE_COMFYUI_DIR}/input" \
 "${STORAGE_COMFYUI_DIR}/output" \
 "${STORAGE_COMFYUI_DIR}/custom_nodes" \
 "${STORAGE_COMFYUI_DIR}/user" \
 "${JLAB_EXTENSIONS_DIR}" || true
sudo chown -R $(whoami):$(whoami) /storage || true

# Install JupyterLab extensions
install_jlab_extensions() {
  micromamba run -p ${MAMBA_ROOT_PREFIX}/envs/pyenv pip install /opt/app/jlab_extensions/jupyterlab_comfyui_cockpit-0.1.0-py3-none-any.whl

  shopt -s nullglob
  local extensions=("$JLAB_EXTENSIONS_DIR"/*.whl)
  if [ ${#extensions[@]} -gt 0 ]; then
    echo "Installing JupyterLab extensions: ${extensions[@]}"
    micromamba run -p ${MAMBA_ROOT_PREFIX}/envs/pyenv pip install --no-cache-dir "${extensions[@]}"
  else
    echo "No JupyterLab extensions found in ${JLAB_EXTENSIONS_DIR}"
  fi
  shopt -u nullglob
}

install_jlab_extensions

# link_dir function (Original logic)
link_dir() {
  local src="$1"; local dst="$2";
  if [ -L "$src" ]; then return 0; fi
  if [ -d "$src" ] && [ -n "$(ls -A "$src" 2>/dev/null || true)" ]; then
    echo "Migrating existing data from $src to $dst ..."
    mkdir -p "$dst"
    # -n: do not overwrite existing files (no-clobber)
    cp -an "$src"/. "$dst"/ 2>/dev/null || true
    rm -rf "$src"
  fi
  ln -sfn "$dst" "$src"
}

for d in input output custom_nodes user; do
  link_dir "${COMFYUI_APP_BASE}/${d}" "${STORAGE_COMFYUI_DIR}/${d}"
done

echo "Starting Supervisor (Jupyter and Background Setup)..."
# Start supervisord in daemon mode (configured in supervisord.conf)
exec supervisord -c /etc/supervisord.conf