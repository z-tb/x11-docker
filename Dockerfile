# ----------------------------------------------------------------------
# Base Image
#
# This creates a Docker image based on Ubuntu 24.04 with NVIDIA CUDA
# runtime support and optional installations of Kiro, AWS CLI, OpenTofu,
# VSCode, and Cursor. It also includes X11 support for GUI applications.
# This is achieved by mounting the X11 socket from the host into the container
# at runtime, along with runtime user provisioning via an entrypoint script.
#
# ----------------------------------------------------------------------
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
ARG WITH_CLAUDE
ARG WITH_BREW
ARG WITH_SPACECTL

# ----------------------------------------------------------------------
# URLs for external downloads
# ----------------------------------------------------------------------
# current version can be retrieved this way: $ curl -s https://prod.download.desktop.kiro.dev/stable/metadata-linux-x64-deb-stable.json | jq -r .currentRelease
# ARG URL_KIRO="https://prod.download.desktop.kiro.dev/releases/stable/linux-x64/signed/0.9.2/deb/kiro-ide-0.9.2-stable-linux-x64.deb"
ARG URL_AWS_CLI="https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip"
ARG URL_SESSION_MANAGER="https://s3.amazonaws.com/session-manager-downloads/plugin/latest/ubuntu_64bit/session-manager-plugin.deb"
ARG URL_TOFU="https://get.opentofu.org/install-opentofu.sh"
#ARG URL_VSCODE="https://code.visualstudio.com/sha/download?build=stable&os=linux-deb-x64"
ARG URL_CURSOR="https://downloads.cursor.com/production/643ba67cd252e2888e296dd0cf34a0c5d7625b96/linux/x64/deb/amd64/deb/cursor_2.3.34_amd64.deb"
ARG URL_CLAUDE="https://claude.ai/install.sh"

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
# NOTES: 
#       * --no-install-recommends actually removes kiro due to deps below.
#       * The lxde package was installed previously since it pulls in deps needed by Kiro.
#         I've removed it and instead used dpkg-deb -f kiro.deb to determine what libs are needed.
# ----------------------------------------------------------------------
RUN apt-get update && apt-get install -y \
   ansible-lint \
   bc \
   ca-certificates \
   curl \
   dbus \
   dbus-x11 \
   dnsutils \
   file \
   fonts-noto-color-emoji \
   git \
   gnupg2 \
   iproute2 \
   iputils-ping \
   jq \
   libasound2t64 \
   libatk-bridge2.0-0 \
   libatk1.0-0 \
   libatspi2.0-0 \
   libcairo2 \
   libcups2 \
   libcurl4 \
   libgbm1 \
   libglib2.0-0 \
   libgtk-3-0 \
   libnspr4 \
   libnss3 \
   libpango-1.0-0 \
   libsecret-1-0 \
   libvulkan1 \
   libx11-6 \
   libxcb1 \
   libxcomposite1 \
   libxdamage1 \
   libxext6 \
   libxfixes3 \
   libxkbcommon0 \
   libxkbfile1 \
   libxrandr2 \
   libxss1 \
   locales \
   make \
   nano \
   net-tools \
   pass \
   python3-pip \
   python3-pyotp \
   python3-pyflakes \
   python3-pytest \
   python3-boto3 \
   rsync \
   sqlite3 \
   strace \
   sudo \
   traceroute \
   tree \
   unzip \
   vim \
   wget \
   x11-apps \
   x11-utils \
   xdg-utils \
   zip \
   && sed -i 's/^# en_US.UTF-8 UTF-8/en_US.UTF-8 UTF-8/' /etc/locale.gen \
   && locale-gen en_US.UTF-8 \
   && rm -rf /var/lib/apt/lists/*
ENV LANG=en_US.UTF-8 \
    LC_ALL=en_US.UTF-8 \
    LANGUAGE=en_US:en




# ----------------------------------------------------------------------
# Optional software installs
# ----------------------------------------------------------------------
# fail the build if Kiro can't be installed
RUN if [ "${WITH_KIRO}" = "1" ]; then \
      echo "Fetching latest Kiro IDE version..." && \
      KIRO_VERSION=$(curl -s https://prod.download.desktop.kiro.dev/stable/metadata-linux-x64-deb-stable.json | jq -r .currentRelease) && \
      echo "Latest Kiro IDE version: ${KIRO_VERSION}" && \
      URL_KIRO="https://prod.download.desktop.kiro.dev/releases/stable/linux-x64/signed/${KIRO_VERSION}/deb/kiro-ide-${KIRO_VERSION}-stable-linux-x64.deb" && \
      echo "Downloading from: ${URL_KIRO}" && \
      curl -fsSL --retry 5 --retry-delay 3 --retry-max-time 60 -o /tmp/kiro.deb "${URL_KIRO}" && \
      dpkg -i /tmp/kiro.deb || (apt-get install -f -y && dpkg -i /tmp/kiro.deb) && \
      which kiro || { echo "❌ Kiro binary not found after install - build failed"; exit 1; } && \
      su -s /bin/sh -c "kiro --version" nobody || { echo "❌ Kiro failed to run - build failed"; exit 1; } && \
      rm /tmp/kiro.deb && \
      rm -rf /var/lib/apt/lists/*; \
    else echo "Skipping Kiro installation"; fi    

# Install AWS CLI
RUN if [ "${WITH_AWS_CLI}" = "1" ]; then \
      echo "Downloading AWS Cli..." && \
      cd /tmp && curl -fsSL --retry 5 --retry-delay 3 --retry-max-time 60  ${URL_AWS_CLI} -o awscliv2.zip && \
      unzip awscliv2.zip >/dev/null  && \
      echo "Installing AWS Cli..." && \
      ./aws/install >/dev/null && \
      curl -fsSL --retry 5 --retry-delay 3 --retry-max-time 60  ${URL_SESSION_MANAGER} -o plugin.deb && dpkg -i plugin.deb; \
    else echo "Skipping AWS Cli installation"; fi

# Install OpenTofu
RUN if [ "${WITH_TOFU}" = "1" ]; then \
      cd /tmp && curl -fsSL --retry 5 --retry-delay 3 --retry-max-time 60  ${URL_TOFU} -o install.sh && \
      chmod +x install.sh && ./install.sh --install-method deb && rm install.sh; \
    else echo "Skipping OpenTofu installation"; fi


# Install VSCode - latest via apt
RUN if [ "${WITH_VSCODE}" = "1" ]; then \
      cd /tmp && \
      curl -fsSL https://packages.microsoft.com/keys/microsoft.asc | gpg --dearmor > packages.microsoft.gpg && \
      install -D -o root -g root -m 644 packages.microsoft.gpg /etc/apt/keyrings/packages.microsoft.gpg && \
      rm -f packages.microsoft.gpg && \
      echo "deb [arch=amd64,arm64,armhf signed-by=/etc/apt/keyrings/packages.microsoft.gpg] https://packages.microsoft.com/repos/code stable main" > /etc/apt/sources.list.d/vscode.list && \
      apt-get update && apt-get install -y code && \
      rm -rf /var/lib/apt/lists/*; \
    else echo "Skipping VS Code installation"; fi


# Install Cursor
RUN if [ "${WITH_CURSOR}" = "1" ]; then \
      cd /tmp && curl -fsSL --retry 5 --retry-delay 3 --retry-max-time 60  ${URL_CURSOR} -o install.deb && \
      apt install -y ./install.deb && rm ./install.deb; \
    else echo "Skipping Cursor installation"; fi

# Install Claude system-wide under /usr/local/bin
RUN if [ "${WITH_CLAUDE}" = "1" ]; then \
      cd /tmp && curl -fsSL --retry 5 --retry-delay 3 --retry-max-time 60  ${URL_CLAUDE} -o install.sh && \
      chmod +x install.sh && ./install.sh && \
      # Find the actual binary and copy to system location \
      CLAUDE_BINARY=$(readlink -f ~/.local/bin/claude) && \
      cp "$CLAUDE_BINARY" /usr/local/bin/claude && \
      chmod +x /usr/local/bin/claude && \
      # Clean up \
      rm install.sh && rm -rf ~/.local/bin/claude; \
    else echo "Skipping Claude installation"; fi

# ----------------------------------------------------------------------
# Homebrew / spacectl
# ----------------------------------------------------------------------
# Always define because brew MAY exist depending on flags
RUN if [ "${WITH_BREW}" = "1" ] || [ "${WITH_SPACECTL}" = "1" ]; then \
      echo "Creating brew user..." && \
      groupadd -r brew && \
      useradd -r -g brew -m -s /bin/bash brew && \
      mkdir -p /home/linuxbrew/.linuxbrew && \
      chown -R brew:brew /home/linuxbrew && \
      \
      echo "Installing Homebrew..." && \
      su - brew -c 'NONINTERACTIVE=1 /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"' && \
      \
      test -x /home/linuxbrew/.linuxbrew/bin/brew || { echo "❌ brew not found after install"; exit 1; } && \
      \
      su - brew -c '/home/linuxbrew/.linuxbrew/bin/brew --version'; \
    else \
      echo "Skipping Homebrew installation"; \
    fi

# Install spacectl via Homebrew
RUN if [ "${WITH_SPACECTL}" = "1" ]; then \
      echo 'eval "$(/home/linuxbrew/.linuxbrew/bin/brew shellenv)"' >> /etc/bash.bashrc && \
      su - brew -c 'eval "$(/home/linuxbrew/.linuxbrew/bin/brew shellenv)" && \
        brew tap spacelift-io/spacelift && \
        brew install spacelift-io/spacelift/spacectl && \
        spacectl version'; \
    else \
      echo "Skipping spacectl installation"; \
    fi

# ----------------------------------------------------------------------
# Fonts
# ----------------------------------------------------------------------
# Install Powerline fonts system-wide
RUN cd /tmp && \
    git clone https://github.com/powerline/fonts.git --depth=1 && \
    cd fonts && \
    mkdir -p /usr/share/fonts/truetype/powerline && \
    find . -name "*.ttf" -exec cp {} /usr/share/fonts/truetype/powerline/ \; && \
    find . -name "*.otf" -exec cp {} /usr/share/fonts/truetype/powerline/ \; && \
    fc-cache -f -v && \
    cd /tmp && rm -rf fonts

# ----------------------------------------------------------------------
# Chromium
# ----------------------------------------------------------------------
RUN apt-get update && \
    apt-get install -y software-properties-common wget gnupg2 && \
    add-apt-repository -y ppa:xtradeb/apps && \
    apt-get update && \
    apt-get install -y chromium

RUN if [ -f /bin/chromium ]; then \
      cp /bin/chromium /usr/bin/chromium.bak && \
      sed -i -E 's|^(CHROMIUM_FLAGS=.*)|CHROMIUM_FLAGS="--no-sandbox --disable-software-rasterizer --disable-dev-shm-usage"|g' /bin/chromium; \
    else echo "Chromium not installed, skipping flag fix"; fi

# ----------------------------------------------------------------------
# Install 1Password op CLI (latest)
# ----------------------------------------------------------------------
# Install 1Password CLI via APT (per 1Password’s official get‑started guide)
RUN set -eux \
    # Import 1Password public key
    && curl -sS https://downloads.1password.com/linux/keys/1password.asc | \
        gpg --dearmor --batch --yes \
            --output /usr/share/keyrings/1password-archive-keyring.gpg \
    \
    # Add 1Password APT repo (for amd64)
    && echo "deb [arch=amd64 signed-by=/usr/share/keyrings/1password-archive-keyring.gpg] https://downloads.1password.com/linux/debian/amd64 stable main" \
        > /etc/apt/sources.list.d/1password.list \
    \
    # Install 1Password CLI package
    && apt-get update \
    && apt-get install -y 1password-cli \
    \
    # Verify it’s there
    && op --version



# ----------------------------------------------------------------------
# Append custom bash additions
# ----------------------------------------------------------------------
RUN cat /tmp/bashrc-addition >> /etc/bash.bashrc && rm /tmp/bashrc-addition

# ----------------------------------------------------------------------
# Copy entrypoint script for provisioning and runtime user setup
# ----------------------------------------------------------------------
COPY ./usr/local/bin/entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod +x /usr/local/bin/entrypoint.sh


# ----------------------------------------------------------------------
# Add some capability to the container
# Avoids needing NET_RAW granted to the whole container at runtime.
# ----------------------------------------------------------------------
RUN setcap cap_net_raw+ep $(readlink -f $(which ping))        && \
    setcap cap_net_raw+ep $(readlink -f $(which traceroute))

# ----------------------------------------------------------------------
# Default ENTRYPOINT (runs bash shell)
# ----------------------------------------------------------------------
ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
