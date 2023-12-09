# X11 Dockerized Environment with Xephyr

This project provides a Dockerized development environment capable of displaying X11 output within a Xephyr window. The environment includes LXDE, a lightweight X11 environment and Cinnamon, a more aesthetic, and resource intensive, desktop. 

The Dockerfile sets up a X11 based on the official Ubuntu 20.04 image. This includes a non-root user with sudo access (`tux`), support for running graphical applications, and the support software for the desktops. It is designed for developers who need a Dockerized GUI for testing and development purposes. 

Audio support was a consideration that crossed my mind, so incorporated a few elements into the Dockerfile to initiate the process. It needs more configuration to be functional.

Using the `xrunx` target will start a Xephyr window on the host, and bash shell in the container. All X output goes to the Xephyr window. Initially, I was using the host X server for displaying things but this can affect desktop resource themes, fonts, etc so I opted for Xephyr. There might be some X leftovers in the Makefile which aren't needed any more. If the Xephyr window is too big after starting `cinnamon-session`, use `xrandr` with something like `xrandr --output default --mode 1280x720` to de-biggen it.

## Dockerfile:

- Creates a non-root user (`tux`) with `/bin/bash` as the default shell.
- Grants sudo access to the `tux` user (need to use `newgrp` first for some reason I don't understand)
- Sets up a working directory at `/app` (shared between host and container if using volume mount target)
- Installs packages for X and some extras like vim and nano, chromium-browser, cinnamon, dbus, firefox, etc.
- Adds the `tux` user to the sudoers group with passwordless sudo access.
- Appends custom bash code from `/tmp/bashrc-addition` to `/etc/bash.bashrc`.
- Switches to the non-root user `tux` for the container shell.
- Specifies the default command to run when the container starts as `/bin/bash`.

Please note that running a full desktop environment inside a Docker container is unconventional and might have limitations depending on your environment and security policies. This Dockerfile is intended for experimentation, testing, and development purposes. Use it with caution and adapt it according to your specific requirements.
## Building the Docker Image

To build the Docker image, run the following command:

```bash
make build
```

This will create an image named `x11-image`.

## Rebuilding the Docker Image

If you need to rebuild the Docker image without using cached layers, use the following command:

```bash
make rebuild
```

## Running the Docker Container

To run the Docker container in an interactive mode, use the following command:

```bash
make run
```

This will start a container named `x11-test`. You can customize the container name by modifying the `CONTAINER_NAME` variable in the Makefile.

## Running in Xephyr X11 Environment

To run the Docker container in a Xephyr X11 environment with Cinnamon and a specific screen resolution (1280x720), use the following command:

```bash
make xrunx
```

This command starts Xephyr in the background, launches the Docker container with X11 display forwarding, and sets up necessary volume mounts. You can customize the screen resolution by modifying the `Xephyr` command in the Makefile.

## Running with Host Display

To run the Docker container using the host display, use the following command:

```bash
make runx
```

This command forwards the host display to the Docker container, allowing it to interact with the host X11 server.

## Running with Volume Mount

To run the Docker container with volume mounting, use the following command:

```bash
make runm
```

This command mounts the `./app` directory from the host to `/app/` in the container and opens a bash shell.

## Stopping the Docker Container

To stop the running Docker container, use the following command:

```bash
make stop
```

## Cleaning Up

To remove the Docker container and image, use the following command:

```bash
make clean
```
