# nnf-system-test

This is a system level (e.g. flux) test suite for verifying NNF Workflows. The Flux workflow manager
is used to drive the management of NNF Worfklows. Since interaction with Flux is largely at the
shell level, the tests are written in bash. To drive that, Bash Automated Testing System (Bats) is
being used. This framework is installed as part of this system test for portability.

## Requirements

System Tests need to be run on a system where flux is available and the target destination global
lustre filesystem must also be mounted on the same system in order to verify workfows that use
global user (e.g. user container tests, the results of data movement operations). For HPE systems,
this means these tests can run on:

    - htx-lustre
    - texas-lustre

To support parallel execution of workflows, GNU `parallel` must be installed as it is a requirement
of `bats`.

## Bats Framework

Bats is a TAP testing framework for bash. This allows us to write a large number of tests in bash to
verify the behavior of NNF software. You can read more about this testing framework here:
<https://bats-core.readthedocs.io/en/stable/>

Bats is installed locally. The `bats_install.sh` script downloads and installs it locally to the
`bats/` directory. `make init` will do this for you. `make clean` will remove it.

It can also be added to your path via `source bats_env.sh`.

## Getting Started

To install bats and run system test:

```shell
make init
make test
```

## Customization

There are a number of ways to customize a run using environment variables. They can be supplied at
the command line or changed in the `Makefile`.

- `N`: Number of compute nodes to request via `flux -N`
- `J`: Number of parallel tests to run via `bats -j`
- `GLOBAL_LUSTRE_ROOT`: For tests that require global lustre, this is the file system path where
user directories are located (e.g. `/lus/global/myuser`)

## dm-system-test

These are tests that dive into the specifics of Data Movement. The current focus is to verify the
correct paths (for index mount directories) when doing copy-in and copy-out between ephemeral
filesystems and global lustre.

To run:

```shell
make dm
```

## copy-in-copy-out tests

These tests make use of a markdown table to define all the expected behavior when performing data
movement when it comes to verifying the destination mkdir directory and index mount directories. The
context of these tests is complex and make it hard to keep track all of the different test cases, so
a table is used to define the test cases. This table is then converted into JSON, which can then be
looped over to dynamically create Bats tests.

This is then done for each Data Movement supported filesystem type:
    - xfs
    - gfs2
    - lustre

There are additional tests to verify the Copy Offload API to facilitate the copy-out for the
supported filesystems:
    - gfs2
    - lustre

All tests for all filesystems can be kicked off by running:

    ```shell
    ./test-copy-in-copy-out.sh
    ```

You an also target one specific filesystem type by:

    ```shell
    FS_TYPE=xfs ./copy-in-copy-out.bats
    ```
