IMAGE ?= ghcr.io/jmetdev/freeswitch-webex-lgw
TAG ?= latest
PLATFORMS ?= linux/amd64,linux/arm64
FREESWITCH_VERSION ?= v1.11.1

.PHONY: sync build build-local push run smoke-test shell

sync:
	./scripts/sync-config-to-runtime.sh

build:
	docker buildx build \
	  --platform $(PLATFORMS) \
	  --build-arg FREESWITCH_VERSION=$(FREESWITCH_VERSION) \
	  -t $(IMAGE):$(TAG) \
	  --push \
	  .

build-local:
	docker buildx build \
	  --platform linux/amd64 \
	  --build-arg FREESWITCH_VERSION=$(FREESWITCH_VERSION) \
	  -t $(IMAGE):$(TAG) \
	  --load \
	  .

push: build

run: sync
	docker compose up -d

smoke-test:
	./scripts/smoke-test.sh $(IMAGE):$(TAG)

shell: sync
	docker run --rm -it --net=host \
	  -e FS_PROFILE=webex \
	  -v "$$(pwd)/runtime/config:/etc/freeswitch" \
	  -v "$$(pwd)/runtime/logs:/var/log/freeswitch" \
	  -v "$$(pwd)/runtime/recordings:/var/lib/freeswitch/recordings" \
	  -v "$$(pwd)/runtime/fax:/var/spool/fax" \
	  $(IMAGE):$(TAG) /bin/bash
