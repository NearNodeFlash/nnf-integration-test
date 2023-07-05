# nnf-integration-test
An NNF integration test meant to be run against a live, already-installed, rabbit system.

# Testing

NNF test infrastructure and individualized tests reside in the [/internal](./internal/) directory. Tests are expected to run against a fully deployed cluster reachable via your current k8s configuration context. NNF test uses the [Ginkgo](https://onsi.github.io/ginkgo) test framework.

Various Ginkgo options can be passed into `go test`. Common options include `-ginkgo.fail-fast`,  `-ginkgo.show-node-events`,  and `-ginkgo.v`

```bash
go test -v ./test/... -ginkgo.fail-fast -ginkgo.v
```

Ginkgo also provides the [Ginkgo CLI](https://onsi.github.io/ginkgo/#ginkgo-cli-overview) that can be used for enhanced test features like parallelization, randomization, and filter.

## Test Definitions

Individual tests are listed in [/int_test.go](./int_test.go). Tests are written from the perspective of a workload manager and should operate only on DWS resources when possible.

## Test Options

[Test Options](./internal/options.go) allow the user extend test definitions with various options. Administrative controls, like creating NNF Storage Profiles or NNF Container profiles, configuring a global Lustre File System, or extracting Lustre parameters from a persistent Lustre instance, are some example test options.
