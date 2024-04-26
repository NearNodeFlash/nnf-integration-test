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

# default the global lustre root directory if not set
GLOBAL_LUSTRE_ROOT ?= /lus/global

# add bats to PATH
CWD := $(shell pwd)
export PATH := $(CWD)/bats/bin:$(PATH)

.PHONY: all init dm clean env

all: init dm

init:
	./bats_install.sh

env:
	. ./bats_env.sh

dm: env
	echo "$(PATH)"
	cd dm; ./test-copy-in-copy-out.sh

clean:
	rm -r ./bats
