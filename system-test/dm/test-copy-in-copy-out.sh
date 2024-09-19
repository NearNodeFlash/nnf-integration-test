#!/bin/bash

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

# Run all of the copy-in-copy-out tests for all filesystems

# TODO: create dedicated job directories so bats -j can be used without collision

set -e

# default to /lus/global/<user>/dm-system-test
if [[ -z "${GLOBAL_LUSTRE_ROOT}" ]]; then
    GLOBAL_LUSTRE_ROOT=/lus/global
fi

# for now, expect the user directory to exist in global lustre root directory
export TESTDIR=${GLOBAL_LUSTRE_ROOT}/${USER}/dm-system-test

pushd copy-in-copy-out

# turn markdown table into json
python3 convert_table.py copy-in-copy-out.md copy-in-copy-out.json

if [[ -n "${FS_TYPE}" ]]; then
    bats -j "${J}" -T ./copy-in-copy-out.bats
else
    # Run copy_out tests for each filesystem
    FS_TYPE=gfs2 bats -j "${J}" -T ./copy-in-copy-out.bats
    FS_TYPE=xfs bats -j "${J}" -T ./copy-in-copy-out.bats
    FS_TYPE=lustre bats -j "${J}" -T ./copy-in-copy-out.bats

    # Run the same with copy offload with supported filesystems (gfs2->lustre, lustre->lustre)
    FS_TYPE=gfs2 COPY_OFFLOAD=y bats -j "${J}" -T ./copy-in-copy-out.bats
    FS_TYPE=lustre COPY_OFFLOAD=y bats -j "${J}" -T ./copy-in-copy-out.bats
fi

popd
