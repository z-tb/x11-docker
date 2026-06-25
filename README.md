# Dockerized X11 Environment for LLM/plugin isolation

This project provides a Dockerized development environment capable of running X11 graphical applications from within the container. This allows for some sort of a security boundary around the appliation and data it has access to. I primarly use this as a DevOps environment so much of the tooling to support that work is included. Various LLM environments like Amazon Kiro IDE can be pulled in during build time. VS Code is pulled in which gives some isolation around their problematic plugin ecosystem. Much of this project was developed using LLM tooling.

The environment supports:
* Host or virtual X11 forwarding
* GPU passthrough (if available, Kiro branch only)
* Volume mounting for persistence
* Optional IDE/LLM tooling (Kiro, Claude, Cursor, VS Code, etc)

This started as a project using [Xephyr](https://www.x.org/archive/X11R7.5/doc/man/man1/Xephyr.1.html#toc7) for a dedicated X display which is faster than VNC, but difficult to use cut-and-paste with. Using `ssh -X` to display remote X apps is fine too, but there can be some limitations and latency with the compression and ciphers. The X11 pass-through was the next idea so I've split this into two branches. It's really designed for those who need a consistent X11 environment (or one managed by a security team) for testing, development, or experimentation.  I am not sure this will work with Windows or Mac. It's more likely with Xephyr, less likely with X11 sockets.

Sound support was originally available from the container also but it was added as a curiosity rather than out of need and haven't maintained it.

---

## Purpose / Security-minded rationale

This setup is designed for better isolation of applications and data instead of just running an application blindly on a host system and hoping everything is fine (you know, the way we've been doing it). Malicious extensions and plugins are becoming more common, and running an AI stack within easy reach of data is becoming commonplace. This project attempts to narrow the opportunities for those attack surfaces by isolating the data and application runtime inside a container.  

That said, this is still subject to all the regular foot‑guns of Docker. Some steps that are taken to remedy some of the common docker problems:
* A user account is created in the container using the build user UID/GID/USER so starting the container isn't just a root shell.
* At runtime, the user running the container gets their home directory mounted (mostly) read‑only under `/mnt/home/$USER` for easier use of persistent data, permissions, user, group, etc.
* The `~/.kiro` directory is mounted read‑write for persistence, as is the `/apps` directory.
* The `sudo` package is installed to make it easier to administer/experiment/investigate inside the container

Be aware Docker itself introduces attack surfaces that could be exercised if malicious software runs inside the container; these vectors are becoming easier to exploit as automation and AI tools improve. Having isolation and consistency is a good first step for safe development workflows, but it is not a complete security boundary. Still, it's better than just trusting fate.

All this being what it is, there are two notable security related work-arounds needed to get Kiro to run in the container:
* The Chromium startup script is modified to start using `--no-sandbox`
* Kiro must be started using `--no-sandbox` (or use the `ks` alias defined in `/etc/bash.bashrc`)

Kiro uses Chromium for sign-on but the only available Chromium package on Ubuntu is a "Snap" which doesn't work in the container and has it's own set of security issues anyway. To get around this, I added the [Xtradb](https://launchpad.net/~xtradeb/+archive/ubuntu/apps) repo in the container and pull in the Chromium package from there. Chromium is super dependendent on system features which don't work the same way in Docker without turning the container into little more than a root shell so unless there's a way to configure Kiro to use firefox instead, this "works". I would not recommend using Chromium in the container for anything else besides logging into Kiro. If it pops up for some reason, like installing a Kiro exension, be super careful. 

Kiro must be started with `kiro --no-sandbox` for the same reasons above. Simply running `kiro` will just get you a blank stare from your terminal.

Symlinks are connected in the container from `/mnt/home/$USER` to `$HOME` which Kiro needs to maintain persistence. This way plugins and things for Kiro won't have to be installed every time you start the container. Some other directories (`.config/pulse`) are volume-mounted R/W on the R/O volume mount for `/mnt/home/$USER`. This allows for some pieces of $HOME on the host to be written to, but the majority of $HOME on the host remains read-only, or mostly ephemeral. Those symlinks are created from `/etc/bash.bashrc` so see the Dockerfile if you want to edit the source file to disable them.

I should mention the `vcode` directory contains a shell script you can drop into your path that will give you some single-instance usability of the containerized install of VS Code. It's not exactly perfect but will work for simple edits.  It does gymnastics with the runtime arguments and volume mounts to provide some amount of sanity and persistence, if needed. There is room to build this out.  I use it for one-shot edits one a directory of files or single files when primarly working at the command line.  

Lastly, there are many ways to butcher docker security in the interest of increasing usability. Custom [Seccomp profiles](https://docs.docker.com/engine/security/seccomp/) seem like the most [favorable and granular](https://stackoverflow.com/questions/76833201/how-to-run-chrome-securely-in-docker) method so there are indeed other ways to cross this bridge.

---

## Features

* Non-root user created in the container, matching host UID/GID to avoid permission issues.
* Passwordless sudo for the non-root user (adjustable if you prefer).
* Optional installation of various add-ons eg: Amazon Kiro IDE (`WITH_KIRO=1`).
* Forward X11 display to host
* GPU passthrough support via Docker `--gpus all`.
* Volume mounts for `/apps`, home directories, and other persistent configuration.

**Home directory mounts and symlinks (persistence):**
* The build process creates a user inside the container with the same UID/GID as the builder.
* The container expects the build user's home to be mounted under `/mnt/$USER_HOME` (host → container). The README/Makefile symlinks point the container user to those mount targets.
* Symlinks created in the container. See `etc/bash.bashrc` for implementation (example):
  * `~/.ssh` → `/mnt/$USER_HOME/.ssh` (intended to be mounted **read‑only** `:ro` for safety)
* The `/apps` directory inside the container is mounted from the host (host `$HOME/apps` → container `/apps`) and is expected to be **read‑write** `:rw` so you can edit/build projects there.
* Persistence and access semantics depend entirely on how you mount the host directories when running the container — some mounts in the examples are intended to be `:ro` and others `:rw`. Verify and adjust your run target flags to match your security and workflow needs.
* The Makefile includes a series of variables prefixed with "WITH_". These are intended to enable/disable (1/0) the feature they reference.  If you want to maintain a persistent configuration for these, you can initialize .make in the current directory to declare what you want enabled or disabled. This allows future pulls not to conflict with changes made directly to the Makefile.  You can double check your config with `make info`

**Important:** The host-side `$HOST_PATH` ($HOME/apps) directory declared in the Makefile **must exist** before running `make runm`, `make runx`, `make runx2` or `make xrunx` — Docker will create an empty directory when binding a host path that does not exist, but failing to intentionally create/prepare it may lead to surprises.

---

## Prerequisites

* Docker installed on the host
* Optional NVIDIA GPU with `nvidia-container-toolkit` installed for GPU passthrough

---

## Building the Docker Image

Build the image with:

```bash
make build
```

This creates an image named `x11-image:latest`.

To rebuild without cache:

```bash
make rebuild
```

---

## Running the Docker Container

### 1. Interactive shell (basic)

```bash
make run
```

Starts a container named `x11-test` with a bash shell.

---

## Stopping and Cleaning

Stop the running container:

```bash
make stop
```

Remove container and image:

```bash
make clean
```

---

## Notes & tips

* The Dockerfile targets **Ubuntu 24.04**.
* Kiro IDE installation is optional and controlled via `WITH_KIRO` build argument in the Makefile.
* Symlinks inside the container point to `/mnt/$USER_HOME/*` targets; the security and persistence semantics follow how you mount those host paths (read‑only vs read‑write). Double‑check your `docker run` flags if you need stricter controls.
* If you do not want `sudo` in the container, remove it from the Dockerfile or adjust the created sudoers file — but remember many troubleshooting tasks become easier with it available.
* Running a full desktop environment in Docker is unconventional — treat this as a reproducible development/testing environment rather than a hardened production appliance.
* GPU passthrough requires proper host-side configuration (nvidia drivers, `nvidia-container-toolkit`, etc.).

---

## Makefile Targets Summary

| Target      | Description |
|-------------|------------|
| `build`     | Build Docker image with default args |
| `rebuild`   | Build Docker image without cache |
| `run`       | Run container interactively |
| `stop`      | Stop container |
| `clean`     | Remove container and image |
| `connect`   | Start interactive shell on running container |
| `push`      | Push container to Dockerhub |
| `info`      | Show Makefile target info |

---

