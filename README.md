# Dockerized X11 Environment with PulseAudio, GPU, and Kiro IDE Support

This project provides a Dockerized development environment capable of running X11 graphical applications, desktop environments (Cinnamon or LXDE), and optionally the Amazon Kiro IDE. The environment supports running applications inside a Docker container with:

* Host or virtual X11 forwarding (Xephyr or host display - this depends on branch)
* PulseAudio/ALSA audio support
* GPU passthrough (if available, Kiro branch only)
* Volume mounting for persistence
* Optional Kiro IDE installation (Kiro branch)

This started as a project using Xephyr for a dedicated X display which is faster than VNC, but difficult to use cut-and-paste with. Using `ssh -X` to display remote X apps is fine too, but there can be some limitations and latency with the compression and ciphers. The X11 pass-through was the next idea so I've split this into two branches. It's really designed for those who need a consistent X11 environment (or one managed by a security team) for testing, development, or experimentation.  I am not sure this will work with Windows or Mac. It's more likely with Xephyr, less likely with X11 sockets.

---

## Purpose / Security-minded rationale

This setup is designed for better isolation of applications and data instead of just running an application blindly on a host system and hoping everything is fine (you know, the way we've been doing it). Malicious extensions and plugins are becoming more common vectors for compromise, and running an AI stack within easy reach of data not intended for the LLM has become commonplace. This project attempts to narrow the opportunities for those attack surfaces by isolating the data and application runtime inside a container.  

That said, this is still subject to all the regular foot‑guns of Docker. The user who builds the container has their UID replicated inside the container, and when the container is started the build user's home directory is mounted (mostly) read‑only under `/mnt/home/$USER`. The `~/.kiro` directory is mounted read‑write for persistence, as is the `/apps` directory. The `sudo` package is installed to make it easier for the user to administer the container for experimentation or investigation — this is an obvious opportunity for compromise, so you may wish to disable it. Be aware Docker itself introduces additional attack surfaces that could be exercised if malicious software runs inside the container; these vectors are becoming easier to exploit as automation and AI tools improve. Having isolation and consistency is a good first step for safe development workflows, but it is not a complete security boundary.

---

## Features

* Non-root user created in the container, matching host UID/GID to avoid permission issues.
* Passwordless sudo for the non-root user (adjustable if you prefer).
* Cinnamon and LXDE desktops installed because I couldn't make up my mind.
* Optional installation of Amazon Kiro IDE (`WITH_KIRO=1`).
* Forward X11 display and PulseAudio for graphical and audio applications.
* GPU passthrough support via Docker `--gpus all`.
* Volume mounts for `/apps`, home directories, and Kiro configuration.

**Home directory mounts and symlinks (persistence behavior):**
* The build process creates a user inside the container with the same UID/GID as the builder.
* The container expects the build user's home to be mounted under `/mnt/$USER_HOME` (host → container). The README/Makefile symlinks point the container user to those mount targets.
* Symlinks created in the container (examples):
  * `~/.ssh` → `/mnt/$USER_HOME/.ssh` (intended to be mounted **read‑only** `:ro` for safety)
  * `~/.gitconfig` → `/mnt/$USER_HOME/.gitconfig` (commonly mounted **read‑only** `:ro`)
  * `~/.kiro` → `/mnt/$USER_HOME/.kiro` (mounted **read‑write** `:rw` to persist Kiro settings)
* The `/apps` directory inside the container is mounted from the host (host `./apps` → container `/apps`) and is expected to be **read‑write** `:rw` so you can edit/build projects there.
* Persistence and access semantics depend entirely on how you mount the host directories when running the container — some mounts in the examples are intended to be `:ro` and others `:rw`. Verify and adjust your run target flags to match your security and workflow needs.

**Important:** The host-side `apps` directory **must exist** before running `make runm`, `make runx`, `make runx2` or `make xrunx` — Docker will create an empty directory when binding a host path that does not exist, but failing to intentionally create/prepare it may lead to surprises.

---

## Prerequisites

* Docker 24+ installed on the host
* Xephyr installed on the host (for Xephyr branch/`xrunx` target) 
* PulseAudio running on the host (for audio forwarding)
* Optional NVIDIA GPU with `nvidia-container-toolkit` installed for GPU passthrough (Kiro branch)

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

### 2. Volume-mounted shell

```bash
make runm
```

Mounts the host `./apps` folder to `/apps` inside the container for persistent work and starts a bash shell. Ensure `./apps` exists on the host before running.

---

## Running with X11

### Host X11 display

```bash
make runx
```

* Forwards the host `DISPLAY` into the container.
* Forwards PulseAudio/ALSA for audio (example mounts shown in Makefile).
* Runs the container as your host UID/GID to reduce permission friction.

### Host X11 + GPU + Kiro IDE

```bash
make runx2
```

* Forwards X11 and PulseAudio/ALSA
* Enables GPU passthrough (`--gpus all`)
* Mounts the home directory and Kiro config for persistence
* Installs Kiro IDE when `WITH_KIRO=1` is set in the Makefile

---

## Running in a Xephyr virtual X11 server

```bash
make xrunx
```

* Starts a Xephyr virtual display (`:1`) with resolution 1280x720
* Forwards X11 and PulseAudio to the container
* Useful to isolate the container desktop from the host desktop environment
* Adjust resolution after startup with:

```bash
xrandr --output default --mode 1280x720
```

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
| `runm`      | Run container with `/apps` volume mount (host `./apps` → container `/apps`) |
| `runx`      | Run container with host X11 and PulseAudio |
| `runx2`     | Run container with X11, PulseAudio, GPU, and optional Kiro |
| `xrunx`     | Run container inside Xephyr virtual X11 server |
| `stop`      | Stop running container |
| `clean`     | Remove container and image |

---

If you'd like, I can also add a short "Quick Start" at the top showing the minimal sequence of commands for a new user (build → runm → open Cinnamon), or generate a small diagram that visualizes which mounts are `:ro` vs `:rw` and how the symlinks resolve to `/mnt/$USER_HOME`. Which would you prefer?

