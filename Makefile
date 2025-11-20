# ----------------------------------------------------------------------
# Makefile for building and running X11 + PulseAudio + Kiro IDE Docker
# ----------------------------------------------------------------------


.PHONY: build rebuild run runm stop clean connect runx runx2 xrunx info

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
WITH_CLAUDE      ?= 1


# ----------------------------------------------------------------------
# Build targets
# ----------------------------------------------------------------------

# Build the Docker image using cached layers (normal build)
# Passes host user information and optional install flags into the image.
build: info
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
		--build-arg WITH_CLAUDE=$(WITH_CLAUDE) \
		-t $(IMAGE_NAME):latest -f ./Dockerfile .

# Rebuild the image without cache
# Useful when Dockerfile changes or when forcing a clean rebuild.
rebuild: info
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
		--build-arg WITH_AWS_CLI=$(WITH_AWS_CLI) \
		--build-arg WITH_TOFU=$(WITH_TOFU) \
		--build-arg WITH_VSCODE=$(WITH_VSCODE) \
		--build-arg WITH_CURSOR=$(WITH_CURSOR) \
		--build-arg WITH_CLAUDE=$(WITH_CLAUDE) \
		-t $(IMAGE_NAME):latest -f ./Dockerfile .

# ----------------------------------------------------------------------
# Basic container run targets
# ----------------------------------------------------------------------

# Run the container normally (interactive, uses container's default CMD)
run: info
	docker run -it --name $(CONTAINER_NAME) $(IMAGE_NAME)

# Run the container with host apps mounted, auto-remove after exit
# Useful for quick testing with access to ./apps on the host.
runm: info
	docker run -it --rm -v $(HOST_PATH):/apps $(IMAGE_NAME) /bin/bash

# Stop container by name
stop:
	docker stop $(CONTAINER_NAME)

# Remove container and image (ignore errors)
clean:
	docker rm $(CONTAINER_NAME) || true
	docker rmi $(IMAGE_NAME) || true

# Connect to a running container with a shell
connect:
	docker exec -it ${CONTAINER_NAME} /bin/bash

info:
	@echo "===== MAKE VARS ====="
	@echo "USER_UID=$(USER_UID)"
	@echo "USER_GROUP_GID=$(USER_GROUP_GID)"
	@echo "USER_GROUP_NAME=$(USER_GROUP_NAME)"
	@echo "USER_NAME=$(USER_NAME)"
	@echo "USER_SHELL=$(USER_SHELL)"
	@echo "USER_HOME=$(USER_HOME)"
	@echo "DOCKER_GID=$(DOCKER_GID)"
	@echo "WITH_KIRO=$(WITH_KIRO)"
	@echo "WITH_AWS_CLI=$(WITH_AWS_CLI)"
	@echo "WITH_TOFU=$(WITH_TOFU)"
	@echo "WITH_CURSOR=$(WITH_CURSOR)"
	@echo "WITH_VSCODE=$(WITH_VSCODE)"
	@echo "WITH_CLAUDE=$(WITH_CLAUDE)"
	@echo

# ----------------------------------------------------------------------
# Run with X11 and PulseAudio support (host display)
# ----------------------------------------------------------------------

# Run container with X11 forwarding and PulseAudio support.
# Mounts host ALSA and PulseAudio paths and runs as host user.
runx: info
	docker run -it --rm \
		--user 1000:1000 \
		--env TARGET_UID=$(USER_UID) \
		--env TARGET_GID=$(USER_GROUP_GID) \
		--env DISPLAY=$(DISPLAY) \
		--env USER=$(USER_NAME) \
		--volume /tmp/.X11-unix:/tmp/.X11-unix:rw \
		--volume $(HOST_PATH):/apps:rw \
		--volume /etc/alsa:/etc/alsa:ro \
		--volume /usr/share/alsa:/usr/share/alsa:ro \
		--volume $(HOME)/.config/pulse:/home/$(USER_NAME)/.config/pulse:rw \
		--volume /run/user/$(USER_UID)/pulse/native:/run/user/$(USER_UID)/pulse/native:rw \
		--env PULSE_SERVER=unix:/run/user/$(USER_UID)/pulse/native \
		$(IMAGE_NAME) /bin/bash



# Run container exactly like runx2env, but running explicitly as the host
# user via --user UID:GID. This requires the container to already contain
# matching user and group entries or have runtime provisioning in entrypoint.
# Provides:
#  * X11 forwarding
#  * PulseAudio/ALSA forwarding
#  * GPU passthrough
#  * host $HOME mounted under /mnt
#  * RW Kiro config directories
#  * docker group forwarding
#  * SSH agent forwarding when available
runx2: info
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

etctest: info
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
		--env USER_GROUPS=$(USER_GROUPS) \
		$$SSH_FORWARD \
		--volume ${USER_HOME}/.kiro:${USER_HOME}/.kiro:rw \
		--volume ${USER_HOME}/.config/Kiro:${USER_HOME}/.config/Kiro:rw \
		--volume ${USER_HOME}/.gitconfig:${USER_HOME}/.gitconfig:ro \
		--volume /tmp/.X11-unix:/tmp/.X11-unix:rw \
		--volume $(HOST_PATH):/apps:rw \
		--gpus all \
		--volume /dev/dri:/dev/dri \
		--group-add $(DOCKER_GID) \
		$(IMAGE_NAME)

# ----------------------------------------------------------------------
# Run inside Xephyr virtual X11 server
# ----------------------------------------------------------------------

# Launch a nested X11 server via Xephyr (:1) and run the container inside it.
# Useful for isolating the container's GUI from the main desktop session.
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
		$(IMAGE_NAME) /bin/bash

# vim: set ts=3 sw=3 tw=0 noet :
