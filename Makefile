# ----------------------------------------------------------------------
# Makefile for building and running X11 + PulseAudio + Kiro IDE Docker
# ----------------------------------------------------------------------

# Image / container names
IMAGE_NAME       := x11-image
CONTAINER_NAME   := x11-test

# Host and container paths
HOST_PATH        := $(HOME)/apps
CONT_APP_MNT     := /apps

# User info
USER_UID         := $(shell id -u)
USER_GROUP_GID   := $(shell id -g)
USER_GROUP_NAME  := $(shell id -gn)
USER_NAME        := $(shell id -un)
USER_SHELL       := /bin/bash
USER_HOME        := $(HOME)

# Docker group for socket forwarding
DOCKER_GID       := $(shell getent group docker | cut -d: -f3)

# Optional installation flags
WITH_KIRO        ?= 1
WITH_AWS_CLI     ?= 1
WITH_TOFU        ?= 1
WITH_CURSOR      ?= 1
WITH_VSCODE      ?= 1


# ----------------------------------------------------------------------
# Build targets
# ----------------------------------------------------------------------


build:
	docker build --progress=plain \
		--build-arg USER_UID=$(USER_UID) \
		--build-arg USER_GROUP_GID=$(USER_GROUP_GID) \
		--build-arg USER_GROUP_NAME=$(USER_GROUP_NAME) \
		--build-arg USER_NAME=$(USER_NAME) \
		--build-arg USER_SHELL=$(USER_SHELL) \
		--build-arg USER_HOME=$(USER_HOME) \
		--build-arg CONT_APP_MNT=$(CONT_APP_MNT) \
		--build-arg IMAGE_NAME=$(IMAGE_NAME) \
		--build-arg WITH_KIRO=$(WITH_KIRO) \
		--build-arg WITH_AWS_CLI=$(WITH_AWS_CLI) \
		--build-arg WITH_TOFU=$(WITH_TOFU) \
		--build-arg WITH_VSCODE=$(WITH_VSCODE) \
		--build-arg WITH_CURSOR=$(WITH_CURSOR) \
		-t $(IMAGE_NAME):latest -f ./Dockerfile .

rebuild:
	docker build --no-cache \
		--build-arg USER_UID=$(USER_UID) \
		--build-arg USER_GROUP_GID=$(USER_GROUP_GID) \
		--build-arg USER_GROUP_NAME=$(USER_GROUP_NAME) \
		--build-arg USER_NAME=$(USER_NAME) \
		--build-arg USER_SHELL=$(USER_SHELL) \
		--build-arg USER_HOME=$(USER_HOME) \
		--build-arg CONT_APP_MNT=$(CONT_APP_MNT) \
		--build-arg IMAGE_NAME=$(IMAGE_NAME) \
		--build-arg WITH_KIRO=$(WITH_KIRO) \
		-t $(IMAGE_NAME):latest -f ./Dockerfile .

# ----------------------------------------------------------------------
# Basic container run targets
# ----------------------------------------------------------------------

run:
	docker run -it --name $(CONTAINER_NAME) $(IMAGE_NAME)

runm:
	docker run -it --rm -v $(HOST_PATH):/apps $(IMAGE_NAME) /bin/bash

stop:
	docker stop $(CONTAINER_NAME)

clean:
	docker rm $(CONTAINER_NAME) || true
	docker rmi $(IMAGE_NAME) || true

connect:
	docker exec -it ${CONTAINER_NAME} /bin/bash

# ----------------------------------------------------------------------
# Run with X11 and PulseAudio support (host display)
# ----------------------------------------------------------------------

runx:
	docker run -it --rm \
		--env DISPLAY=$(DISPLAY) \
		--env USER=$(USER_NAME) \
		--volume /tmp/.X11-unix:/tmp/.X11-unix:rw \
		--volume $(HOST_PATH):/apps:rw \
		--volume /etc/alsa:/etc/alsa:ro \
		--volume /usr/share/alsa:/usr/share/alsa:ro \
		--volume $(HOME)/.config/pulse:/home/$(USER_NAME)/.config/pulse:rw \
		--volume /run/user/$(USER_UID)/pulse/native:/run/user/$(USER_UID)/pulse/native:rw \
		--env PULSE_SERVER=unix:/run/user/$(USER_UID)/pulse/native \
		--user $(USER_UID):$(USER_GROUP_GID) \
		--group-add $(DOCKER_GID) \
		$(IMAGE_NAME) /bin/bash

# Run container with X11, PulseAudio, and GPU passthrough
#  * X11 forwarding
#  * PulseAudio/alsa forwarding - could maybe be symlinks to /mnt/$USER_HOME in container?
#  * App mounting - or data directory for work in continer
#  * GPU passthrough
#  * Use the same user as host to avoid permission issues on $HOME
#  * forward group for Docker socket if needed
#  * mount ~/.kiro RW for Kiro settings persistence
#  * mount ~/.config/Kiro RW for Kiro settings persistence
runx2:
	docker run -it --rm --shm-size=1g \
		--name $(CONTAINER_NAME) \
		--hostname $(IMAGE_NAME) \
		--env DISPLAY=$(DISPLAY) \
		--env USER=$(USER_NAME) \
		--volume ${USER_HOME}:/mnt/${USER_HOME}:ro \
		--volume ${USER_HOME}/.kiro:/mnt/${USER_HOME}/.kiro:rw \
		--volume ${USER_HOME}/.config/Kiro:/mnt/${USER_HOME}/.config/Kiro:rw \
		--volume /tmp/.X11-unix:/tmp/.X11-unix:rw \
		--volume /etc/alsa:/etc/alsa:ro \
		--volume /usr/share/alsa:/usr/share/alsa:ro \
		--volume $(HOME)/.config/pulse:/home/$(USER_NAME)/.config/pulse:rw \
		--volume /run/user/$(USER_UID)/pulse/native:/run/user/$(USER_UID)/pulse/native:rw \
		--env PULSE_SERVER=unix:/run/user/$(USER_UID)/pulse/native \
		--volume $(HOST_PATH):/apps:rw \
		--gpus all \
		--volume /dev/dri:/dev/dri \
		--user $(USER_UID):$(USER_GROUP_GID) \
		--group-add $(DOCKER_GID) \
		$(IMAGE_NAME) /bin/bash


# testing runtime provisioning for use with pulling the container from Quay
# add --device for /dev/usb/ubikey-whatever?
runx2env:
	@SSH_FORWARD=""; \
	if [ -n "$$SSH_AUTH_SOCK" ]; then \
		SSH_FORWARD="--env SSH_AUTH_SOCK=$$SSH_AUTH_SOCK --volume $$SSH_AUTH_SOCK:$$SSH_AUTH_SOCK"; \
	else \
		echo "⚠️  SSH_AUTH_SOCK not set on host; you will need to mount ~/.ssh manually or start an ssh-agent."; \
	fi; \
	docker run -it --rm --shm-size=1g \
		--name $(CONTAINER_NAME) \
		--hostname $(IMAGE_NAME) \
		--env DISPLAY=$(DISPLAY) \
		--env USER_UID=$(USER_UID) \
		--env USER_GROUP_GID=$(USER_GROUP_GID) \
		--env USER_GROUP_NAME=$(USER_GROUP_NAME) \
		--env USER_NAME=$(USER_NAME) \
		--env USER_SHELL=$(USER_SHELL) \
		--env USER_HOME=$(USER_HOME) \
		--env PULSE_SERVER=unix:/run/user/$(USER_UID)/pulse/native \
		$$SSH_FORWARD \
		--volume ${USER_HOME}:/mnt/${USER_HOME}:ro \
		--volume ${USER_HOME}/.kiro:/mnt/${USER_HOME}/.kiro:rw \
		--volume ${USER_HOME}/.config/Kiro:/mnt/${USER_HOME}/.config/Kiro:rw \
		--volume /tmp/.X11-unix:/tmp/.X11-unix:rw \
		--volume /etc/alsa:/etc/alsa:ro \
		--volume /usr/share/alsa:/usr/share/alsa:ro \
		--volume $(HOME)/.config/pulse:/home/$(USER_NAME)/.config/pulse:rw \
		--volume /run/user/$(USER_UID)/pulse/native:/run/user/$(USER_UID)/pulse/native:rw \
		--volume $(HOST_PATH):/apps:rw \
		--gpus all \
		--volume /dev/dri:/dev/dri \
		--group-add $(DOCKER_GID) \
		$(IMAGE_NAME)

# write a comment for this make target
# similar to runx2env but uses --user to run as host user directly
# this requires that the container user is pre-provisioned to match host user
#  * X11 forwarding
#  * PulseAudio/alsa forwarding - could maybe be symlinks to /mnt/$USER_HOME in container?
#  * App mounting - or data directory for work in continer
#  * GPU passthrough
#  * mount user home from host as /mnt/$USER_HOME read-only
#  * subdirectories from host:$HOME
#  * forward group for Docker socket if needed
#  * mount ~/.kiro RW for Kiro settings persistence
#  * mount ~/.config/Kiro RW for Kiro settings persistence
#  * entrypoint provisions user/group at runtime so user names match in container and host
runx2user:
	@SSH_FORWARD=""; \
	if [ -n "$$SSH_AUTH_SOCK" ]; then \
		SSH_FORWARD="--env SSH_AUTH_SOCK=$$SSH_AUTH_SOCK --volume $$SSH_AUTH_SOCK:$$SSH_AUTH_SOCK"; \
	else \
		echo "⚠️  SSH_AUTH_SOCK not set on host; you will need to mount ~/.ssh manually or start an ssh-agent."; \
	fi; \
	docker run -it --rm --shm-size=1g \
		--user $(id -u):$(id -g) \
		--name $(CONTAINER_NAME) \
		--hostname $(IMAGE_NAME) \
		--env DISPLAY=$(DISPLAY) \
		--env USER_UID=$(USER_UID) \
		--env USER_GROUP_GID=$(USER_GROUP_GID) \
		--env USER_GROUP_NAME=$(USER_GROUP_NAME) \
		--env USER_NAME=$(USER_NAME) \
		--env USER_SHELL=$(USER_SHELL) \
		--env USER_HOME=$(USER_HOME) \
		--env PULSE_SERVER=unix:/run/user/$(USER_UID)/pulse/native \
		$$SSH_FORWARD \
		--volume ${USER_HOME}:/mnt/${USER_HOME}:ro \
		--volume ${USER_HOME}/.kiro:/mnt/${USER_HOME}/.kiro:rw \
		--volume ${USER_HOME}/.config/Kiro:/mnt/${USER_HOME}/.config/Kiro:rw \
		--volume /tmp/.X11-unix:/tmp/.X11-unix:rw \
		--volume /etc/alsa:/etc/alsa:ro \
		--volume /usr/share/alsa:/usr/share/alsa:ro \
		--volume $(HOME)/.config/pulse:/home/$(USER_NAME)/.config/pulse:rw \
		--volume /run/user/$(USER_UID)/pulse/native:/run/user/$(USER_UID)/pulse/native:rw \
		--volume $(HOST_PATH):/apps:rw \
		--gpus all \
		--volume /dev/dri:/dev/dri \
		--group-add $(DOCKER_GID) \
		$(IMAGE_NAME)



# ----------------------------------------------------------------------
# Run inside Xephyr virtual X11 server
# ----------------------------------------------------------------------
xrunx:
	Xephyr :1 -ac -screen 1280x720 & \
	docker run -it --rm \
		--env DISPLAY=:1 \
		--env USER=$(USER_NAME) \
		--volume /tmp/.X11-unix:/tmp/.X11-unix:rw \
		--volume $(HOST_PATH):/app:rw \
		--volume /etc/alsa:/etc/alsa:ro \
		--volume /usr/share/alsa:/usr/share/alsa:ro \
		--volume $(HOME)/.config/pulse:/home/$(USER_NAME)/.config/pulse:rw \
		--volume /run/user/$(USER_UID)/pulse/native:/run/user/$(USER_UID)/pulse/native:rw \
		--env PULSE_SERVER=unix:/run/user/$(USER_UID)/pulse/native \
		--user $(USER_UID):$(USER_GROUP_GID) \
		--group-add $(DOCKER_GID) \
		$(IMAGE_NAME) /bin/bash

# vim: set ts=3 sw=3 tw=0 noet :




