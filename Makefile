SHELL:=/bin/bash
.DEFAULT_GOAL := help

include .make/help.mk
include .make/detect_ro.mk

# make sure we enable BuildKit
export DOCKER_BUILDKIT=1

# env variables also used by Jenkins
# intentionally set to non-production values for use during local dev
IMAGE_REGISTRY ?= artifactory.myorg.com:9002
IMAGE_NAME     ?= myteam/myapp
IMAGE_TAG      ?= dev

##
### main targets (containerized)
##

build.binary: ## build the binary
	docker build . --target bin --output type=local,dest=bin/

build.container: ## build the container
	docker build -t ${IMAGE_REGISTRY}/${IMAGE_NAME}:${IMAGE_TAG} .

.PHONY: test
test: ## run all tests
	docker build . --target lint
	docker build . --target coverage --output type=local,dest=bin/
	docker build . --build-arg TEST_SLOW_PATH --target test-bats --progress=plain

##
### bare metal targets
##

build.local: ## compile binary
	go build -o ${WRITEABLE_PATH}/query src/query.go

test.golang.local: ## run golang unit tests
	go test -v -coverprofile=${WRITEABLE_PATH}/cover.out ./...

test.bats.local: ## run bash-based tests
	bats test/*.bats
