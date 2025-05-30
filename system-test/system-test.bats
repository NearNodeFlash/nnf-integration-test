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

# Test Tempdir directory
if [[ -z "${TEST_TMPDIR_PREFIX}" ]]; then
    TEST_TMPDIR_PREFIX=${HOME}/nnf/tmp
fi

# Number of compute nodes; default to 4
if [[ -z "${N}" ]]; then
    N=4
fi

# Flux command
FLUX="flux run -l -N${N} --wait-event=clean"
FLUX_A="flux alloc -N${N}"

# Use a Flux queue
if [ "${Q}" != "" ]; then
    FLUX+=" -q ${Q}"
    FLUX_A+=" -q ${Q}"
fi

# Require specific rabbits
if [ "${R}" != "" ]; then
    FLUX+=" --requires=hosts:${R}"
    FLUX_A+=" --requires=hosts:${R}"
fi

# Command to run on the compute node via flux
# TODO try set -x
#COMPUTE_CMD="bash -c 'hostname'"
COMPUTE_CMD='hostname'

# How much space to request for rabbit workflows per node
GB_PER_NODE=300

# For capacity tests, what is the threshold of available capacity vs the requested capacity
CAPACITY_PERCENT=80

function setup_file {
    # When using UUID in the DW name keyboard, just use the first 9 digits to make $DW_ env vars easier
    export UUID=$(uuidgen | cut -d'-' -f1)

    # For lustre tests, use the total capacity given the node count
    export LUS_CAPACITY=$(($N * $GB_PER_NODE))

    # Ensure tempdir prefix directory exists
    mkdir -p ${TEST_TMPDIR_PREFIX}
}

function setup {
    # Create a test tmpdir at the supplied prefix (e.g. /home/user/nnf/tmp.x8e8f0a/)
    export TEST_TMPDIR=$(mktemp -d -p ${TEST_TMPDIR_PREFIX})
}

function teardown {
    if [[ -n "$TEST_TMPDIR" ]]; then
        rm -rf $TEST_TMPDIR
    fi
}

#----------------------------------------------------------
# Simple Tests
#----------------------------------------------------------
# bats test_tags=tag:xfs, tag:sanity, tag:simple
@test "XFS" {
    ${FLUX} --setattr=dw="\
        #DW jobdw type=xfs name=xfs capacity=${GB_PER_NODE}GB" \
        ${COMPUTE_CMD}
}

# bats test_tags=tag:gfs2, tag:simple
@test "GFS2" {
    ${FLUX} --setattr=dw="\
        #DW jobdw type=gfs2 name=gfs2 capacity=${GB_PER_NODE}GB" \
        ${COMPUTE_CMD}
}

# bats test_tags=tag:lustre, tag:simple
@test "Lustre" {
    ${FLUX} --setattr=dw="\
        #DW jobdw type=lustre name=lustre capacity=${LUS_CAPACITY}GB" \
        ${COMPUTE_CMD}
}

# bats test_tags=tag:raw, tag:simple
@test "Raw" {
    ${FLUX} --setattr=dw="\
        #DW jobdw type=raw name=raw capacity=${GB_PER_NODE}GB" \
        ${COMPUTE_CMD}
}

#----------------------------------------------------------
# Persistent Storage - Create
#----------------------------------------------------------

# bats test_tags=tag:lustre, tag:persistent, tag:create
@test "Persistent (Create) - Lustre" {
    if [ "$ENABLE_PERSISTENT" != "yes" ]; then
        skip
    fi
    ${FLUX} --setattr=dw="\
        #DW create_persistent type=lustre name=persistent-lustre-${UUID} capacity=${LUS_CAPACITY}GB" \
        ${COMPUTE_CMD}
}

# bats test_tags=tag:gfs2, tag:persistent, tag:create
@test "Persistent (Create) - GFS2" {
    if [ "$ENABLE_PERSISTENT" != "yes" ]; then
        skip
    fi
    ${FLUX} --setattr=dw="\
        #DW create_persistent type=gfs2 name=persistent-gfs2-${UUID} capacity=${GB_PER_NODE}GB" \
        ${COMPUTE_CMD}
}

# bats test_tags=tag:xfs, tag:persistent, tag:create
@test "Persistent (Create) - XFS" {
    if [ "$ENABLE_PERSISTENT" != "yes" ]; then
        skip
    fi
    ${FLUX} --setattr=dw="\
        #DW create_persistent type=xfs name=persistent-xfs-${UUID} capacity=${GB_PER_NODE}GB" \
        ${COMPUTE_CMD}
}

# bats test_tags=tag:raw, tag:persistent, tag:create
@test "Persistent (Create) - Raw" {
    if [ "$ENABLE_PERSISTENT" != "yes" ]; then
        skip
    fi
    ${FLUX} --setattr=dw="\
        #DW create_persistent type=raw name=persistent-raw-${UUID} capacity=${GB_PER_NODE}GB" \
        ${COMPUTE_CMD}
}

#----------------------------------------------------------
# Persistent Storage - Use It
#----------------------------------------------------------
# bats test_tags=tag:lustre, tag:persistent, tag:use
@test "Persistent (Usage) - Lustre" {
    if [ "$ENABLE_PERSISTENT" != "yes" ]; then
        skip
    fi
    ${FLUX} --setattr=dw="\
        #DW persistentdw name=persistent-lustre-${UUID}" \
        bash -c "fallocate -l1GB -x \${DW_PERSISTENT_persistent_lustre_${UUID}}/test-\${FLUX_TASK_RANK}.out && \
            stat \${DW_PERSISTENT_persistent_lustre_${UUID}}/test-\${FLUX_TASK_RANK}.out"
}

# bats test_tags=tag:gfs2, tag:persistent, tag:use
@test "Persistent (Usage) - GFS2" {
    if [ "$ENABLE_PERSISTENT" != "yes" ]; then
        skip
    fi
    ${FLUX} --setattr=dw="\
        #DW persistentdw name=persistent-gfs2-${UUID}" \
        bash -c "fallocate -l1GB -x \${DW_PERSISTENT_persistent_gfs2_${UUID}}/test123.out && \
            stat \${DW_PERSISTENT_persistent_gfs2_${UUID}}/test123.out"
}

# bats test_tags=tag:xfs, tag:persistent, tag:use
@test "Persistent (Usage) - XFS" {
    if [ "$ENABLE_PERSISTENT" != "yes" ]; then
        skip
    fi
    ${FLUX} --setattr=dw="\
        #DW persistentdw name=persistent-xfs-${UUID}" \
        bash -c "fallocate -l1GB -x \${DW_PERSISTENT_persistent_xfs_${UUID}}/test123.out && \
            stat \${DW_PERSISTENT_persistent_xfs_${UUID}}/test123.out"
}

# bats test_tags=tag:raw, tag:persistent, tag:use
@test "Persistent (Usage) - Raw" {
    if [ "$ENABLE_PERSISTENT" != "yes" ]; then
        skip
    fi
    ${FLUX} --setattr=dw="\
        #DW persistentdw name=persistent-raw-${UUID}" \
        bash -c "mkfs \${DW_PERSISTENT_persistent_raw_${UUID}} && \
            stat \${DW_PERSISTENT_persistent_raw_${UUID}}"
}

#----------------------------------------------------------
# Container Tests
#----------------------------------------------------------
# TODO: make these use ports

# bats test_tags=tag:gfs2, tag:container, tag:non-mpi, container:sanity
@test "Container - GFS2" {
    ${FLUX} --setattr=dw="\
        #DW jobdw type=gfs2 name=containers-gfs2 capacity=${GB_PER_NODE}GB \
        #DW container name=containers-gfs2 profile=example-success \
            DW_JOB_foo_local_storage=containers-gfs2" \
        ${COMPUTE_CMD}
}

# bats test_tags=tag:gfs2, tag:container, tag:mpi
@test "Container - GFS2 MPI" {
    ${FLUX} --setattr=dw="\
        #DW jobdw type=gfs2 name=containers-gfs2-mpi capacity=${GB_PER_NODE}GB \
        #DW container name=containers-gfs2-mpi profile=example-mpi \
            DW_JOB_foo_local_storage=containers-gfs2-mpi" \
        ${COMPUTE_CMD}
}

# bats test_tags=tag:lustre, tag:container, tag:non-mpi
@test "Container - Lustre" {
    ${FLUX} --setattr=dw="\
        #DW jobdw type=lustre name=containers-lustre capacity=${LUS_CAPACITY}GB \
        #DW container name=containers-lustre profile=example-success \
            DW_JOB_foo_local_storage=containers-lustre" \
        ${COMPUTE_CMD}
}

# bats test_tags=tag:lustre, tag:container, tag:mpi
@test "Container - Lustre MPI" {
    ${FLUX} --setattr=dw="\
        #DW jobdw type=lustre name=containers-lustre-mpi capacity=${LUS_CAPACITY}GB \
        #DW container name=containers-lustre-mpi profile=example-mpi \
            DW_JOB_foo_local_storage=containers-lustre-mpi" \
        ${COMPUTE_CMD}
}

# bats test_tags=tag:gfs2, tag:container, tag:global-lustre, tag:non-mpi
@test "Container - GFS2 + Global Lustre" {
    ${FLUX} --setattr=dw="\
        #DW jobdw type=gfs2 name=containers-gfs2-global-lustre capacity=${GB_PER_NODE}GB \
        #DW container name=containers-gfs2-global-lustre profile=example-success \
            DW_JOB_foo_local_storage=containers-gfs2-global-lustre \
            DW_GLOBAL_foo_global_lustre=${GLOBAL_LUSTRE_ROOT}" \
        ${COMPUTE_CMD}
}

# bats test_tags=tag:gfs2, tag:container, tag:global-lustre, tag:mpi
@test "Container - GFS2 + Global Lustre MPI" {
    ${FLUX} --setattr=dw="\
        #DW jobdw type=gfs2 name=containers-gfs2-global-lustre-mpi capacity=${GB_PER_NODE}GB \
        #DW container name=containers-gfs2-global-lustre-mpi profile=example-mpi \
            DW_JOB_foo_local_storage=containers-gfs2-global-lustre-mpi \
            DW_GLOBAL_foo_global_lustre=${GLOBAL_LUSTRE_ROOT}" \
        ${COMPUTE_CMD}
}

# bats test_tags=tag:lustre, tag:container, tag:global-lustre, tag:non-mpi
@test "Container - Lustre + Global Lustre" {
    ${FLUX} --setattr=dw="\
        #DW jobdw type=lustre name=containers-lustre-global-lustre capacity=${LUS_CAPACITY}GB \
        #DW container name=containers-lustre-global-lustre profile=example-success \
            DW_JOB_foo_local_storage=containers-lustre-global-lustre \
            DW_GLOBAL_foo_global_lustre=${GLOBAL_LUSTRE_ROOT}" \
        ${COMPUTE_CMD}
}

# bats test_tags=tag:lustre, tag:container, tag:global-lustre, tag:mpi
@test "Container - Lustre + Global Lustre MPI" {
    ${FLUX} --setattr=dw="\
        #DW jobdw type=lustre name=containers-lustre-global-lustre-mpi capacity=${LUS_CAPACITY}GB \
        #DW container name=containers-lustre-global-lustre-mpi profile=example-mpi \
            DW_JOB_foo_local_storage=containers-lustre-global-lustre-mpi \
            DW_GLOBAL_foo_global_lustre=${GLOBAL_LUSTRE_ROOT}" \
        ${COMPUTE_CMD}
}

# Containers - Long Running Non-MPI
# The copy offload tests in dm-system-test exercise MPI User Containers

# The example-forever profile has a long-running process that never exits and a short
# postRunTimeoutSeconds, so expect it to fail
# bats test_tags=tag:gfs2, tag:container, tag:non-mpi, container:long-running
@test "Container - Long Running (should fail)" {
    run ! ${FLUX} --setattr=dw="\
        #DW jobdw type=gfs2 name=containers-gfs2 capacity=${GB_PER_NODE}GB \
        #DW container name=containers-gfs2 profile=example-forever \
            DW_JOB_foo_local_storage=containers-gfs2" \
        ${COMPUTE_CMD}
    [ "$status" -eq 1 ]
    [[ "$output" =~ "user container(s) failed to complete after" ]]
}

# This test uses the same example-forever profile, but with a no-wait option
# so it should not wait for the container to finish and should not fail
# bats test_tags=tag:gfs2, tag:container, tag:non-mpi, container:long-running, container:no-wait
@test "Container - Long Running (no wait)" {
    ${FLUX} --setattr=dw="\
        #DW jobdw type=gfs2 name=containers-gfs2 capacity=${GB_PER_NODE}GB \
        #DW container name=containers-gfs2 profile=example-forever-nowait \
            DW_JOB_foo_local_storage=containers-gfs2" \
        ${COMPUTE_CMD}
}

# Containers - Unsupported File systems (xfs & raw)

# bats test_tags=tag:xfs, tag:container, tag:unsupported
@test "Container - Unsupported XFS" {
    run ! ${FLUX} --setattr=dw="\
        #DW jobdw type=xfs name=containers-xfs capacity=${GB_PER_NODE}GB \
        #DW container name=containers-xfs profile=example-success \
            DW_JOB_foo_local_storage=containers-xfs" \
        ${COMPUTE_CMD}
    [ "$status" -eq 1 ]
    [[ "$output" =~ "unsupported container filesystem" ]]
}

# bats test_tags=tag:raw, tag:container, tag:unsupported
@test "Container - Unsupported Raw" {
   run ! ${FLUX} --setattr=dw="\
        #DW jobdw type=raw name=containers-raw capacity=${GB_PER_NODE}GB \
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
    if [ "$ENABLE_PERSISTENT" != "yes" ]; then
        skip
    fi
    ${FLUX} --setattr=dw="\
        #DW destroy_persistent name=persistent-lustre-${UUID}" \
        ${COMPUTE_CMD}
}

# bats test_tags=tag:gfs2, tag:persistent, tag:destroy
@test "Persistent (Destroy) - GFS2" {
    if [ "$ENABLE_PERSISTENT" != "yes" ]; then
        skip
    fi
    ${FLUX} --setattr=dw="\
        #DW destroy_persistent name=persistent-gfs2-${UUID}" \
        ${COMPUTE_CMD}
}

# bats test_tags=tag:xfs, tag:persistent, tag:destroy
@test "Persistent (Destroy) - XFS" {
    if [ "$ENABLE_PERSISTENT" != "yes" ]; then
        skip
    fi
    ${FLUX} --setattr=dw="\
        #DW destroy_persistent name=persistent-xfs-${UUID}" \
        ${COMPUTE_CMD}
}

# bats test_tags=tag:raw, tag:persistent, tag:destroy
@test "Persistent (Destroy) - Raw" {
    if [ "$ENABLE_PERSISTENT" != "yes" ]; then
        skip
    fi
    ${FLUX} --setattr=dw="\
        #DW destroy_persistent name=persistent-raw-${UUID}" \
        ${COMPUTE_CMD}
}

#----------------------------------------------------------
# Capacity Tests
#----------------------------------------------------------
function create_capacity_file {
    wf_name=$1
    runit_file="$TEST_TMPDIR/run-it.sh"
    touch $runit_file
    chmod +x $runit_file
    cat << 'EOF' >> $runit_file
#!/bin/bash
echo "jobid: $(flux getattr jobid)"
requested_size=$1
capacity_percent=$2
type=$3

echo "\$DW_JOB_<NAME>: $DW_JOB_<NAME>"
hostname

#df_output=$(flux run -N1 df -BG "$DW_JOB_<NAME>" 2>/dev/null | tail -1)
df_output=$(df -BG "$DW_JOB_<NAME>" 2>/dev/null | tail -1)
if [ -z "$df_output" ]; then
    echo "Error: Invalid filesystem path or unable to retrieve information."
    exit 1
fi

available_size=$(echo "$df_output" | awk '{print $2}' | sed 's/G//')
required_size=$(( requested_size * capacity_percent / 100 ))

echo "requested_size: ${requested_size} GB"
echo "required_size (${capacity_percent}%): ${required_size} GB"
echo "available_size: ${available_size} GB"

if [ "$type" == "lustre" ]; then
    echo ".nnf-servers.json: $(cat $DW_JOB_<NAME>/.nnf-servers.json)"
fi

if [ "$available_size" -ge "$required_size" ]; then
    echo "Sufficient space available: ${available_size}G (>= ${capacity_percent}% of ${requested_size}G)"
    exit 0
else
    echo "Insufficient space: ${available_size}G (< ${capacity_percent}% of ${requested_size}G)"
    if [ "$type" == "lustre" ]; then
       echo "lfs df: $(lfs df $DW_JOB_<NAME>)"
       echo "lfs check servers: $(lfs check servers $DW_JOB_<NAME>)"
    fi
    df_output=$(df -BG "$DW_JOB_<NAME>" 2>/dev/null | tail -1)
    echo "df: $df_output"

    echo "sleeping for 30 seconds..."
    sleep 30

    if [ "$type" == "lustre" ]; then
       echo "lfs df: $(lfs df $DW_JOB_<NAME>)"
       echo "lfs check servers: $(lfs check servers $DW_JOB_<NAME>)"
    fi
    df_output=$(df -BG "$DW_JOB_<NAME>" 2>/dev/null | tail -1)
    echo "df: $df_output"
    exit 1
fi
EOF

    # replace the workflow name in the $DW_JOB_ env var
    sed -i "s/<NAME>/$wf_name/g" $runit_file

    echo $runit_file
}

# bats test_tags=tag:xfs, tag:capacity
@test "XFS - Capacity" {
    runit_file=$(create_capacity_file xfs)
    ${FLUX_A} --setattr=dw="\
        #DW jobdw type=xfs name=xfs capacity=${GB_PER_NODE}GB" \
        $runit_file ${GB_PER_NODE} $CAPACITY_PERCENT xfs
}

# bats test_tags=tag:gfs2, tag:capacity
@test "GFS2 - Capacity" {
    runit_file=$(create_capacity_file gfs2)
    ${FLUX_A} --setattr=dw="\
        #DW jobdw type=gfs2 name=gfs2 capacity=${GB_PER_NODE}GB" \
        $runit_file ${GB_PER_NODE} $CAPACITY_PERCENT gfs2
}

# bats test_tags=tag:lustre, tag:capacity
@test "Lustre - Capacity" {
    runit_file=$(create_capacity_file lustre)
    ${FLUX_A} --setattr=dw="\
        #DW jobdw type=lustre name=lustre capacity=${LUS_CAPACITY}GB" \
        $runit_file ${LUS_CAPACITY} $CAPACITY_PERCENT lustre
}
