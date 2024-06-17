#!/bin/bash

# Install ginkgo to default GOBIN (~/go/bin)

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
# Get the directory of this script

GINKGO_MOD=$(grep "github.com/onsi/ginkgo" go.mod | awk '{print $1 "@" $2}')
GOMEGA_VER=$(grep "github.com/onsi/gomega" go.mod | awk '{print $2}')
bash -c "echo Using ${GINKGO_MOD} and gomega ${GOMEGA_VER} && go get ${GINKGO_MOD} && go get github.com/onsi/gomega@${GOMEGA_VER}"

GINKGO_CLI_VER=$(grep "github.com/onsi/ginkgo" go.mod | awk '{print $2}')
bash -c "go install github.com/onsi/ginkgo/v2/ginkgo@${GINKGO_CLI_VER}"
