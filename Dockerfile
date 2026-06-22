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
FROM nvidia/cuda:13.3.0-runtime-ubuntu24.04

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
ARG WITH_GHCLI

# ----------------------------------------------------------------------
# URLs for external downloads
# ----------------------------------------------------------------------
ARG URL_AWS_CLI="https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip"
ARG URL_SESSION_MANAGER="https://s3.amazonaws.com/session-manager-downloads/plugin/latest/ubuntu_64bit/session-manager-plugin.deb"
ARG URL_TOFU="https://get.opentofu.org/install-opentofu.sh"
ARG URL_CURSOR="https://downloads.cursor.com/production/643ba67cd252e2888e296dd0cf34a0c5d7625b96/linux/x64/deb/amd64/deb/cursor_2.3.34_amd64.deb"
ARG URL_CLAUDE="https://claude.ai/install.sh"

# ----------------------------------------------------------------------
# Working directory & Status Reports setup
# ----------------------------------------------------------------------
WORKDIR /apps
RUN mkdir -p /tmp/build-report

# ----------------------------------------------------------------------
# Copy custom bash additions into /tmp
# ----------------------------------------------------------------------
COPY etc/bashrc-addition /tmp/

# ----------------------------------------------------------------------
# Pre-requisites for Third-Party Repos (gopass, etc)
# ----------------------------------------------------------------------
RUN apt-get update && apt-get install -y \
    ca-certificates \
    curl \
    gnupg2

# ----------------------------------------------------------------------
# Configure Third-Party Repos (gopass + CUDA Key Fix)
# ----------------------------------------------------------------------
RUN if [ -f /etc/apt/trusted.gpg ]; then \
      gpg --no-default-keyring --keyring /etc/apt/trusted.gpg --export 24157E7A > /etc/apt/keyrings/cuda-archive-keyring.gpg 2>/dev/null || true; \
      rm -f /etc/apt/trusted.gpg; \
    fi \
   && printf "\033[0;32mAdding gopass repository...\033[0m\n" \
   && curl -fsSL https://packages.gopass.pw/repos/gopass/gopass-archive-keyring.gpg > /usr/share/keyrings/gopass-archive-keyring.gpg \
   && printf "Types: deb\nURIs: https://packages.gopass.pw/repos/gopass\nSuites: stable\nArchitectures: all amd64 arm64 armhf\nComponents: main\nSigned-By: /usr/share/keyrings/gopass-archive-keyring.gpg\n" > /etc/apt/sources.list.d/gopass.sources

# ----------------------------------------------------------------------
# Base packages / X11 support / GUI app support
# ----------------------------------------------------------------------
RUN apt-get update && apt-get install -y \
   ansible-lint \
   bc \
   binutils \
   dbus \
   dbus-x11 \
   dnsutils \
   file \
   fonts-noto-color-emoji \
   git \
   gopass \
   gopass-archive-keyring \
   hexcurse \
   hexdiff \
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
   tzdata \
   unzip \
   vim \
   wget \
   x11-apps \
   x11-utils \
   xdg-utils \
   zip \
   >/dev/null \
   && sed -i 's/^# en_US.UTF-8 UTF-8/en_US.UTF-8 UTF-8/' /etc/locale.gen \
   && locale-gen en_US.UTF-8 >/dev/null \
   && rm -rf /var/lib/apt/lists/*
ENV LANG=en_US.UTF-8 \
     LC_ALL=en_US.UTF-8 \
     LANGUAGE=en_US:en

# ----------------------------------------------------------------------
# Optional software installs
# ----------------------------------------------------------------------

# Install Kiro IDE
RUN if [ "${WITH_KIRO}" = "1" ]; then \
      printf "\033[0;32mFetching latest Kiro IDE version...\033[0m\n" && \
      KIRO_VERSION=$(curl -s https://prod.download.desktop.kiro.dev/stable/metadata-linux-x64-deb-stable.json | jq -r .currentRelease) && \
      printf "\033[0;35mLatest Kiro IDE version:\033[0;37m ${KIRO_VERSION}\033[0m\n" && \
      URL_KIRO="https://prod.download.desktop.kiro.dev/releases/stable/linux-x64/signed/${KIRO_VERSION}/deb/kiro-ide-${KIRO_VERSION}-stable-linux-x64.deb" && \
      echo "Downloading from: ${URL_KIRO}" && \
      curl -fsSL --retry 5 --retry-delay 3 --retry-max-time 60 -o /tmp/kiro.deb "${URL_KIRO}" && \
      dpkg -i /tmp/kiro.deb || (apt-get install -f -y && dpkg -i /tmp/kiro.deb) && \
      which kiro || { echo "❌ Kiro binary not found after install - build failed"; exit 1; } && \
      su -s /bin/sh -c "kiro --version" nobody || { echo "❌ Kiro failed to run - build failed"; exit 1; } && \
      rm /tmp/kiro.deb && \
      rm -rf /var/lib/apt/lists/* && \
      printf "\033[0;32mKiro installed OK\033[0m\n" && \
      printf "  %-15s : \033[0;32mInstalled OK\033[0m\n" "Kiro IDE" > /tmp/build-report/01-kiro; \
    else \
      printf "\033[0;33mSkipping Kiro installation\033[0m\n" && \
      printf "  %-15s : \033[0;33mSkipped\033[0m\n" "Kiro IDE" > /tmp/build-report/01-kiro; \
    fi    

# Install AWS CLI
RUN if [ "${WITH_AWS_CLI}" = "1" ]; then \
      printf "\033[0;32mDownloading AWS Cli...\033[0m\n" && \
      cd /tmp && curl -fsSL --retry 5 --retry-delay 3 --retry-max-time 60  ${URL_AWS_CLI} -o awscliv2.zip && \
      unzip awscliv2.zip >/dev/null  && \
      printf "\033[0;32mInstalling AWS Cli...\033[0m\n" && \
      ./aws/install >/dev/null && \
      curl -fsSL --retry 5 --retry-delay 3 --retry-max-time 60  ${URL_SESSION_MANAGER} -o plugin.deb && dpkg -i plugin.deb && \
      printf "\033[0;32mAWS Cli installed OK\033[0m\n" && \
      printf "  %-15s : \033[0;32mInstalled OK\033[0m\n" "AWS CLI" > /tmp/build-report/02-aws; \
    else \
      printf "\033[0;33mSkipping AWS Cli installation\033[0m\n" && \
      printf "  %-15s : \033[0;33mSkipped\033[0m\n" "AWS CLI" > /tmp/build-report/02-aws; \
    fi

# Install OpenTofu
RUN if [ "${WITH_TOFU}" = "1" ]; then \
      printf "\033[0;32mInstalling OpenTofu...\033[0m\n" && \
      cd /tmp && curl -fsSL --retry 5 --retry-delay 3 --retry-max-time 60  ${URL_TOFU} -o install.sh && \
      chmod +x install.sh && ./install.sh --install-method deb && rm install.sh && \
      printf "\033[0;32mOpenTofu installed OK\033[0m\n" && \
      printf "  %-15s : \033[0;32mInstalled OK\033[0m\n" "OpenTofu" > /tmp/build-report/03-tofu; \
    else \
      printf "\033[0;33mSkipping OpenTofu installation\033[0m\n" && \
      printf "  %-15s : \033[0;33mSkipped\033[0m\n" "OpenTofu" > /tmp/build-report/03-tofu; \
    fi

# Install VSCode - latest via apt
RUN if [ "${WITH_VSCODE}" = "1" ]; then \
      printf "\033[0;32mInstalling VS Code...\033[0m\n" && \
      cd /tmp && \
      curl -fsSL https://packages.microsoft.com/keys/microsoft.asc | gpg --dearmor > packages.microsoft.gpg && \
      install -D -o root -g root -m 644 packages.microsoft.gpg /etc/apt/keyrings/packages.microsoft.gpg && \
      rm -f packages.microsoft.gpg && \
      echo "deb [arch=amd64,arm64,armhf signed-by=/etc/apt/keyrings/packages.microsoft.gpg] https://packages.microsoft.com/repos/code stable main" > /etc/apt/sources.list.d/vscode.list && \
      apt-get update -qq && apt-get install -y -qq code >/dev/null && \
      rm -rf /var/lib/apt/lists/* && \
      printf "\033[0;32mVS Code installed OK\033[0m\n" && \
      printf "  %-15s : \033[0;32mInstalled OK\033[0m\n" "VS Code" > /tmp/build-report/04-vscode; \
    else \
      printf "\033[0;33mSkipping VS Code installation\033[0m\n" && \
      printf "  %-15s : \033[0;33mSkipped\033[0m\n" "VS Code" > /tmp/build-report/04-vscode; \
    fi

# Install Cursor
RUN if [ "${WITH_CURSOR}" = "1" ]; then \
      printf "\033[0;32mInstalling Cursor...\033[0m\n" && \
      cd /tmp && curl -fsSL --retry 5 --retry-delay 3 --retry-max-time 60  ${URL_CURSOR} -o install.deb && \
      apt install -y -qq ./install.deb >/dev/null && rm ./install.deb && \
      printf "\033[0;32mCursor installed OK\033[0m\n" && \
      printf "  %-15s : \033[0;32mInstalled OK\033[0m\n" "Cursor" > /tmp/build-report/05-cursor; \
    else \
      printf "\033[0;33mSkipping Cursor installation\033[0m\n" && \
      printf "  %-15s : \033[0;33mSkipped\033[0m\n" "Cursor" > /tmp/build-report/05-cursor; \
    fi

# Install Claude system-wide under /usr/local/bin
RUN if [ "${WITH_CLAUDE}" = "1" ]; then \
      printf "\033[0;32mInstalling Claude...\033[0m\n" && \
      cd /tmp && curl -fsSL --retry 5 --retry-delay 3 --retry-max-time 60  ${URL_CLAUDE} -o install.sh && \
      chmod +x install.sh && ./install.sh && \
      CLAUDE_BINARY=$(readlink -f ~/.local/bin/claude) && \
      cp "$CLAUDE_BINARY" /usr/local/bin/claude && \
      chmod +x /usr/local/bin/claude && \
      rm install.sh && rm -rf ~/.local/bin/claude && \
      printf "\033[0;32mClaude installed OK\033[0m\n" && \
      printf "  %-15s : \033[0;32mInstalled OK\033[0m\n" "Claude CLI" > /tmp/build-report/06-claude; \
    else \
      printf "\033[0;33mSkipping Claude installation\033[0m\n" && \
      printf "  %-15s : \033[0;33mSkipped\033[0m\n" "Claude CLI" > /tmp/build-report/06-claude; \
    fi

# ----------------------------------------------------------------------
# Homebrew / spacectl / GitHub CLI
# ----------------------------------------------------------------------
# Always define because brew MAY exist depending on flags
RUN if [ "${WITH_BREW}" = "1" ] || [ "${WITH_SPACECTL}" = "1" ] || [ "${WITH_GHCLI}" = "1" ]; then \
      printf "\033[0;32mCreating brew user...\033[0m\n" && \
      groupadd -r brew && \
      useradd -r -g brew -m -s /bin/bash brew && \
      mkdir -p /home/linuxbrew/.linuxbrew && \
      chown -R brew:brew /home/linuxbrew && \
      \
      printf "\033[0;32mInstalling Homebrew...\033[0m\n" && \
      su - brew -c 'NONINTERACTIVE=1 /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"' && \
      test -x /home/linuxbrew/.linuxbrew/bin/brew || { echo "❌ brew not found after install"; exit 1; } && \
      su - brew -c '/home/linuxbrew/.linuxbrew/bin/brew --version' && \
      printf "\033[0;32mHomebrew installed OK\033[0m\n" && \
      printf "  %-15s : \033[0;32mInstalled OK\033[0m\n" "Homebrew" > /tmp/build-report/07-brew; \
    else \
      printf "\033[0;33mSkipping Homebrew installation\033[0m\n" && \
      printf "  %-15s : \033[0;33mSkipped\033[0m\n" "Homebrew" > /tmp/build-report/07-brew; \
    fi

# Install spacectl via Homebrew
RUN if [ "${WITH_SPACECTL}" = "1" ]; then \
      echo 'eval "$(/home/linuxbrew/.linuxbrew/bin/brew shellenv)"' >> /etc/bash.bashrc && \
      su - brew -c 'eval "$(/home/linuxbrew/.linuxbrew/bin/brew shellenv)" && \
        brew tap spacelift-io/spacelift && \
        brew install spacelift-io/spacelift/spacectl && \
        spacectl version' && \
      printf "\033[0;32mspacectl installed OK\033[0m\n" && \
      printf "  %-15s : \033[0;32mInstalled OK\033[0m\n" "spacectl" > /tmp/build-report/08-spacectl; \
    else \
      printf "\033[0;33mSkipping spacectl installation\033[0m\n" && \
      printf "  %-15s : \033[0;33mSkipped\033[0m\n" "spacectl" > /tmp/build-report/08-spacectl; \
    fi

# Install github cli via brew
RUN if [ "${WITH_GHCLI}" = "1" ]; then \
      grep -qxF 'eval "$(/home/linuxbrew/.linuxbrew/bin/brew shellenv)"' /etc/bash.bashrc || \
        echo 'eval "$(/home/linuxbrew/.linuxbrew/bin/brew shellenv)"' >> /etc/bash.bashrc && \
      su - brew -c 'eval "$(/home/linuxbrew/.linuxbrew/bin/brew shellenv)" && \
        brew install gh && \
        gh --version' && \
      printf "\033[0;32mGitHub CLI installed OK\033[0m\n" && \
      printf "  %-15s : \033[0;32mInstalled OK\033[0m\n" "GitHub CLI" > /tmp/build-report/09-ghcli; \
    else \
      printf "\033[0;33mSkipping GitHub CLI installation\033[0m\n" && \
      printf "  %-15s : \033[0;33mSkipped\033[0m\n" "GitHub CLI" > /tmp/build-report/09-ghcli; \
    fi

# ----------------------------------------------------------------------
# Powerline Fonts
# ----------------------------------------------------------------------
RUN cd /tmp && \
    git clone https://github.com/powerline/fonts.git --depth=1 && \
    cd fonts && \
    mkdir -p /usr/share/fonts/truetype/powerline && \
    find . -name "*.ttf" -exec cp {} /usr/share/fonts/truetype/powerline/ \; && \
    find . -name "*.otf" -exec cp {} /usr/share/fonts/truetype/powerline/ \; && \
    fc-cache -f -v && \
    cd /tmp && rm -rf fonts

# ----------------------------------------------------------------------
# Chromium Installation & Flag Patching
# ----------------------------------------------------------------------
RUN apt-get update -qq && \
    apt-get install -y -qq software-properties-common wget >/dev/null && \
    add-apt-repository -y ppa:xtradeb/apps >/dev/null && \
    apt-get update -qq && \
    apt-get install -y -qq chromium >/dev/null

RUN if [ -f /bin/chromium ]; then \
      cp /bin/chromium /usr/bin/chromium.bak && \
      sed -i -E 's|^(CHROMIUM_FLAGS=.*)|CHROMIUM_FLAGS="--no-sandbox --disable-software-rasterizer --disable-dev-shm-usage"|g' /bin/chromium; \
    else echo "Chromium not installed, skipping flag fix"; fi

# ----------------------------------------------------------------------
# Install 1Password op CLI (latest)
# ----------------------------------------------------------------------
RUN set -eux \
    && curl -sS https://downloads.1password.com/linux/keys/1password.asc | \
        gpg --dearmor --batch --yes \
            --output /usr/share/keyrings/1password-archive-keyring.gpg \
    && echo "deb [arch=amd64 signed-by=/usr/share/keyrings/1password-archive-keyring.gpg] https://downloads.1password.com/linux/debian/amd64 stable main" \
        > /etc/apt/sources.list.d/1password.list \
    && apt-get update -qq \
    && apt-get install -y -qq 1password-cli >/dev/null \
    && op --version


# ----------------------------------------------------------------------
# Install z-tb (me) epass utility from GitHub
# ----------------------------------------------------------------------
RUN printf "\033[0;32mInstalling epass utility from GitHub...\033[0m\n" \
   && curl -fsSL "https://raw.githubusercontent.com/z-tb/linuxadmin/main/cli/epass" -o /usr/local/bin/epass \
   && chmod +x /usr/local/bin/epass \
   && printf "\033[0;32mepass utility installed OK\033[0m\n"


# ----------------------------------------------------------------------
# Append custom bash additions
# ----------------------------------------------------------------------
RUN cat /tmp/bashrc-addition >> /etc/bash.bashrc && rm /tmp/bashrc-addition

# ----------------------------------------------------------------------
# Entrypoint Configuration
# ----------------------------------------------------------------------
COPY ./usr/local/bin/entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod +x /usr/local/bin/entrypoint.sh

# ----------------------------------------------------------------------
# Networking Capabilities for Non-Root Runtime Diagnostics
# ----------------------------------------------------------------------
RUN setcap cap_net_raw+ep $(readlink -f $(which ping))        && \
    setcap cap_net_raw+ep $(readlink -f $(which traceroute))

# ----------------------------------------------------------------------
# Print Build Summary Report
# ----------------------------------------------------------------------
RUN printf "\n\033[1;36m=========================================\033[0m\n" && \
    printf "\033[1;36m       DOCKER IMAGE BUILD REPORT         \033[0m\n" && \
    printf "\033[1;36m=========================================\033[0m\n" && \
    cat /tmp/build-report/* && \
    printf "\033[1;36m=========================================\033[0m\n\n" && \
    rm -rf /tmp/build-report

# ----------------------------------------------------------------------
# Default ENTRYPOINT
# ----------------------------------------------------------------------
ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
