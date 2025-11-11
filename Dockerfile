# ----------------------------------------------------------------------
# Base Image
# ----------------------------------------------------------------------
# Use the nvidia CUDA runtime base image for GPU passthrough support
FROM nvidia/cuda:13.0.1-runtime-ubuntu24.04

# Don't prompt for input during build
ARG DEBIAN_FRONTEND=noninteractive 

# ----------------------------------------------------------------------
# Software installation flags
# ----------------------------------------------------------------------
ARG WITH_KIRO
ARG WITH_AWS_CLI
ARG WITH_TOFU
ARG WITH_CURSOR
ARG WITH_VSCODE

# ----------------------------------------------------------------------
# URLs for external downloads
# ----------------------------------------------------------------------
ARG URL_KIRO="https://prod.download.desktop.kiro.dev/releases/202511032205--distro-linux-x64-deb/202511032205-distro-linux-x64.deb"
ARG URL_AWS_CLI="https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip"
ARG URL_SESSION_MANAGER="https://s3.amazonaws.com/session-manager-downloads/plugin/latest/ubuntu_64bit/session-manager-plugin.deb"
ARG URL_TOFU="https://get.opentofu.org/install-opentofu.sh"
ARG URL_VSCODE="https://vscode.download.prss.microsoft.com/dbazure/download/stable/7d842fb85a0275a4a8e4d7e040d2625abbf7f084/code_1.105.1-1760482543_amd64.deb"
ARG URL_CURSOR="https://downloads.cursor.com/production/63fcac100bd5d5749f2a98aa47d65f6eca61db39/linux/x64/deb/amd64/deb/cursor_2.0.69_amd64.deb"

# ----------------------------------------------------------------------
# Working directory
# ----------------------------------------------------------------------
WORKDIR /apps

# ----------------------------------------------------------------------
# Copy custom bash additions into /tmp
# ----------------------------------------------------------------------
COPY etc/bashrc-addition /tmp/

# ----------------------------------------------------------------------
# Base packages / X11 support / GUI app support
# ----------------------------------------------------------------------
RUN apt-get update && apt-get install -y \
    sudo \
    git \
    curl \
    pass \
    gnupg2 \
    net-tools \
    vim \
    nano \
    x11-apps \
    strace \
    libpulse0 \
    cinnamon \
    lxde \
    dbus \
    dbus-x11 \
    x11-utils \
    rsync \
    software-properties-common \
    firefox \
    libasound2t64 \
    libx11-6 \
    libxkbfile1 \
    libsecret-1-0 \
    libxss1 \
    libnss3 \
    libatk1.0-0

# ----------------------------------------------------------------------
# Optional software installs
# ----------------------------------------------------------------------
### Kiro ###
RUN if [ "${WITH_KIRO}" = "1" ]; then \
      curl -fsSL -o /tmp/kiro.deb ${URL_KIRO} && \
      dpkg -i /tmp/kiro.deb || apt-get install -f -y && \
      rm /tmp/kiro.deb && rm -rf /var/lib/apt/lists/*; \
    else \
      echo "Skipping Kiro installation"; \
    fi

### AWS CLI + Session Manager ###
RUN if [ "${WITH_AWS_CLI}" = "1" ]; then \
      cd /tmp && curl -fsSL ${URL_AWS_CLI} -o awscliv2.zip && unzip awscliv2.zip && ./aws/install && \
      curl -fsSL ${URL_SESSION_MANAGER} -o plugin.deb && dpkg -i plugin.deb; \
    fi

### OpenTofu ###
RUN if [ "${WITH_TOFU}" = "1" ]; then \
      cd /tmp && curl -fsSL ${URL_TOFU} -o install.sh && \
      chmod +x install.sh && ./install.sh --install-method deb && rm install.sh; \
    fi

### VSCode ###
RUN if [ "${WITH_VSCODE}" = "1" ]; then \
      cd /tmp && curl -fsSL ${URL_VSCODE} -o install.deb && \
      apt install ./install.deb && rm ./install.deb; \
    fi

### Cursor IDE ###
RUN if [ "${WITH_CURSOR}" = "1" ]; then \
      cd /tmp && curl -fsSL ${URL_CURSOR} -o install.deb && \
      apt install ./install.deb && rm ./install.deb; \
    fi

# ----------------------------------------------------------------------
# Install sane X11 fonts
# ----------------------------------------------------------------------
RUN cd /tmp && git clone https://github.com/powerline/fonts.git --depth=1 && cd fonts && ./install.sh

# ----------------------------------------------------------------------
# Chromium installation (non-Snap)
# ----------------------------------------------------------------------
RUN apt-get update && \
    apt-get install -y software-properties-common wget gnupg2 && \
    add-apt-repository -y ppa:xtradeb/apps && \
    apt-get update && \
    apt-get install -y chromium

# ----------------------------------------------------------------------
# Fix Chromium flags for Docker
# ----------------------------------------------------------------------
RUN if [ -f /bin/chromium ]; then \
      cp /bin/chromium /usr/bin/chromium.bak && \
      sed -i -E 's|^(CHROMIUM_FLAGS=.*)|CHROMIUM_FLAGS="--no-sandbox --disable-software-rasterizer --disable-dev-shm-usage"|g' /bin/chromium; \
    else \
      echo "Chromium not installed, skipping flag fix"; \
    fi

# ----------------------------------------------------------------------
# Append custom bash additions
# ----------------------------------------------------------------------
RUN cat /tmp/bashrc-addition >> /etc/bash.bashrc && rm /tmp/bashrc-addition

# ----------------------------------------------------------------------
# Provisioning script
# ----------------------------------------------------------------------
COPY ./usr/local/bin/runtime-prov.sh /usr/local/bin/runtime-prov.sh
RUN chmod +x /usr/local/bin/runtime-prov.sh

# ----------------------------------------------------------------------
# Prepare root home for default shell
# ----------------------------------------------------------------------
RUN mkdir -p /root/.config && mkdir -p /root/.local

# ----------------------------------------------------------------------
# Default CMD
# ----------------------------------------------------------------------
CMD ["/usr/local/bin/runtime-prov.sh"]
