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

# Default to 4 compute nodes
N ?= 4

# Default to serial execution; Anything higher than 1 requires GNU parallel to be installed
J ?= 1

# Default the global lustre root directory. Tests that use global lustre expect a writeable user
# directory at GLOBAL_LUSTRE_ROOT (e.g. /lus/global/myuser).
GLOBAL_LUSTRE_ROOT ?= /lus/global

# add bats to PATH
export PATH := $(shell ./bats_env.sh):$(PATH)

.PHONY: all init dm clean env

all: init test dm

init:
	./bats_install.sh

test:
	bats -j $(J) .

dm:
	echo "$(PATH)"
	cd dm; ./test-copy-in-copy-out.sh

clean:
	rm -r ./bats
