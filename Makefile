IMAGE_NAME 	 	= x11-image
CONTAINER_NAME 	= x11-test
HOST_PATH 	    = ./app

build:
	docker build -t $(IMAGE_NAME) .

rebuild:
	docker build --no-cache -t $(IMAGE_NAME) .
run:
	docker run -it --name $(CONTAINER_NAME) $(IMAGE_NAME)

# run in Xephyr X11 environment
# start cinnamon with: cinnamon-session
# xrandr --output default --mode 1280x720
xrunx:
	Xephyr :1 -ac -screen 1280x720 & \
	docker run -it --rm \
	-e DISPLAY=:1 \
	-v /tmp/.X11-unix:/tmp/.X11-unix \
	-v "./app:/app/" \
	-v "/etc/alsa:/etc/alsa" \
	-v "/usr/share/alsa:/usr/share/alsa" \
	-v "$(HOME)/.config/pulse:/.config/pulse" \
	-v "/run/user/$(UID)/pulse/native:/run/user/$(UID)/pulse/native" \
	--env "PULSE_SERVER=unix:/run/user/$(UID)/pulse/native" \
	--user "$(id -u)" \
	$(IMAGE_NAME) /bin/bash

runx:
	docker run -it --rm \
	-e DISPLAY=$(DISPLAY) \
	-v /tmp/.X11-unix:/tmp/.X11-unix \
	-v "./app:/app/" \
	-v "/etc/alsa:/etc/alsa" \
	-v "/usr/share/alsa:/usr/share/alsa" \
	-v "$(HOME)/.config/pulse:/.config/pulse" \
	-v "/run/user/$(UID)/pulse/native:/run/user/$(UID)/pulse/native" \
	--env "PULSE_SERVER=unix:/run/user/$(UID)/pulse/native" \
	--user "$(id -u)" \
	$(IMAGE_NAME) /bin/bash

runm:
	docker run -it --rm -v ./app:/app/ ${IMAGE_NAME} /bin/bash

stop:
	docker stop $(CONTAINER_NAME)

clean:
	docker rm $(CONTAINER_NAME)
	docker rmi $(IMAGE_NAME)


# vim: set ts=3 sw=3 tw=0 noet :
