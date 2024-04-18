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

mkdir -p /lus/global/testdir/src/job/job2
mkdir -p /lus/global/testdir/src/job2
echo "hello_there" >/lus/global/testdir/src/job/data.out
cp /lus/global/testdir/src/job/data.out /lus/global/testdir/src/job/data2.out
cp /lus/global/testdir/src/job/data.out /lus/global/testdir/src/job/job2/data3.out
cp /lus/global/testdir/src/job/data.out /lus/global/testdir/src/job2/data.out
cp /lus/global/testdir/src/job/data.out /lus/global/testdir/src/job2/data2.out

mkdir -p /lus/global/testdir/dest

# let the users group own testdir
chown -R root:users /lus/global/testdir

# make sure src isn't group writeable though (to protect it)
chmod -R g-w /lus/global/testdir/src

# make dest group writeable
chmod -R g+w /lus/global/testdir/dest/
