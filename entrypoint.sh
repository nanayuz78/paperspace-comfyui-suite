#!/usr/bin/env bash
set -euo pipefail

MAMBA_ROOT_PREFIX=/opt/conda
NOTEBOOKS_WORKSPACE_BASE="/notebooks/workspace"
COMFYUI_APP_BASE="/opt/app/ComfyUI"
mkdir -p "${NOTEBOOKS_WORKSPACE_BASE}/input" "${NOTEBOOKS_WORKSPACE_BASE}/output" "${NOTEBOOKS_WORKSPACE_BASE}/custom_nodes" "${NOTEBOOKS_WORKSPACE_BASE}/user"

update_comfyui() {
  local auto="${COMFYUI_AUTO_UPDATE:-1}"
  if [ "$auto" = "0" ] || [ "$auto" = "false" ]; then
    return 0
  fi
  if [ ! -d "${COMFYUI_APP_BASE}/.git" ]; then
    return 0
  fi
  if ! command -v git >/dev/null 2>&1; then
    echo "WARN: git not available; skipping ComfyUI update" >&2
    return 0
  fi
  echo "Fixing ComfyUI to version v0.3.73 in ${COMFYUI_APP_BASE} ..."
  (
    cd "${COMFYUI_APP_BASE}"
    # 強制的にv0.3.73にチェックアウト
    git fetch --tags
    git checkout v0.3.73
    micromamba run -p ${MAMBA_ROOT_PREFIX}/envs/pyenv pip install -r /opt/app/ComfyUI/requirements.txt
  )
}

update_comfyui

update_preinstalled_nodes() {
  local auto="${COMFYUI_CUSTOM_NODES_AUTO_UPDATE:-1}"
  if [ "$auto" = "0" ] || [ "$auto" = "false" ]; then
    return 0
  fi
  
  local nodes=(
    "ComfyUI-Manager"
    "ComfyUI-ProxyFix"
  )
  
  for node in "${nodes[@]}"; do
    local node_path="${NOTEBOOKS_WORKSPACE_BASE}/custom_nodes/${node}"
    if [ -d "$node_path/.git" ]; then
      echo "Updating pre-installed custom node: $node ..."
      (
        cd "$node_path"
        
        local deps_marker=".deps_installed"
        local is_first_run=false
        if [ ! -f "$deps_marker" ]; then
          is_first_run=true
        fi
        
        local req_hash_before=""
        if [ -f "requirements.txt" ]; then
          req_hash_before=$(md5sum requirements.txt 2>/dev/null | cut -d' ' -f1)
        fi
        
        git pull --ff-only origin master 2>/dev/null || git pull --ff-only origin main 2>/dev/null || true
        
        local needs_install=false
        if [ -f "requirements.txt" ]; then
          local req_hash_after=$(md5sum requirements.txt 2>/dev/null | cut -d' ' -f1)
          if [ "$is_first_run" = true ]; then
            needs_install=true
            echo "  → First run, ensuring dependencies are installed..."
          elif [ "$req_hash_before" != "$req_hash_after" ]; then
            needs_install=true
            echo "  → requirements.txt changed, installing dependencies..."
          fi
        fi
        
        if [ "$needs_install" = true ]; then
          micromamba run -p ${MAMBA_ROOT_PREFIX}/envs/pyenv pip install --upgrade-strategy only-if-needed -r requirements.txt
          touch "$deps_marker"
        fi
      )
    fi
  done
}

link_dir() {
  local src="$1"; local dst="$2";
  if [ -L "$src" ]; then return 0; fi
  if [ -d "$src" ] && [ -n "$(ls -A "$src" 2>/dev/null || true)" ]; then
    echo "Migrating existing data from $src to $dst ..."
    mkdir -p "$dst"
    cp -an "$src"/. "$dst"/ 2>/dev/null || true
    rm -rf "$src"
  fi
  ln -sfn "$dst" "$src"
}

link_dir "${COMFYUI_APP_BASE}/input" "${NOTEBOOKS_WORKSPACE_BASE}/input"
link_dir "${COMFYUI_APP_BASE}/output" "${NOTEBOOKS_WORKSPACE_BASE}/output"
link_dir "${COMFYUI_APP_BASE}/custom_nodes" "${NOTEBOOKS_WORKSPACE_BASE}/custom_nodes"
link_dir "${COMFYUI_APP_BASE}/user" "${NOTEBOOKS_WORKSPACE_BASE}/user"

update_preinstalled_nodes

echo "Starting ComfyUI service..."
cd "${COMFYUI_APP_BASE}"
nohup python main.py --listen 127.0.0.1 --port 8189 > /tmp/comfyui.log 2>&1 &
COMFYUI_PID=$!
cd /notebooks
echo "ComfyUI started with PID: $COMFYUI_PID (port 8189)"

if [ "$#" -gt 0 ]; then
  exec "$@"
else
  exec jupyter lab --ip=0.0.0.0 --port=8888 --no-browser --ServerApp.token= --ServerApp.password=
fi
