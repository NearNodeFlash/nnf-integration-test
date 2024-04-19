#!../bats/bin/bats

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

# number of computes
N=4

# source the files by doing a copy_in
# the source files are created with `create-testfiles.sh`
COPY_IN_SRC=/lus/global/testdir/src/

# destination directory root (e.g. /lus/global/user)
DEST_DIR=/lus/global/testdir/dest

tests_file="copy-in-copy-out.json"
num_tests=$(jq length $tests_file)

# Default to gfs2, but allow FS_TYPE env var to override
fs_type="${FS_TYPE:-gfs2}"

# Provide a way to run sanity or a protion of the tests (e.g. NUM_TESTS=1)
if [[ -v NUM_TESTS ]]; then
    num_tests=$NUM_TESTS
fi

copy_out_method="out"
if [[ -v COPY_OFFLOAD ]]; then
    copy_out_method="offload"
fi

# Read the test file and create a bats test for each entry
for ((i = 0; i < num_tests; i++)); do
    test_name=$(cat $tests_file | jq -r ".[$i].test")-$fs_type
    bats_test_function --description "copy-in-copy-$copy_out_method: $test_name" -- test_copy_in_copy_out "$i"
done

function setup() {
    rm -rf /lus/global/testdir/dest/*
}

# function teardown() {
#     rm -rf $USER_DIR/*
# }

function test_copy_in_copy_out() {
    local idx=$1
    local src=$(cat $tests_file | jq -r ".[$idx].src")
    local dest=$(cat $tests_file | jq -r ".[$idx].dest")
    local expected=$(cat $tests_file | jq -r ".[$idx].expected")

    # Use copy offload to do the copy_out (copy_in isn't supported)
    if [[ "$copy_out_method" == "offload" ]]; then
        # replace the hyphen in src with underscore since it's being used on the compute node rather than in a directive
        echo "SOURCE: $src"
        src="${src//-/_}"
        echo "AFTER SOURCE: $src"
        flux run -l -N${N} --wait-event=clean --setattr=dw="\
            #DW jobdw type=$fs_type capacity=10GiB name=copyout-test \
            #DW copy_in source=$COPY_IN_SRC destination=\$DW_JOB_copyout-test" \
            bash -c "hostname && \
                dm-client-go -source=$src -destination=$dest -profile=no-xattr"
    else
        flux run -l -N${N} --wait-event=clean --setattr=dw="\
            #DW jobdw type=$fs_type capacity=10GiB name=copyout-test \
            #DW copy_in source=$COPY_IN_SRC destination=\$DW_JOB_copyout-test \
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
