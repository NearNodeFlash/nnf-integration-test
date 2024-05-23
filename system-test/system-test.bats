#!/usr/bin/env bats

# Copyright 2024 Hewlett Packard Enterprise Development LP
# Other additional copyright holders may be indicated within.
#
# The entirety of this work is licensed under the Apache License,
# Version 2.0 (the "License"); you may not use this file except
# in compliance with the License.
#
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
bats_require_minimum_version 1.5.0

# Global lustre root directory
if [[ -z "${GLOBAL_LUSTRE_ROOT}" ]]; then
    GLOBAL_LUSTRE_ROOT=/lus/global
fi

# Number of compute nodes; default to 4
if [[ -z "${N}" ]]; then
    N=4
fi

# Flux command
FLUX="flux run -l -N${N} --wait-event=clean"

# Use a Flux queue
if [ "${Q}" != "" ]; then
    FLUX+=" -q ${Q}"
fi

# Require specific rabbits
if [ "${R}" != "" ]; then
    FLUX+=" --requires=hosts:${R}"
fi

# Command to run on the compute node via flux
# TODO try set -x
COMPUTE_CMD='hostname'

echo ${FLUX}

#----------------------------------------------------------
# Simple Tests
#----------------------------------------------------------

# bats test_tags=tag:xfs, tag:sanity, tag:simple
@test "XFS" {
    ${FLUX} --setattr=dw="\
        #DW jobdw type=xfs name=xfs capacity=50GB" \
        ${COMPUTE_CMD}
}

# bats test_tags=tag:gfs2, tag:simple
@test "GFS2" {
    ${FLUX} --setattr=dw="\
        #DW jobdw type=gfs2 name=gfs2 capacity=50GB" \
        ${COMPUTE_CMD}
}

# bats test_tags=tag:lustre, tag:simple
@test "Lustre" {
    ${FLUX} --setattr=dw="\
        #DW jobdw type=lustre name=lustre capacity=50GB" \
        ${COMPUTE_CMD}
}

# bats test_tags=tag:raw, tag:simple
@test "Raw" {
    ${FLUX} --setattr=dw="\
        #DW jobdw type=raw name=raw capacity=50GB" \
        ${COMPUTE_CMD}
}

#----------------------------------------------------------
# Persistent Storage - Create
#----------------------------------------------------------

# bats test_tags=tag:lustre, tag:persistent, tag:create
@test "Persistent (Create) - Lustre" {
    ${FLUX} --setattr=dw="\
        #DW create_persistent type=lustre name=persistent-lustre capacity=50GB" \
        ${COMPUTE_CMD}
}

# bats test_tags=tag:gfs2, tag:persistent, tag:create
@test "Persistent (Create) - GFS2" {
    ${FLUX} --setattr=dw="\
        #DW create_persistent type=gfs2 name=persistent-gfs2 capacity=50GB" \
        ${COMPUTE_CMD}
}

# bats test_tags=tag:xfs, tag:persistent, tag:create
@test "Persistent (Create) - XFS" {
    ${FLUX} --setattr=dw="\
        #DW create_persistent type=xfs name=persistent-xfs capacity=50GB" \
        ${COMPUTE_CMD}
}

# bats test_tags=tag:raw, tag:persistent, tag:create
@test "Persistent (Create) - Raw" {
    ${FLUX} --setattr=dw="\
        #DW create_persistent type=raw name=persistent-raw capacity=50GB" \
        ${COMPUTE_CMD}
}

#----------------------------------------------------------
# Persistent Storage - Use It
#----------------------------------------------------------
# bats test_tags=tag:gfs2, tag:persistent, tag:use
@test "Persistent (Usage) - GFS2" {
    skip
    ${FLUX} --setattr=dw="\
        #DW jobdw type=gfs2 name=use-persistent-gfs2 capacity=50GB \
        #DW persistentdw name=persistent-gfs2" \
        bash -c "fallocate -l1GB \${DW_PERSISTENT_persistent_gfs2}/test123.out && realpath \${DW_PERSISTENT_persistent_gfs2}"
    # [[ "$output" =~ ^/mnt/nnf/[[:alnum:]-]+/test123\.out$ ]]
}

#----------------------------------------------------------
# Container Tests
#----------------------------------------------------------
# TODO: make these use ports

# bats test_tags=tag:gfs2, tag:container, tag:non-mpi, container:sanity
@test "Container - GFS2" {
    ${FLUX} --setattr=dw="\
        #DW jobdw type=gfs2 name=containers-gfs2 capacity=100GB \
        #DW container name=containers-gfs2 profile=example-success \
            DW_JOB_foo_local_storage=containers-gfs2" \
        ${COMPUTE_CMD}
}

# bats test_tags=tag:gfs2, tag:container, tag:mpi
@test "Container - GFS2 MPI" {
    ${FLUX} --setattr=dw="\
        #DW jobdw type=gfs2 name=containers-gfs2-mpi capacity=100GB \
        #DW container name=containers-gfs2-mpi profile=example-mpi \
            DW_JOB_foo_local_storage=containers-gfs2-mpi" \
        ${COMPUTE_CMD}
}

# bats test_tags=tag:lustre, tag:container, tag:non-mpi
@test "Container - Lustre" {
    ${FLUX} --setattr=dw="\
        #DW jobdw type=lustre name=containers-lustre capacity=100GB \
        #DW container name=containers-lustre profile=example-success \
            DW_JOB_foo_local_storage=containers-lustre" \
        ${COMPUTE_CMD}
}

# bats test_tags=tag:lustre, tag:container, tag:mpi
@test "Container - Lustre MPI" {
    ${FLUX} --setattr=dw="\
        #DW jobdw type=lustre name=containers-lustre-mpi capacity=100GB \
        #DW container name=containers-lustre-mpi profile=example-mpi \
            DW_JOB_foo_local_storage=containers-lustre-mpi" \
        ${COMPUTE_CMD}
}

# bats test_tags=tag:gfs2, tag:container, tag:global-lustre, tag:non-mpi
@test "Container - GFS2 + Global Lustre" {
    ${FLUX} --setattr=dw="\
        #DW jobdw type=gfs2 name=containers-gfs2-global-lustre capacity=100GB \
        #DW container name=containers-gfs2-global-lustre profile=example-success \
            DW_JOB_foo_local_storage=containers-gfs2-global-lustre \
            DW_GLOBAL_foo_global_lustre=${GLOBAL_LUSTRE_ROOT}" \
        ${COMPUTE_CMD}
}

# bats test_tags=tag:gfs2, tag:container, tag:global-lustre, tag:mpi
@test "Container - GFS2 + Global Lustre MPI" {
    ${FLUX} --setattr=dw="\
        #DW jobdw type=gfs2 name=containers-gfs2-global-lustre-mpi capacity=100GB \
        #DW container name=containers-gfs2-global-lustre-mpi profile=example-mpi \
            DW_JOB_foo_local_storage=containers-gfs2-global-lustre-mpi \
            DW_GLOBAL_foo_global_lustre=${GLOBAL_LUSTRE_ROOT}" \
        ${COMPUTE_CMD}
}

# bats test_tags=tag:lustre, tag:container, tag:global-lustre, tag:non-mpi
@test "Container - Lustre + Global Lustre" {
    ${FLUX} --setattr=dw="\
        #DW jobdw type=lustre name=containers-lustre-global-lustre capacity=100GB \
        #DW container name=containers-lustre-global-lustre profile=example-success \
            DW_JOB_foo_local_storage=containers-lustre-global-lustre \
            DW_GLOBAL_foo_global_lustre=${GLOBAL_LUSTRE_ROOT}" \
        ${COMPUTE_CMD}
}

# bats test_tags=tag:lustre, tag:container, tag:global-lustre, tag:mpi
@test "Container - Lustre + Global Lustre MPI" {
    ${FLUX} --setattr=dw="\
        #DW jobdw type=lustre name=containers-lustre-global-lustre-mpi capacity=100GB \
        #DW container name=containers-lustre-global-lustre-mpi profile=example-mpi \
            DW_JOB_foo_local_storage=containers-lustre-global-lustre-mpi \
            DW_GLOBAL_foo_global_lustre=${GLOBAL_LUSTRE_ROOT}" \
        ${COMPUTE_CMD}
}

# Containers - Unsupported File systems (xfs & raw)

# bats test_tags=tag:xfs, tag:container, tag:unsupported
@test "Container - Unsupported XFS" {
    run ! ${FLUX} --setattr=dw="\
        #DW jobdw type=xfs name=containers-xfs capacity=100GB \
        #DW container name=containers-xfs profile=example-success \
            DW_JOB_foo_local_storage=containers-xfs" \
        ${COMPUTE_CMD}
    [ "$status" -eq 1 ]
    [[ "$output" =~ "unsupported container filesystem" ]]
}

# bats test_tags=tag:raw, tag:container, tag:unsupported
@test "Container - Unsupported Raw" {
    run ! ${FLUX} --setattr=dw="\
        #DW jobdw type=raw name=containers-raw capacity=100GB \
        #DW container name=containers-raw profile=example-success \
            DW_JOB_foo_local_storage=containers-raw" \
        ${COMPUTE_CMD}
    [ "$status" -eq 1 ]
    [[ "$output" =~ "unsupported container filesystem" ]]
}

# TODO Containers - MPI Failures (needs container profiles)

#----------------------------------------------------------
# Persistent Storage - Destroy
#----------------------------------------------------------
# bats test_tags=tag:lustre, tag:persistent, tag:destroy
@test "Persistent (Destroy) - Lustre" {
    ${FLUX} --setattr=dw="\
        #DW destroy_persistent name=persistent-lustre" \
        ${COMPUTE_CMD}
}

# bats test_tags=tag:gfs2, tag:persistent, tag:destroy
@test "Persistent (Destroy) - GFS2" {
    ${FLUX} --setattr=dw="\
        #DW destroy_persistent name=persistent-gfs2" \
        ${COMPUTE_CMD}
}

# bats test_tags=tag:xfs, tag:persistent, tag:destroy
@test "Persistent (Destroy) - XFS" {
    ${FLUX} --setattr=dw="\
        #DW destroy_persistent name=persistent-xfs" \
        ${COMPUTE_CMD}
}

# bats test_tags=tag:raw, tag:persistent, tag:destroy
@test "Persistent (Destroy) - Raw" {
    ${FLUX} --setattr=dw="\
        #DW destroy_persistent name=persistent-raw" \
        ${COMPUTE_CMD}
}
