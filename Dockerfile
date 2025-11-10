# Use the official Ubuntu base image
# FROM ubuntu:24.04
# use the nvidia cuda runtime base image for GPU passthrough support
FROM nvidia/cuda:13.0.1-runtime-ubuntu24.04

# don't prompt for input during build
ARG DEBIAN_FRONTEND=noninteractive 

# User configuration arguments
ARG USER_UID
ARG USER_GROUP_GID
ARG USER_GROUP_NAME
ARG USER_NAME
ARG USER_SHELL
ARG USER_HOME

# Copy custom bash.bashrc additions into the image
COPY etc/bashrc-addition /tmp/

# set to 1 in Makefile to install amazon kiro
ARG WITH_KIRO
ARG WITH_AWS_CLI
ARG WITH_TOFU
ARG WITH_CURSOR
ARG WITH_VSCODE

# Set the working directory
WORKDIR /apps

# update package lists
RUN apt-get update

# install some support packages/X11 apps - NOTE: snap apps won't work in the container
RUN apt-get install -y \
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
    firefox

RUN apt-get install -y \
    libasound2t64 \
    libx11-6 \
    libxkbfile1 \
    libsecret-1-0 \
    libxss1 \
    libnss3 \
    libatk1.0-0

### Kiro + Chromium deps ###
RUN if [ "${WITH_KIRO}" = "1" ]; then \      
      curl -fsSL -o /tmp/kiro.deb https://prod.download.desktop.kiro.dev/releases/202511032205--distro-linux-x64-deb/202511032205-distro-linux-x64.deb && \
      dpkg -i /tmp/kiro.deb || apt-get install -f -y && \
      rm /tmp/kiro.deb && rm -rf /var/lib/apt/lists/*; \
    else \
      echo "Skipping Kiro installation"; \
    fi

### AWS CLI + Session Manager ###
RUN if [ "${WITH_AWS_CLI}" = "1" ]; then \
      cd /tmp && curl -fsSL "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o awscliv2.zip && unzip awscliv2.zip && ./aws/install && \
      curl -fsSL "https://s3.amazonaws.com/session-manager-downloads/plugin/latest/ubuntu_64bit/session-manager-plugin.deb" -o plugin.deb && dpkg -i plugin.deb; \
    fi

# Conditional package installs
### OpenTofu ###
RUN if [ "${WITH_TOFU}" = "1" ]; then \
      cd /tmp && curl -fsSL https://get.opentofu.org/install-opentofu.sh -o install.sh && \
      chmod +x install.sh && ./install.sh --install-method deb && rm install.sh; \
    fi

### VSCode ###
RUN if [ "${WITH_VSCODE}" = "1" ]; then \
      cd /tmp && curl -fsSL https://vscode.download.prss.microsoft.com/dbazure/download/stable/7d842fb85a0275a4a8e4d7e040d2625abbf7f084/code_1.105.1-1760482543_amd64.deb -o install.deb && \
      apt install ./install.deb && rm ./install.deb; \
    fi

### Cursor IDE ###
RUN if [ "${WITH_CURSOR}" = "1" ]; then \
      cd /tmp && curl -fsSL https://downloads.cursor.com/production/63fcac100bd5d5749f2a98aa47d65f6eca61db39/linux/x64/deb/amd64/deb/cursor_2.0.69_amd64.deb -o install.deb && \
      apt install ./install.deb && rm ./install.deb; \
    fi

### sane X11 fonts ###
RUN cd /tmp && git clone https://github.com/powerline/fonts.git --depth=1 && cd fonts && ./install.sh

### Create non-root user/user running build ###
RUN groupadd -g ${USER_GROUP_GID} ${USER_GROUP_NAME} \
    && useradd -u ${USER_UID} -g ${USER_GROUP_GID} -G sudo -d ${USER_HOME} -s ${USER_SHELL} -m ${USER_NAME} \
    && echo "${USER_NAME} ALL=(ALL:ALL) NOPASSWD:ALL" > /etc/sudoers.d/sudo-users

# install chromium from something that isn't 🤡Snap🤡 based
# https://xtradeb.net/
RUN apt-get update && \
    apt-get install -y software-properties-common wget gnupg2 && \
    add-apt-repository -y ppa:xtradeb/apps && \
    apt-get update && \
    apt-get install -y chromium

# Optional: clean up to reduce image size
RUN apt-get clean && rm -rf /var/lib/apt/lists/*

# append bash custom code to /etc/bash.bashrc
RUN cat /tmp/bashrc-addition >> /etc/bash.bashrc && rm /tmp/bashrc-addition

# Fix Chromium flags to work in Docker (I don't think Kiro will launch it with --no-sandbox)
RUN if [ -f /bin/chromium ]; then \
      cp /bin/chromium /usr/bin/chromium.bak && \
      sed -i -E 's|^(CHROMIUM_FLAGS=.*)|CHROMIUM_FLAGS="--no-sandbox --disable-software-rasterizer --disable-dev-shm-usage"|g' /bin/chromium; \
    else \
      echo "Chromium not installed, skipping flag fix"; \
    fi


# -------------------------------------------------------------------
# switch to non-root user to do user privileged stuff
# -------------------------------------------------------------------
USER ${USER_NAME}

# setup user's home directory in container - symlink to /mnt/home/$USER for "real" volume mounts/persistence
RUN echo 'pcol' >> ${USER_HOME}/.bashrc

# Prepare home mount dirs
#RUN mkdir -p {$USER_HOME/.config,$USER_HOME/.local}
RUN mkdir -p $HOME/.config && mkdir -p $HOME/.local

# can also run Xephyr in the background with the desired screen resolution to get a virtual desktop that isn't VNC
# To change Xephyr window size after starting cinnamon-session: xrandr --output default --mode 1280x720
CMD ["/bin/bash"]
