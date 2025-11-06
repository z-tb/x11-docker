# Use the official Ubuntu base image
FROM ubuntu:24.04

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

# Set the working directory
WORKDIR /apps

# update package lists
RUN apt-get update

# install some support packages/X11 apps
RUN apt-get install -y \
    sudo \
    git \
    curl \
    pass \
    gnupg2 \
    chromium-browser \
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

### sane X11 fonts ###
RUN cd /tmp && git clone https://github.com/powerline/fonts.git --depth=1 && cd fonts && ./install.sh

# append bash custom code to /etc/bash.bashrc
RUN cat /tmp/bashrc-addition >> /etc/bash.bashrc && rm /tmp/bashrc-addition

### Create non-root user/user running build ###
RUN groupadd -g ${USER_GROUP_GID} ${USER_GROUP_NAME} \
    && useradd -u ${USER_UID} -g ${USER_GROUP_GID} -G sudo -m -s ${USER_SHELL} ${USER_NAME} -d ${USER_HOME} \
    && echo "${USER_NAME} ALL=(ALL:ALL) NOPASSWD:ALL" > /etc/sudoers.d/sudo-users

# switch to non-root user for shell
USER ${USER_NAME}

# setup user's home directory in container - symlink to /mnt/home/$USER for "real" volume mounts/persistence
RUN echo 'pcol' >> ${USER_HOME}/.bashrc

RUN ln -sf /mnt/${USER_HOME}/.ssh ~/ \
    && ln -sf /mnt/${USER_HOME}/.gitconfig ~/ \
    && ln -sf /mnt/${USER_HOME}/.kiro ~/

# Prepare home mount dirs
# RUN mkdir -p ~/{.config,.local}

# can also run Xephyr in the background with the desired screen resolution to get a virtual desktop that isn't VNC
# To change Xephyr window size after starting cinnamon-session: xrandr --output default --mode 1280x720
CMD ["/bin/bash"]
