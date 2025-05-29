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

# This file is repsonsible for creating the environment needed to run the copy-in-copy-out tests on
# a global lustre filesystem that is mounted on `/lus/global`
TESTFILE_SIZE=100M

if [[ -z $1 ]]; then
    echo "testdir must be supplied"
    exit 1
fi
TESTDIR=$1

mkdir -p ${TESTDIR}/src/job/job2
mkdir -p ${TESTDIR}/src/job2
fallocate -l ${TESTFILE_SIZE} -x ${TESTDIR}/src/job/data.out

cp ${TESTDIR}/src/job/data.out ${TESTDIR}/src/job/data2.out
cp ${TESTDIR}/src/job/data.out ${TESTDIR}/src/job/job2/data3.out
cp ${TESTDIR}/src/job/data.out ${TESTDIR}/src/job2/data.out
cp ${TESTDIR}/src/job/data.out ${TESTDIR}/src/job2/data2.out

mkdir -p ${TESTDIR}/dest

# let the users group own testdir
#chown -R ${USER}:users ${TESTDIR}

# make sure src isn't group writeable though (to protect it)
chmod -R g-w ${TESTDIR}/src

# make dest group writeable
chmod -R g+w ${TESTDIR}/dest/
