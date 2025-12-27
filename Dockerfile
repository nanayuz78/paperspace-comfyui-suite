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

RUN set -eux; \
    codename="$(. /etc/os-release && echo "$VERSION_CODENAME")"; \
    { \
      echo "deb https://archive.ubuntu.com/ubuntu ${codename} main universe multiverse restricted"; \
      echo "deb https://archive.ubuntu.com/ubuntu ${codename}-updates main universe multiverse restricted"; \
      echo "deb https://security.ubuntu.com/ubuntu ${codename}-security main universe multiverse restricted"; \
    } > /etc/apt/sources.list; \
    apt-get -o Acquire::Retries=5 -o Acquire::http::Timeout="30" update && \
    apt-get -o Acquire::Retries=5 -o Acquire::http::Timeout="30" install -y --no-install-recommends \
      ca-certificates curl wget git nano vim zip unzip tzdata build-essential \
      libgl1-mesa-glx libglib2.0-0 openssh-client bzip2 pkg-config iproute2 tini ffmpeg && \
    rm -rf /var/lib/apt/lists/*

RUN set -eux; \
    mkdir -p ${MAMBA_ROOT_PREFIX}; \
    curl -fsSL -o /tmp/micromamba.tar.bz2 "https://micro.mamba.pm/api/micromamba/linux-64/latest"; \
    if tar -tjf /tmp/micromamba.tar.bz2 | grep -q '^bin/micromamba$'; then \
      tar -xjf /tmp/micromamba.tar.bz2 -C /usr/local/bin --strip-components=1 bin/micromamba; \
    else \
      curl -fsSL -o /tmp/install_micromamba.sh https://micro.mamba.pm/install.sh; \
      bash /tmp/install_micromamba.sh -b -p ${MAMBA_ROOT_PREFIX}; \
      ln -sf ${MAMBA_ROOT_PREFIX}/bin/micromamba /usr/local/bin/micromamba; \
    fi; \
    echo "export PATH=${MAMBA_ROOT_PREFIX}/bin:\$PATH" > /etc/profile.d/mamba.sh

RUN set -eux; \
    micromamba create -y -p ${MAMBA_ROOT_PREFIX}/envs/pyenv python=${PYTHON_VERSION}; \
    micromamba run -p ${MAMBA_ROOT_PREFIX}/envs/pyenv python -m pip install --upgrade pip && \
    micromamba clean -a -y

ENV PATH=${MAMBA_ROOT_PREFIX}/envs/pyenv/bin:${MAMBA_ROOT_PREFIX}/bin:${PATH}

RUN set -eux; \
    git clone https://github.com/comfyanonymous/ComfyUI.git /opt/app/ComfyUI && \
    mkdir -p /opt/app/ComfyUI/custom_nodes && \
    git clone https://github.com/Comfy-Org/ComfyUI-Manager.git /opt/app/ComfyUI/custom_nodes/ComfyUI-Manager && \
    git clone https://github.com/mochidroppot/ComfyUI-ProxyFix.git /opt/app/ComfyUI/custom_nodes/ComfyUI-ProxyFix && \
    git config --global --add safe.directory /opt/app/ComfyUI

RUN set -eux; \
    export PIP_NO_CACHE_DIR=0; \
    micromamba run -p ${MAMBA_ROOT_PREFIX}/envs/pyenv pip install --index-url https://download.pytorch.org/whl/cu124 torch torchvision torchaudio && \
    micromamba run -p ${MAMBA_ROOT_PREFIX}/envs/pyenv pip install --prefer-binary --upgrade-strategy only-if-needed \
      jupyterlab==4.* notebook ipywidgets jupyterlab-git jupyter-server-proxy tensorboard \
      matplotlib seaborn pandas numpy scipy tqdm rich supervisor && \
    if [ -f /opt/app/ComfyUI/requirements.txt ]; then \
      micromamba run -p ${MAMBA_ROOT_PREFIX}/envs/pyenv pip install -r /opt/app/ComfyUI/requirements.txt; \
    fi; \
    if [ -f /opt/app/ComfyUI/custom_nodes/ComfyUI-Manager/requirements.txt ]; then \
      micromamba run -p ${MAMBA_ROOT_PREFIX}/envs/pyenv pip install -r /opt/app/ComfyUI/custom_nodes/ComfyUI-Manager/requirements.txt; \
    fi; \
    if [ -f /opt/app/ComfyUI/custom_nodes/ComfyUI-ProxyFix/requirements.txt ]; then \
      micromamba run -p ${MAMBA_ROOT_PREFIX}/envs/pyenv pip install -r /opt/app/ComfyUI/custom_nodes/ComfyUI-ProxyFix/requirements.txt; \
    fi; \
    micromamba clean -a -y

RUN set -eux; \
    mkdir -p /opt/app/jlab_extensions && \
    curl -fsSL -o /opt/app/jlab_extensions/jupyterlab_comfyui_cockpit-0.1.0-py3-none-any.whl https://github.com/mochidroppot/jupyterlab-comfyui-cockpit/releases/download/v0.1.0/jupyterlab_comfyui_cockpit-0.1.0-py3-none-any.whl

RUN set -eux; \
    useradd -m -s /bin/bash ${MAMBA_USER}; \
    chown -R ${MAMBA_USER}:${MAMBA_USER} /home/${MAMBA_USER}; \
    chown -R ${MAMBA_USER}:${MAMBA_USER} ${MAMBA_ROOT_PREFIX}; \
    chown -R ${MAMBA_USER}:${MAMBA_USER} /opt/app

USER ${MAMBA_USER}
RUN git config --global --add safe.directory /opt/app/ComfyUI

USER root
RUN mkdir -p /workspace /workspace/data /workspace/notebooks

USER ${MAMBA_USER}
ENV PATH=${MAMBA_ROOT_PREFIX}/envs/pyenv/bin:${MAMBA_ROOT_PREFIX}/bin:${PATH}
ENV CONDA_DEFAULT_ENV=pyenv

USER root
WORKDIR /notebooks

COPY scripts/entrypoint.sh /usr/local/bin/entrypoint.sh
COPY config/supervisord.conf /etc/supervisord.conf
RUN chmod +x /usr/local/bin/entrypoint.sh && chown ${MAMBA_USER}:${MAMBA_USER} /usr/local/bin/entrypoint.sh

COPY pyproject.toml /tmp/paperspace-stable-diffusion-suite/pyproject.toml
COPY src /tmp/paperspace-stable-diffusion-suite/src
RUN micromamba run -p ${MAMBA_ROOT_PREFIX}/envs/pyenv pip install /tmp/paperspace-stable-diffusion-suite && \
    rm -rf /tmp/paperspace-stable-diffusion-suite

EXPOSE 8888
ENTRYPOINT ["/usr/bin/tini", "--", "/usr/local/bin/entrypoint.sh"]
USER ${MAMBA_USER}

CMD ["jupyter", "lab", "--ip=0.0.0.0", "--port=8888", "--no-browser", "--ServerApp.token=", "--ServerApp.password="]