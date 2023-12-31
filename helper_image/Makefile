# Image URL to use all building/pushing image targets
IMG ?= ghcr.io/nearnodeflash/nnf-integration-test-helper

# CONTAINER_TOOL defines the container tool to be used for building images.
# Be aware that the target commands are only tested with Docker which is
# scaffolded by default. However, you might want to replace it to use other
# tools. (i.e. podman)
CONTAINER_TOOL ?= docker

.PHONY: docker-build
docker-build: VERSION ?= $(shell cat ../.version)
docker-build: .version ## Build docker image with the manager.
	$(CONTAINER_TOOL) build -t ${IMG}:${VERSION} .

.PHONY: docker-push
docker-push: VERSION ?= $(shell cat ../.version)
docker-push: .version ## Push docker image with the manager.
	$(CONTAINER_TOOL) push ${IMG}:${VERSION}

.PHONY: kind-push
kind-push: VERSION ?= $(shell cat ../.version)
kind-push: .version ## Push docker image to kind
	kind load docker-image ${IMG}:${VERSION}

# PLATFORMS defines the target platforms for the manager image be built to provide support to multiple
# architectures. (i.e. make docker-buildx IMG=myregistry/mypoperator:0.0.1). To use this option you need to:
# - be able to use docker buildx. More info: https://docs.docker.com/build/buildx/
# - have enabled BuildKit. More info: https://docs.docker.com/develop/develop-images/build_enhancements/
# - be able to push the image to your registry (i.e. if you do not set a valid value via IMG=<myregistry/image:<tag>> then the export will fail)
# To adequately provide solutions that are compatible with multiple platforms, you should consider using this option.
PLATFORMS ?= linux/arm64,linux/amd64,linux/s390x,linux/ppc64le
.PHONY: docker-buildx
docker-buildx: VERSION ?= $(shell cat ../.version)
docker-buildx: .version ## Build and push docker image for the manager for cross-platform support
	# copy existing Dockerfile and insert --platform=${BUILDPLATFORM} into Dockerfile.cross, and preserve the original Dockerfile
	sed -e '1 s/\(^FROM\)/FROM --platform=\$$\{BUILDPLATFORM\}/; t' -e ' 1,// s//FROM --platform=\$$\{BUILDPLATFORM\}/' Dockerfile > Dockerfile.cross
	- $(CONTAINER_TOOL) buildx create --name project-v3-builder
	$(CONTAINER_TOOL) buildx use project-v3-builder
	- $(CONTAINER_TOOL) buildx build --push --platform=$(PLATFORMS) --tag ${IMG}:${VERSION} -f Dockerfile.cross .
	- $(CONTAINER_TOOL) buildx rm project-v3-builder
	rm Dockerfile.cross

.PHONY: .version
.version:
	make -C .. .version
