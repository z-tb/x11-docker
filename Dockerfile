FROM ubuntu:20.04

ARG DEBIAN_FRONTEND=noninteractive
ARG CURSOR_USER_UID
ARG GROUPS="code,docker,developer"

# Create groups first
RUN groupadd --gid 38003 code && \
groupadd --gid 143 docker && \
groupadd --gid 38004 developer

# Create tux user with correct UID and groups in one step
RUN useradd -u ${CURSOR_USER_UID} -G sudo,code,docker,developer -ms /bin/bash tux

# Install dependencies
RUN apt-get update && apt -y install sudo \
net-tools \
vim nano \
x11-apps \
strace \
chromium-browser \
lxde \
libasound2 \
libpulse0 \
libasound2-plugins \
cinnamon \
dbus \
dbus-x11 \
x11-utils \
openbox \
firefox

# Configure sudo access
RUN echo '%sudo ALL=(ALL:ALL) NOPASSWD:ALL' > /etc/sudoers.d/sudo-group

# Copy and configure bash settings
COPY etc/bashrc-addition /tmp/
RUN cat /tmp/bashrc-addition >> /etc/bash.bashrc && \
rm /tmp/bashrc-addition

WORKDIR /app
USER tux

CMD ["/bin/bash"]