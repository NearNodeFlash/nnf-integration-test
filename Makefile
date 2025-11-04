# Run in parallel with P number of processes (workflows) at a time
# To run all the simple tests, 2 at a time:
# 	$ P=2 make simple
ifdef P
PARALLEL_OPT:=-procs=${P}
endif

# Add go bin to path (for ginkgo)
export PATH := $(HOME)/go/bin:$(PATH)

# Base command to start the tests with ginkgo
GINKGO_RUN?=CGO_ENABLED=0 ginkgo run ${PARALLEL_OPT} --v

all: fmt vet

.PHONY: fmt
fmt:
	go fmt ./...

.PHONY: vet
vet:
	go vet ./...

# TODO: would be nice to tie this to a script that also deletes all the workflows and makes sure nothing is left over
.PHONY: clean
clean:
	kubectl delete namespace nnf-system-needs-triage --ignore-not-found

.PHONY: init
init:
	./ginkgo_install.sh

# Run all the tests
.PHONY: test
test:
	${GINKGO_RUN} .

# Alias for all the tests
.PHONY: full
full: test

# Run one test to ensure system is in working order
.PHONY: sanity
sanity:
	${GINKGO_RUN} --label-filter='simple && xfs' .

# Test all 4 filesytems
.PHONY: simple
simple:
	${GINKGO_RUN} --label-filter='simple' .

# Run Data Movement Tests (i.e. copy_in/copy_out). This does not test copy offload API.
.PHONY: dm
dm:
	${GINKGO_RUN} --label-filter='dm' .

# Run container tests
.PHONY: container
container:
	${GINKGO_RUN} --label-filter='container' .

# Run gfs2 fence test
.PHONY: gfs2_fence
gfs2_fence:
	${GINKGO_RUN} --label-filter='gfs2_fence' .

.PHONY: .version
.version: ## Uses the git-version-gen script to generate a tag version
	./git-version-gen --fallback `git rev-parse HEAD` > .version
