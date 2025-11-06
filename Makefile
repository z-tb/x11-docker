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
USER_SHELL       := $(SHELL)
USER_HOME        := $(HOME)

# Docker group for socket forwarding
DOCKER_GID       := $(shell getent group docker | cut -d: -f3)

# Optional installation flags
WITH_KIRO        ?= 1

# ----------------------------------------------------------------------
# Build targets
# ----------------------------------------------------------------------

build:
	docker build \
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

# ----------------------------------------------------------------------
# Run with X11 and PulseAudio support (host display)
# ----------------------------------------------------------------------

runx:
	docker run -it --rm \
		-e DISPLAY=$(DISPLAY) \
		-e USER=$(USER_NAME) \
		-v /tmp/.X11-unix:/tmp/.X11-unix:rw \
		-v $(HOST_PATH):/apps:rw \
		-v /etc/alsa:/etc/alsa:ro \
		-v /usr/share/alsa:/usr/share/alsa:ro \
		-v $(HOME)/.config/pulse:/home/$(USER_NAME)/.config/pulse:rw \
		-v /run/user/$(USER_UID)/pulse/native:/run/user/$(USER_UID)/pulse/native:rw \
		-e PULSE_SERVER=unix:/run/user/$(USER_UID)/pulse/native \
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
runx2:
	docker run -it --rm --shm-size=1g \
		--name $(CONTAINER_NAME) \
		--hostname $(IMAGE_NAME) \
		-e DISPLAY=$(DISPLAY) \
		-e USER=$(USER_NAME) \
		-v ${USER_HOME}:/mnt/${USER_HOME}:ro \
		-v ${USER_HOME}/.kiro:/mnt/${USER_HOME}/.kiro:rw \
		-v ${USER_HOME}/.config/Kiro:/mnt/${USER_HOME}/.config/Kiro:rw \
		-v /tmp/.X11-unix:/tmp/.X11-unix:rw \
		-v /etc/alsa:/etc/alsa:ro \
		-v /usr/share/alsa:/usr/share/alsa:ro \
		-v $(HOME)/.config/pulse:/home/$(USER_NAME)/.config/pulse:rw \
		-v /run/user/$(USER_UID)/pulse/native:/run/user/$(USER_UID)/pulse/native:rw \
		-e PULSE_SERVER=unix:/run/user/$(USER_UID)/pulse/native \
		-v $(HOST_PATH):/apps:rw \
		--gpus all \
		-v /dev/dri:/dev/dri \
		--user $(USER_UID):$(USER_GROUP_GID) \
		--group-add $(DOCKER_GID) \
		$(IMAGE_NAME) /bin/bash




# ----------------------------------------------------------------------
# Run inside Xephyr virtual X11 server
# ----------------------------------------------------------------------

xrunx:
	Xephyr :1 -ac -screen 1280x720 & \
	docker run -it --rm \
		-e DISPLAY=:1 \
		-e USER=$(USER_NAME) \
		-v /tmp/.X11-unix:/tmp/.X11-unix:rw \
		-v $(HOST_PATH):/app:rw \
		-v /etc/alsa:/etc/alsa:ro \
		-v /usr/share/alsa:/usr/share/alsa:ro \
		-v $(HOME)/.config/pulse:/home/$(USER_NAME)/.config/pulse:rw \
		-v /run/user/$(USER_UID)/pulse/native:/run/user/$(USER_UID)/pulse/native:rw \
		-e PULSE_SERVER=unix:/run/user/$(USER_UID)/pulse/native \
		--user $(USER_UID):$(USER_GROUP_GID) \
		--group-add $(DOCKER_GID) \
		$(IMAGE_NAME) /bin/bash

# vim: set ts=3 sw=3 tw=0 noet :
