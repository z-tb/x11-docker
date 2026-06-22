# ----------------------------------------------------------------------
# Makefile for building and running X11 + PulseAudio + Kiro IDE Docker
# ----------------------------------------------------------------------

# .make - Your own preferences can be created locally so future pull doesn't overwrite
# WITH_KIRO        ?= 1
# WITH_AWS_CLI     ?= 0
# WITH_TOFU        ?= 0
# ...
-include $(CURDIR)/.make

.PHONY: build rebuild run runm stop clean connect runx runx2 xrunx info

# Image / container names
IMAGE_NAME       := x11-image
CONTAINER_NAME   := x11-test

# Host and container paths
HOST_PATH        := $(HOME)/apps/
CONT_APP_MNT     := /apps

# User info
USER_UID         := $(shell id -u)
USER_GROUP_GID   := $(shell id -g)
USER_GROUP_NAME  := $(shell id -gn)
USER_NAME        := $(shell id -un)
USER_SHELL       := /bin/bash
USER_HOME        := $(HOME)

# Docker group for socket forwarding - if using Docker inside container
DOCKER_GID       := $(shell getent group docker | cut -d: -f3)

# Optional installation flags
WITH_KIRO        ?= 1
WITH_AWS_CLI     ?= 1
WITH_TOFU        ?= 1
WITH_CURSOR      ?= 0
WITH_VSCODE      ?= 1
WITH_CLAUDE      ?= 0
WITH_BREW        ?= 0
WITH_SPACECTL    ?= 0
WITH_GHCLI       ?= 0

# ----------------------------------------------------------------------
# supplemental groups for runtime user add to the container user
# use current user groups, or define your own here
# ----------------------------------------------------------------------
SUPP_GROUPS := $(shell id -Gn | tr ' ' '\n' | while read g; do \
    gid=$$(getent group "$$g" | cut -d: -f3); \
    [ -n "$$gid" ] && printf "%s:%s," "$$g" "$$gid"; \
done | sed 's/,$$//')


# Set your Docker Hub username, or override on CLI: make push DOCKER_USER=foo
DOCKER_USER ?= $(USER_NAME)

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
		--build-arg WITH_BREW=$(WITH_BREW) \
		--build-arg WITH_SPACECTL=$(WITH_SPACECTL) \
		--build-arg WITH_GHCLI=$(WITH_GHCLI) \
		-t $(IMAGE_NAME):latest -f ./Dockerfile .

# Rebuild the image without cache
# Useful when Dockerfile changes or when forcing a clean rebuild.
rebuild: info
	docker build --no-cache --progress=plain\
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
		--build-arg WITH_BREW=$(WITH_BREW) \
		--build-arg WITH_SPACECTL=$(WITH_SPACECTL) \
		--build-arg WITH_GHCLI=$(WITH_GHCLI) \
		-t $(IMAGE_NAME):latest -f ./Dockerfile .

# ----------------------------------------------------------------------
# Basic container run targets
# ----------------------------------------------------------------------

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
	@echo "SUPP_GROUPS=$(SUPP_GROUPS)"
	@echo "WITH_KIRO=$(WITH_KIRO)"
	@echo "WITH_AWS_CLI=$(WITH_AWS_CLI)"
	@echo "WITH_TOFU=$(WITH_TOFU)"
	@echo "WITH_CURSOR=$(WITH_CURSOR)"
	@echo "WITH_VSCODE=$(WITH_VSCODE)"
	@echo "WITH_CLAUDE=$(WITH_CLAUDE)"
	@echo "WITH_BREW=$(WITH_BREW)"
	@echo "WITH_SPACECTL=$(WITH_SPACECTL)"
	@echo "WITH_GHCLI=$(WITH_GHCLI)"
	@echo


# run container like runx2 but with supplemental groups passed in using SUPP_GROUPS variable
run: info
	@SSH_FORWARD=""; \
	if [ -n "$$SSH_AUTH_SOCK" ]; then \
		SSH_FORWARD="--env SSH_AUTH_SOCK=$$SSH_AUTH_SOCK --volume $$SSH_AUTH_SOCK:$$SSH_AUTH_SOCK"; \
	else \
		echo "⚠️ SSH_AUTH_SOCK not set on host; mount ~/.ssh manually or start an ssh-agent."; \
	fi; \
	docker run -it --rm --shm-size=1g \
		--ipc=host \
		--name $(CONTAINER_NAME) \
		--hostname $(IMAGE_NAME) \
		--env DISPLAY=$(DISPLAY) \
		--env USER_UID=$(USER_UID) \
		--env USER_GROUP_GID=$(USER_GROUP_GID) \
		--env USER_GROUP_NAME=$(USER_GROUP_NAME) \
		--env USER_NAME=$(USER_NAME) \
		--env USER_SHELL=$(USER_SHELL) \
		--env USER_HOME=$(USER_HOME) \
		--env USER_GROUPS='$(SUPP_GROUPS)' \
		$$SSH_FORWARD \
		--volume ${USER_HOME}/.kiro:${USER_HOME}/.kiro:rw \
		--volume ${USER_HOME}/.config/Kiro:${USER_HOME}/.config/Kiro:rw \
		--volume ${USER_HOME}/.gitconfig:${USER_HOME}/.gitconfig:ro \
		--volume /tmp/.X11-unix:/tmp/.X11-unix:rw \
		--volume $(HOST_PATH):/apps:rw \
      	--volume /etc/localtime:/etc/localtime:ro \
      	--volume /etc/timezone:/etc/timezone:ro \
		--gpus all \
		--volume /dev/dri:/dev/dri \
		$(IMAGE_NAME)



push: ## Login, tag, and push image to Docker Hub
	@echo "==> Logging in to Docker Hub as $(DOCKER_USER)"
	docker login -u $(DOCKER_USER)

	@echo "==> Tagging image: $(IMAGE_NAME) -> $(DOCKER_USER)/$(IMAGE_NAME):latest"
	docker tag $(IMAGE_NAME):latest $(DOCKER_USER)/$(IMAGE_NAME):latest

	@echo "==> Pushing image to Docker Hub"
	docker push $(DOCKER_USER)/$(IMAGE_NAME):latest

	@echo "==> Push complete!"

# vim: set ts=3 sw=3 tw=0 noet :
