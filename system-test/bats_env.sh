# This file is meant to be sourced (.) to update PATH to include the local install of bats.

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

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BATS_DIR=${SCRIPT_DIR}/bats/bin

# Check if the directory is already in PATH
if [[ ":$PATH:" != *":$BATS_DIR:"* ]]; then
    # Add the directory to PATH
    export PATH="$BATS_DIR:$PATH"
    echo "Added $BATS_DIR to PATH"
else
    echo "$BATS_DIR is already in PATH"
fi
