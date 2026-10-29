IMAGE ?= xlings-docker
TAG ?= dev
BASE_IMAGE ?= ubuntu:24.04
DEV_UID ?= 1000
DEV_GID ?= 1000
XLINGS_DEFAULT_MIRROR ?= GLOBAL
XLINGS_DOWNLOAD_BASE ?= https://github.com/openxlings/xlings/releases/download
PLATFORMS ?= linux/amd64,linux/arm64
XLINGS_VERSION ?= $(shell sed -n 's/^ARG XLINGS_VERSION=//p' Dockerfile)
NINJA_VERSION ?= 1.12.1

BUILD_ARGS = \
	--build-arg BASE_IMAGE=$(BASE_IMAGE) \
	--build-arg DEV_UID=$(DEV_UID) \
	--build-arg DEV_GID=$(DEV_GID) \
	--build-arg XLINGS_VERSION=$(XLINGS_VERSION) \
	--build-arg XLINGS_DOWNLOAD_BASE=$(XLINGS_DOWNLOAD_BASE) \
	--build-arg XLINGS_DEFAULT_MIRROR=$(XLINGS_DEFAULT_MIRROR)

.PHONY: help build smoke test build-multi push version clean

help:
	@printf '%s\n' \
		'build         build the image for the local platform' \
		'smoke         run image smoke tests' \
		'test          build + smoke' \
		'build-multi   build amd64 and arm64 without pushing' \
		'push          build amd64 and arm64 and push $(IMAGE):$(TAG)' \
		'version       print the pinned xlings version'

build:
	docker build $(BUILD_ARGS) -t $(IMAGE):$(TAG) .

smoke:
	IMAGE=$(IMAGE):$(TAG) XLINGS_VERSION=$(XLINGS_VERSION) NINJA_VERSION=$(NINJA_VERSION) \
		SMOKE_UID=$(DEV_UID) ./tests/smoke.sh

test: build smoke

build-multi:
	docker buildx build $(BUILD_ARGS) --platform $(PLATFORMS) -t $(IMAGE):$(TAG) .

push:
	docker buildx build $(BUILD_ARGS) --platform $(PLATFORMS) --push -t $(IMAGE):$(TAG) .

version:
	@printf '%s\n' '$(XLINGS_VERSION)'

clean:
	docker image rm -f $(IMAGE):$(TAG) >/dev/null 2>&1 || true
