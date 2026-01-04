#!/bin/bash

# If the Makefile is too cumbersome, this script can help define the runtime environment
 HOST_PATH="/home/src"        # The project directory to mount in the container
IMAGE_NAME="x11-image"        # The name of the image to contianerize (default x11-image)
 USER_HOME="/home/jct"        # The home directory to use in the container for your user

# Format a list of groups to pass into container
# These could also be hard coded literals. (eg: developer:12121,admin:32322)
SUPP_GROUPS=$(id -nG | tr ' ' '\n' | while read -r group; do
  gid=$(getent group "$group" | cut -d: -f3)
  echo "$group:$gid"
done | paste -sd,)

# Forward the SSH socket into container so ssh works without access to secret keys
SSH_FORWARD=""
if [ -n "$SSH_AUTH_SOCK" ]; then
   SSH_FORWARD="--env SSH_AUTH_SOCK=$SSH_AUTH_SOCK --volume $SSH_AUTH_SOCK:$SSH_AUTH_SOCK"
else
   echo "⚠️ SSH_AUTH_SOCK not set on host; mount ~/.ssh manually or start an ssh-agent."
fi

docker run -it --rm --shm-size=1g \
  --name "$CONTAINER_NAME" \
  --hostname "$IMAGE_NAME" \
  --env DISPLAY="$DISPLAY" \
  --env USER_UID=$(id -u) \
  --env USER_GROUP_GID=$(id -g) \
  --env USER_GROUP_NAME=$(id -gn) \
  --env USER_NAME="jct" \
  --env USER_SHELL="/bin/bash" \
  --env USER_HOME="${USER_HOME}" \
  --env USER_GROUPS="$SUPP_GROUPS" \
  --env SSH_AUTH_SOCK=/ssh-agent \
  $SSH_FORWARD \
  --volume "./jtid/.kiro:${USER_HOME}/.kiro:rw" \
  --volume "${HOME}/.gitconfig:${USER_HOME}/.gitconfig:rw" \
  --volume "./jtid/.config/Kiro:${USER_HOME}/.config/Kiro:rw" \
  --volume /tmp/.X11-unix:/tmp/.X11-unix:rw \
  --volume "${HOST_PATH}:/home/src:rw" \
  --gpus all \
  --volume /dev/dri:/dev/dri \
  "$IMAGE_NAME"

