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

# Optionally use copy_offload to perform the copy_out
copy_out_method="out"
if [ "${COPY_OFFLOAD}" != "" ]; then
    copy_out_method="offload"
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

# Read the test file and create a bats test for each entry
for ((i = 0; i < NUM_TESTS; i++)); do
    test_name=$(cat $tests_file | jq -r ".[$i].test")-$fs_type
    bats_test_function --description "copy-in-copy-$copy_out_method: $test_name" -- test_copy_in_copy_out "$i"
done

function setup() {
    ./create-testfiles.sh ${TESTDIR}
    rm -rf ${TESTDIR}/dest/*
}

function teardown() {
    # clean up if it succeeded, otherwise leave it around for inspection (if no other tests run afterwards)
    if [[ -v "${BATS_TEST_COMPLETED}" ]]; then
        rm -rf ${TESTDIR}/dest/*
    fi
}

function test_copy_in_copy_out() {
    local idx=$1
    local src=$(cat $tests_file | jq -r ".[$idx].src")
    local dest=$(cat $tests_file | jq -r ".[$idx].dest")
    local expected=$(cat $tests_file | jq -r ".[$idx].expected")

    local copy_in_src=${TESTDIR}/src/

    # expand the $TESTDIR variable in dest/expected vars
    dest="$(eval echo "$dest")"
    expected="$(eval echo "$expected")"

    # Use copy offload to do the copy_out (copy_in isn't supported)
    if [[ "$copy_out_method" == "offload" ]]; then
        # replace the hyphen in src with underscore since it's being used on the compute node rather than in a directive
        echo "SOURCE: $src"
        src="${src//-/_}"
        echo "AFTER SOURCE: $src"
        ${FLUX} --setattr=dw="\
            #DW jobdw type=$fs_type capacity=10GiB name=copyout-test \
            #DW copy_in source=$copy_in_src destination=\$DW_JOB_copyout-test" \
            bash -c "hostname && \
                dm-client-go -source=$src -destination=$dest -profile=no-xattr"
    else
        ${FLUX} --setattr=dw="\
            #DW jobdw type=$fs_type capacity=10GiB name=copyout-test \
            #DW copy_in source=$copy_in_src destination=\$DW_JOB_copyout-test \
            #DW copy_out source=$src destination=$dest profile=no-xattr" \
            bash -c "hostname"
    fi

    # For lustre, remove the `/*` from expected since there are no index mounts
    if [[ "$fs_type" == "lustre" ]]; then
        expected="${expected/\*\//}"
    fi

    # grab the output from ls
    local ls_output=$(/bin/ls -l ${expected})
    echo "$ls_output" # print it out in case of fail

    # if lustre, then no index mounts and only 1 file
    if [[ "$fs_type" == "lustre" ]]; then
        echo "$ls_output" | wc -l | grep 1
    # otherwise verify the number of lines from `ls -l`
    else
        echo "$ls_output" | wc -l | grep $N
    fi
}
