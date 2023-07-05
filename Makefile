all: fmt vet

.PHONY: fmt
fmt:
	go fmt ./...

.PHONY: vet
vet:
	go vet ./...

.PHONY: int-test
int-test:
	ginkgo run -p --vv ./...

