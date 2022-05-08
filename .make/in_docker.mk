# make sure we enable BuildKit
export DOCKER_BUILDKIT=1

# in_docker convenience function
# Usage: $(call in_docker,[extra args] <container> <command>)
define in_docker
	docker run -it --rm --user $(shell id -u):$(shell id -g) --mount type=bind,source=${CURDIR},target=/mnt --workdir /mnt ${1}
endef

# for more convenience using the golang container, we find and mount the local module cache

CONTAINER_GOLANG = golang:1.18