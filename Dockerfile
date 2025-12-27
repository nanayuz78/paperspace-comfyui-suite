# ----------------------------------------------------------------------------
# Image for Paperspace Notebook (GPU) running JupyterLab
# ----------------------------------------------------------------------------
FROM nvidia/cuda:12.4.1-cudnn-runtime-ubuntu22.04

LABEL maintainer="nanayuz78"

ARG PYTHON_VERSION=3.11
ARG MAMBA_USER=mambauser
ENV MAMBA_USER=${MAMBA_USER} \
    DEBIAN_FRONTEND=noninteractive \
    TZ=Etc/UTC \
    SHELL=/bin/bash \
    PIP_NO_CACHE_DIR=1 \
    PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    NVIDIA_VISIBLE_DEVICES=all \
    NVIDIA_DRIVER_CAPABILITIES=compute,utility \
    MAMBA_ROOT_PREFIX=/opt/conda

# --- 1. システムパッケージ (Root) ---
RUN set -eux; \
    apt-get update && \
    apt-get install -y --no-install-recommends \
      ca-certificates curl wget git nano vim zip unzip tzdata build-essential \
      libgl1-mesa-glx libglib2.0-0 openssh-client bzip2 pkg-config iproute2 tini ffmpeg supervisor && \
    rm -rf /var/lib/apt/lists/*

# --- 2. ユーザー作成とディレクトリ準備 (Root) ---
# 先にユーザーを作り、ディレクトリの権限を渡しておく（容量パンク回避の鍵）
RUN set -eux; \
    useradd -m -s /bin/bash ${MAMBA_USER}; \
    mkdir -p ${MAMBA_ROOT_PREFIX} /opt/app /workspace; \
    chown -R ${MAMBA_USER}:${MAMBA_USER} ${MAMBA_ROOT_PREFIX} /opt/app /workspace

# --- 3. 以降、mambauser で実行 ---
USER ${MAMBA_USER}
WORKDIR /opt/app

# micromamba のインストール (公式の単純なバイナリ配置)
RUN set -eux; \
    curl -fsSL https://micro.mamba.pm/api/micromamba/linux-64/latest | tar -xj -C /tmp bin/micromamba; \
    mv /tmp/bin/micromamba ${MAMBA_ROOT_PREFIX}/micromamba; \
    chmod +x ${MAMBA_ROOT_PREFIX}/micromamba

# パスの設定
ENV PATH=${MAMBA_ROOT_PREFIX}/envs/pyenv/bin:${MAMBA_ROOT_PREFIX}:${PATH}

# Python環境作成
RUN set -eux; \
    ${MAMBA_ROOT_PREFIX}/micromamba create -y -p ${MAMBA_ROOT_PREFIX}/envs/pyenv python=${PYTHON_VERSION} && \
    ${MAMBA_ROOT_PREFIX}/micromamba clean -afy

# ComfyUIのクローン (--depth 1 で容量削減)
RUN set -eux; \
    git clone --depth 1 https://github.com/comfyanonymous/ComfyUI.git /opt/app/ComfyUI && \
    mkdir -p /opt/app/ComfyUI/custom_nodes && \
    git clone --depth 1 https://github.com/Comfy-Org/ComfyUI-Manager.git /opt/app/ComfyUI/custom_nodes/ComfyUI-Manager && \
    git clone --depth 1 https://github.com/mochidroppot/ComfyUI-ProxyFix.git /opt/app/ComfyUI/custom_nodes/ComfyUI-ProxyFix && \
    find /opt/app -name ".git" -type d -exec rm -rf {} +

# PyTorch と 依存関係のインストール
RUN set -eux; \
    pip install --no-cache-dir --index-url https://download.pytorch.org/whl/cu124 torch torchvision torchaudio && \
    pip install --no-cache-dir \
      jupyterlab==4.* notebook ipywidgets jupyterlab-git jupyter-server-proxy tensorboard \
      matplotlib seaborn pandas numpy scipy tqdm rich supervisor && \
    if [ -f /opt/app/ComfyUI/requirements.txt ]; then \
      pip install --no-cache-dir -r /opt/app/ComfyUI/requirements.txt; \
    fi; \
    if [ -f /opt/app/ComfyUI/custom_nodes/ComfyUI-Manager/requirements.txt ]; then \
      pip install --no-cache-dir -r /opt/app/ComfyUI/custom_nodes/ComfyUI-Manager/requirements.txt; \
    fi; \
    if [ -f /opt/app/ComfyUI/custom_nodes/ComfyUI-ProxyFix/requirements.txt ]; then \
      pip install --no-cache-dir -r /opt/app/ComfyUI/custom_nodes/ComfyUI-ProxyFix/requirements.txt; \
    fi; \
    ${MAMBA_ROOT_PREFIX}/micromamba clean -afy

# Jupyter拡張の準備
RUN set -eux; \
    mkdir -p /opt/app/jlab_extensions && \
    curl -fsSL -o /opt/app/jlab_extensions/jupyterlab_comfyui_cockpit-0.1.0-py3-none-any.whl https://github.com/mochidroppot/jupyterlab-comfyui-cockpit/releases/download/v0.1.0/jupyterlab_comfyui_cockpit-0.1.0-py3-none-any.whl

# 自作パッケージのインストール (pyproject.toml 関連)
COPY --chown=${MAMBA_USER}:${MAMBA_USER} pyproject.toml /tmp/suite/pyproject.toml
COPY --chown=${MAMBA_USER}:${MAMBA_USER} src /tmp/suite/src
RUN pip install /tmp/suite && rm -rf /tmp/suite

# 設定ファイルのコピー (Root権限が必要な箇所のみ一旦Rootへ)
USER root
COPY --chown=${MAMBA_USER}:${MAMBA_USER} scripts/entrypoint.sh /usr/local/bin/entrypoint.sh
COPY --chown=${MAMBA_USER}:${MAMBA_USER} config/supervisord.conf /etc/supervisord.conf
RUN chmod +x /usr/local/bin/entrypoint.sh

USER ${MAMBA_USER}
WORKDIR /workspace
ENV CONDA_DEFAULT_ENV=pyenv
EXPOSE 8888

ENTRYPOINT ["/usr/bin/tini", "--", "/usr/local/bin/entrypoint.sh"]

CMD ["jupyter", "lab", "--ip=0.0.0.0", "--port=8888", "--no-browser", "--ServerApp.token=", "--ServerApp.password="]
