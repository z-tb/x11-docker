# Use the official Ubuntu base image
FROM ubuntu:20.04

# don't prompt for input during build
ARG DEBIAN_FRONTEND=noninteractive 

# create a user account, non-root
RUN useradd -ms /bin/bash tux

# Give sudo access
RUN usermod -aG sudo tux

# Copy custom bash.bashrc additions into the image
COPY etc/bashrc-addition /tmp/
 
# Set the working directory
WORKDIR /app

# python reqs
#COPY requirements.txt /app/requirements.txt
#RUN pip3 install -r requirements.txt

# Install Python 3 and pip
RUN apt-get update && apt-get dist-upgrade -y

# install some support packages
RUN apt-get install sudo \
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
   firefox -y

# add tux user to sudoers
RUN echo '%sudo ALL=(ALL:ALL) NOPASSWD:ALL' > /etc/sudoers.d/sudo-group

# append bash custom code to /etc/bash.bashrc
RUN cat /tmp/bashrc-addition >> /etc/bash.bashrc && \
    rm /tmp/bashrc-addition
    
# switch to non-root user for shell
USER tux

# Run Xephyr in the background with the desired screen resolution
# To change Xephyr window size after starting cinnamon-session: xrandr --output default --mode 1280x720
CMD ["/bin/bash"]
