#!/bin/bash

# This file is meant to be sourced (.) to update PATH to include the local install of ginkgo.

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

GOBIN=${HOME}/go/bin

# Check if the directory is already in PATH
if [[ ":$PATH:" != *":$GOBIN:"* ]]; then
    # Add the directory to PATH
    export PATH="$GOBIN:$PATH"
    echo "Added $GOBIN to PATH"
else
    echo "$GOBIN is already in PATH"
fi
