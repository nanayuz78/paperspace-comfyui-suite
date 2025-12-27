FROM nvidia/cuda:12.4.1-cudnn-runtime-ubuntu22.04

LABEL maintainer="mochidroppot <mochidroppot@gmail.com>"

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

# Base packages
RUN set -eux; \
    apt-get update && \
    apt-get install -y --no-install-recommends \
      ca-certificates curl wget git nano vim zip unzip tzdata build-essential \
      libgl1-mesa-glx libglib2.0-0 openssh-client bzip2 pkg-config iproute2 tini ffmpeg supervisor && \
    rm -rf /var/lib/apt/lists/*

# micromamba installation
RUN set -eux; \
    mkdir -p ${MAMBA_ROOT_PREFIX}; \
    curl -fsSL https://micro.mamba.pm/api/micromamba/linux-64/latest | tar -xj -C /usr/local/bin --strip-components=1 bin/micromamba; \
    echo "export PATH=${MAMBA_ROOT_PREFIX}/bin:\$PATH" > /etc/profile.d/mamba.sh

# Python environment & core libraries
RUN set -eux; \
    micromamba create -y -p ${MAMBA_ROOT_PREFIX}/envs/pyenv python=${PYTHON_VERSION}; \
    micromamba run -p ${MAMBA_ROOT_PREFIX}/envs/pyenv pip install --no-cache-dir \
      --index-url https://download.pytorch.org/whl/cu124 \
      torch torchvision torchaudio && \
    micromamba run -p ${MAMBA_ROOT_PREFIX}/envs/pyenv pip install --no-cache-dir \
      jupyterlab==4.* notebook ipywidgets jupyterlab-git jupyter-server-proxy tensorboard \
      matplotlib seaborn pandas numpy scipy tqdm rich && \
    micromamba clean -afy

ENV PATH=${MAMBA_ROOT_PREFIX}/envs/pyenv/bin:${MAMBA_ROOT_PREFIX}/bin:${PATH}

# Application: ComfyUI
RUN set -eux; \
    git clone https://github.com/comfyanonymous/ComfyUI.git /opt/app/ComfyUI && \
    git clone https://github.com/Comfy-Org/ComfyUI-Manager.git /opt/app/ComfyUI/custom_nodes/ComfyUI-Manager && \
    git clone https://github.com/mochidroppot/ComfyUI-ProxyFix.git /opt/app/ComfyUI/custom_nodes/ComfyUI-ProxyFix && \
    micromamba run -p ${MAMBA_ROOT_PREFIX}/envs/pyenv pip install --no-cache-dir \
      -r /opt/app/ComfyUI/requirements.txt \
      -r /opt/app/ComfyUI/custom_nodes/ComfyUI-Manager/requirements.txt \
      -r /opt/app/ComfyUI/custom_nodes/ComfyUI-ProxyFix/requirements.txt

# JupyterLab Extensions (Build-time install)
RUN set -eux; \
    mkdir -p /opt/app/jlab_extensions; \
    curl -fsSL -o /opt/app/jlab_extensions/jupyterlab_comfyui_cockpit-0.1.0-py3-none-any.whl \
      https://github.com/mochidroppot/jupyterlab-comfyui-cockpit/releases/download/v0.1.0/jupyterlab_comfyui_cockpit-0.1.0-py3-none-any.whl && \
    micromamba run -p ${MAMBA_ROOT_PREFIX}/envs/pyenv pip install /opt/app/jlab_extensions/jupyterlab_comfyui_cockpit-0.1.0-py3-none-any.whl

# --- 追加: 自作パッケージ (paperspace-stable-diffusion-suite) のインストール ---
# ビルド時にファイルをコピーしてインストールすることで、ランチャーにアイコンが出るようになります
COPY pyproject.toml /tmp/suite/pyproject.toml
COPY src /tmp/suite/src
RUN micromamba run -p ${MAMBA_ROOT_PREFIX}/envs/pyenv pip install /tmp/suite && \
    rm -rf /tmp/suite

# User setup
RUN set -eux; \
    if id -u "${MAMBA_USER}" >/dev/null 2>&1; then \
        # ユーザーが既に存在する場合：ホームディレクトリの作成とシェルの設定のみ行う
        mkdir -p /home/${MAMBA_USER}; \
        usermod -d /home/${MAMBA_USER} -s /bin/bash "${MAMBA_USER}"; \
    else \
        # ユーザーが存在しない場合：新規作成
        useradd -m -s /bin/bash "${MAMBA_USER}"; \
    fi; \
    # 所有権の変更が必要なディレクトリをすべて作成
    mkdir -p /home/${MAMBA_USER} ${MAMBA_ROOT_PREFIX} /opt/app /workspace; \
    # 所有権の一括変更（-Rはサブディレクトリを含める）
    chown -R ${MAMBA_USER}:${MAMBA_USER} /home/${MAMBA_USER} ${MAMBA_ROOT_PREFIX} /opt/app /workspace

WORKDIR /workspace
COPY --chown=${MAMBA_USER}:${MAMBA_USER} scripts/entrypoint.sh /usr/local/bin/entrypoint.sh
COPY --chown=${MAMBA_USER}:${MAMBA_USER} config/supervisord.conf /etc/supervisord.conf
RUN chmod +x /usr/local/bin/entrypoint.sh

USER ${MAMBA_USER}
ENV CONDA_DEFAULT_ENV=pyenv
EXPOSE 8888

ENTRYPOINT ["/usr/bin/tini", "--", "/usr/local/bin/entrypoint.sh"]
