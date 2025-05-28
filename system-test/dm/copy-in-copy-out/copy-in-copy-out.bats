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

# These tests run a copy_in/copy_out to and from global lustre using flux. These tests rely a
# specific folder structure that can be created with `create-testfile.sh`. Additionaly, the supplied
# source and destination parameters are supplied via a table defined in `copy-in-copy-out.md`. This
# table is then converted to json, which is used for this test. `convert_table.py` is used to perform
# that converstion into `copy-in-copy-out.json`, which is used by this file.

# TESTDIR must be set - this is used as the root directory for the src/dest
# directories. This must live on global lustre (e.g. /lus/global/<user>/dm-system-test)
if [[ -z "${TESTDIR}" ]]; then
    echo "Error: TESTDIR must be set!" >&2
    exit 1
fi

tests_file="copy-in-copy-out.json"

# Default to gfs2, but allow FS_TYPE env var to override
fs_type="${FS_TYPE:-gfs2}"

# Number of compute nodes; default to 4
if [[ -z "${N}" ]]; then
    N=4
fi

# Provide a way to run sanity or a portion of the tests (e.g. NUM_TESTS=1)
if [[ -z "${NUM_TESTS}" ]]; then
    NUM_TESTS=$(jq length $tests_file)
fi

if [[ -z "${DM_PROFILE}" ]]; then
    DM_PROFILE=default
fi

# Optionally use copy_offload to perform the copy_out
copy_out_method="out"
if [ "${COPY_OFFLOAD}" != "" ]; then
    copy_out_method="offload"
fi

# Default to using the lib-copy-offload-tester binary for copy offload tests
if [[ -z "${COPY_OFFLOAD_TEST_BIN}" ]]; then
    COPY_OFFLOAD_TEST_BIN=lib-copy-offload-tester
fi

# Flux command
FLUX="flux run -l -N${N}"
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

# Read the test file and create a bats test for each entry
for ((i = 0; i < NUM_TESTS; i++)); do
    test_name=$(cat $tests_file | jq -r ".[$i].test")-$fs_type
    bats_test_function --description "copy-in-copy-$copy_out_method: $test_name" -- test_copy_in_copy_out "$i"
done

function setup() {
    # Create a test tmpdir at the supplied prefix (e.g. /home/user/nnf/tmp.x8e8f0a/)
    export TEST_TMPDIR=$(mktemp -d -p ${TEST_TMPDIR_PREFIX})

    # Make a unique directory to support simulteanous tests
    export UUID=$(uuidgen | cut -d'-' -f1)
    export DESTDIR=${TESTDIR}/${UUID}
    mkdir -p ${DESTDIR}
    ./create-testfiles.sh ${DESTDIR}
}

function teardown() {
    if [[ -n "$TEST_TMPDIR" ]]; then
        rm -rf $TEST_TMPDIR
    fi

    # clean up if it succeeded, otherwise leave it around for inspection (if no other tests run afterwards)
    if [[ "${BATS_TEST_COMPLETED}" -eq 1 ]]; then
        rm -rf ${DESTDIR}
    fi

}

# Create a copy offload file to be used in the test by the flux job. This file is used to
# run the lib-copy-offload-tester program. This file is created in the test tmpdir and
# is passed to the flux job. The file is created with the following contents:
function create_copyoffload_file {
    runit_file="$TEST_TMPDIR/run-it.sh"
    touch $runit_file
    chmod +x $runit_file
    cat << 'EOF' >> $runit_file
#!/bin/bash
echo "starting test"
set -e

token_file=$1
src=$2
dst=$3
profile=$4
prog=<COPY_OFFLOAD_TEST_BIN>

jobid=$FLUX_JOB_ID
jobuid=$(echo $FLUX_KVS_NAMESPACE | cut -d '-' -f2)
wf=fluxjob-$jobuid

echo "jobid:      $jobid"
echo "workflow:   $wf"
echo "hostname:   $(hostname)"
echo "token_file: $token_file"
echo "src:        $src"
echo "dst:        $dst"
echo "profile:    $profile"

if [[ -z "$token_file" || -z "$src" || -z "$dst" || -z "$profile" ]]; then
    echo "Error: One or more required variables are not set"
    exit 1
fi


# TODO: reword this to be more generic - if we need this, it means flux isn't giving us env vars
# This should be set for us by flux, but if not, and kubectl is available, go and get it.
if [ -z $DW_WORKFLOW_TOKEN ]; then
    echo "DW_WORKFLOW_TOKEN not set, trying to get it from kubectl"

    if command -v kubectl >/dev/null 2>&1 && kubectl version --request-timeout=5s >/dev/null 2>&1; then
        echo "kubectl is available and can contact the server"
    else
        echo "kubectl is not available or cannot contact the server"
        exit 1
    fi

    kubectl get secret `kubectl get workflow $wf -ojson | jq -rM .status.workflowToken.secretName` -ojson | jq -rM .data.token | base64 -d > $token_file

    export NNF_CONTAINER_LAUNCHER=$(kubectl get workflow $wf -ojson | jq -rM '.status.env["NNF_CONTAINER_LAUNCHER"]')
    export NNF_CONTAINER_PORTS=$(kubectl get workflow $wf -ojson | jq -rM '.status.env["NNF_CONTAINER_PORTS"]')
    export DW_WORKFLOW_TOKEN=$(<$token_file)
fi

echo "NNF* env vars:"
env | grep -E "NNF|DW_JOB|WORKFLOW|TOKEN"

# expand the $DW_JOB variable
src=$(eval echo "$src")
echo "src: $src"

export DW_WORKFLOW_NAME=$wf
export DW_WORKFLOW_NAMESPACE=default

# Start a copy offload and capture the ID
args=(
    -o
    -S $src
    -D $dst
    -P $profile
)

echo "Running $prog ${args[@]}..."
ID=$($prog "${args[@]}")
prog_status=$?
if [[ $prog_status -ne 0 ]]; then
    echo "ERROR: $prog failed with exit code $prog_status"
    echo "  Command: $prog ${args[@]}"
    exit $prog_status
fi

# # Get the ID for the copy offload
# sleep 1
# args=(
#     -l
# )
# echo "Running $prog ${args[@]}..."
# ID=$($prog "${args[@]}")
echo "ID: $ID"

# Wait for the copy offload to finish
args=(
    -q
    -j $ID
    -w -1
)
echo "Running $prog ${args[@]}..."
$prog "${args[@]}"
EOF
    # replace the prog name
    sed -i "s/<COPY_OFFLOAD_TEST_BIN>/$COPY_OFFLOAD_TEST_BIN/g" $runit_file

    echo $runit_file
}

# This function runs the copy_in/copy_out test. It takes a single argument, which is the index
# of the test to run. It reads the test parameters from the JSON file and runs the test using
# flux.
function test_copy_in_copy_out() {
    local idx=$1
    local src=$(cat $tests_file | jq -r ".[$idx].src")
    local dest=$(cat $tests_file | jq -r ".[$idx].dest")
    local expected=$(cat $tests_file | jq -r ".[$idx].expected")

    local copy_in_src=${DESTDIR}/src/

    # expand the $DESTDIR variable in dest/expected vars
    dest="$(eval echo "$dest")"
    expected="$(eval echo "$expected")"

    # Use copy offload to do the copy_out (copy_in isn't supported)
    if [[ "$copy_out_method" == "offload" ]]; then
        # replace the hyphen in src with underscore since it's being used on the compute node rather than in a directive
        echo "SOURCE: $src"
        src="${src//-/_}"
        echo "AFTER SOURCE: $src"
        token="change-me"

        # TODO: is this running on each compute? we're only getting 1 copy offload file at the end
        runit_file=$(create_copyoffload_file)
        echo "runit_file: $runit_file"
        ${FLUX} --setattr=dw="\
            #DW jobdw type=$fs_type capacity=10GiB name=copyout-test requires=copy-offload \
            #DW copy_in source=$copy_in_src destination=\$DW_JOB_copyout-test \
            #DW container name=copyoff-container profile=copy-offload-default \
                DW_JOB_my_storage=copyout-test DW_GLOBAL_lus=$GLOBAL_LUSTRE_ROOT" \
            $runit_file $token $src $dest $DM_PROFILE
    else
        ${FLUX} --setattr=dw="\
            #DW jobdw type=$fs_type capacity=10GiB name=copyout-test \
            #DW copy_in source=$copy_in_src destination=\$DW_JOB_copyout-test \
            #DW copy_out source=$src destination=$dest profile=$DM_PROFILE" \
            bash -c "hostname"
    fi

    # For lustre, remove the `/*` from expected since there are no index mounts
    if [[ "$fs_type" == "lustre" ]]; then
        expected="${expected/\*\//}"
    fi

    # grab the output from ls
    local ls_output=$(/bin/ls -l ${expected})
    echo "ls_output: $ls_output" # print it out in case of fail

    local actual_count=$(echo "$ls_output" | wc -l)
    local expected_count

    if [[ "$fs_type" == "lustre" ]]; then
        expected_count=1
    else
        expected_count=$N
    fi

    if [[ "$actual_count" -ne "$expected_count" ]]; then
        echo "ERROR: File count mismatch for $expected"
        echo "  Filesystem type: $fs_type"
        echo "  Expected count: $expected_count"
        echo "  Actual count:   $actual_count"
        echo "  ls output:"
        echo "$ls_output"
        return 1
    fi
}
