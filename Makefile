# Run in parallel with P number of processes (workflows) at a time
# To run all the simple tests, 2 at a time:
# 	$ P=2 make simple
ifdef P
PARALLEL_OPT:=-procs=${P}
endif

# Add go bin to path (for ginkgo)
export PATH := $(HOME)/go/bin:$(PATH)

# Base command to start the tests with ginkgo
GINKGO_RUN?=CGO_ENABLED=0 ginkgo run ${PARALLEL_OPT} --v --fail-fast

all: fmt vet

.PHONY: fmt
fmt:
	go fmt ./...

.PHONY: vet
vet:
	go vet ./...

# TODO: would be nice to tie this to a script that also deletes all the workflows and makes sure nothing is left over
# Clean up resources that may be left behind by interrupted test runs
.PHONY: clean
clean:
	@echo "Removing triage namespace..."
	kubectl delete namespace nnf-system-needs-triage --ignore-not-found
	@echo "Removing leftover UID verification pods..."
	kubectl delete pods -n default --ignore-not-found $$(kubectl get pods -n default --no-headers -o custom-columns=':metadata.name' 2>/dev/null | grep '^verify-uid-') 2>/dev/null; true
	@echo "Checking for persistent storage instances..."
	@psi=$$(kubectl get persistentstorageinstances -A --no-headers 2>/dev/null); \
	if [ -n "$$psi" ]; then \
		echo "WARNING: Persistent storage instances still exist. These require a destroy_persistent workflow to remove:" >&2; \
		echo "$$psi" >&2; \
	fi

.PHONY: init
init:
	./ginkgo_install.sh

# Run all the tests
.PHONY: test
test:
	@if kubectl config current-context 2>/dev/null | grep -q 'kind-'; then \
		echo "Detected kind cluster. Switching to 'make kind' (excludes global-lustre tests)." >&2; \
		$(MAKE) kind; \
	else \
		${GINKGO_RUN} . ; \
	fi

# Alias for all the tests
.PHONY: full
full: test

# Run tests compatible with a kind environment (excludes tests requiring real Lustre mounts)
.PHONY: kind
kind:
	${GINKGO_RUN} --label-filter='!global-lustre && !multi-storage && !lustre-csimount && !high-capacity' .

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
	${GINKGO_RUN} --fail-fast --label-filter='dm' .

# Run container tests
.PHONY: container
container:
	${GINKGO_RUN} --fail-fast --label-filter='container' .

# Run gfs2 fence test
.PHONY: gfs2_fence
gfs2_fence:
	${GINKGO_RUN} --label-filter='gfs2_fence' .

.PHONY: .version
.version: ## Uses the git-version-gen script to generate a tag version
	./git-version-gen --fallback `git rev-parse HEAD` > .version
