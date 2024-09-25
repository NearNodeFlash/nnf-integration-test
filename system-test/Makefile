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
#

# If present, load the env file (ignored by git) to override the variables
# exported below. This is especially useful for setting Q and R on systems.
ifneq (,$(wildcard ./env))
	include env
	export
endif

# Default to 4 compute nodes
N ?= 4
export N

# Default to serial execution; Anything higher than 1 requires GNU parallel to be installed
J ?= 1
export J

# Default the global lustre root directory. Tests that use global lustre expect a
# writeable user directory at GLOBAL_LUSTRE_ROOT (e.g. /lus/global/myuser).
GLOBAL_LUSTRE_ROOT ?= $(shell df -t lustre --output=target 2>/dev/null | \
        awk 'FNR==2 { print $0; exit 1 }' && echo '/lus/global')
export GLOBAL_LUSTRE_ROOT

# Default to no flux queue
Q ?=
export Q

# No specfic nodes (with flux --requires)
R ?=
export R

# add bats to PATH
export PATH := $(shell ./bats_env.sh):$(PATH)

DM_PROFILE ?=
export DM_PROFILE

# Default bats command
BATS = bats -j $(J) -T

.PHONY: all
all: init test dm

.PHONY: init
init:
	./bats_install.sh

.PHONY: sanity
sanity:
	$(BATS) --filter-tags tag:sanity .

.PHONY: simple
simple:
	$(BATS) --filter-tags tag:simple .

%::
	$(BATS) --filter-tags tag:$@ .

.PHONY: test
test:
	$(BATS) .

.PHONY: dm
dm:
	echo "$(PATH)"
	cd dm; ./test-copy-in-copy-out.sh

.PHONY: clean
clean:
	rm -r ./bats
