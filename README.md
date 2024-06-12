# nnf-integration-test

In this repository, there are two different test suites:

- nnf-integration-test
- nnf-system test

Both are meant to be run against a live, already-installed, rabbit system.

## Integration Testing

This is meant to be used as a submodule of [nnf-deploy](https://github.com/NearNodeFlash/nnf-deploy)
so that it is built against the same version of the code that has been deployed to the live rabbit
system.

`nnf-integation-test` does not run workflows through `flux` and is intended to provide a deeper
level of testing, since it can easily retrieve NNF resources in kubernetes. By default, **this test
uses all available computes/rabbits in the system configuration**. It is best for smaller
systems to do localized testing.

NNF test infrastructure and individualized tests reside in the [/internal](./internal/) directory.
Tests are expected to run against a fully deployed cluster reachable via your current k8s
configuration context. NNF test uses the [Ginkgo](https://onsi.github.io/ginkgo) test framework.

Various Ginkgo options can be passed into `go test`. Common options include `-ginkgo.fail-fast`,
`-ginkgo.show-node-events`,  and `-ginkgo.v`

```bash
go test -v ./test/... -ginkgo.fail-fast -ginkgo.v
```

Ginkgo also provides the [Ginkgo CLI](https://onsi.github.io/ginkgo/#ginkgo-cli-overview) that can
be used for enhanced test features like parallelization, randomization, and filtering.

### Test Definitions

Individual tests are listed in [/int_test.go](./int_test.go). Tests are written from the perspective
of a workload manager and should operate only on DWS resources when possible.

### Test Options

[Test Options](./internal/options.go) allow the user to extend test definitions with various options.
Administrative controls, like creating NNF Storage Profiles or NNF Container profiles, configuring a
global Lustre File System, or extracting Lustre parameters from a persistent Lustre instance, are
some example test options.

## System Testing

`nnf-system-test` runs all tests through `flux` and is intended to provide testing at the user
level. This can be customized to run on any number of compute nodes and can also run multiple jobs
in parallel.

See `system-test/README.md` for more.
