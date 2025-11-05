#!/usr/bin/env bash

# Copyright 2025 Hewlett Packard Enterprise Development LP
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

set -euo pipefail
NS=default
echo "Patching all workflows in namespace $NS to Teardown..."
for wf in $(kubectl -n "$NS" get workflows -o jsonpath='{.items[*].metadata.name}'); do
  cur=$(kubectl -n "$NS" get workflow "$wf" -o jsonpath='{.spec.desiredState}')
  if [ "$cur" = "Teardown" ]; then
    echo "[=] $wf already Teardown"
    continue
  fi
  echo "[>] $wf -> Teardown"
  kubectl -n "$NS" patch workflow "$wf" --type=merge -p '{"spec":{"desiredState":"Teardown"}}'
done

echo "Waiting for all to report status.state=Teardown (up to 10m each)..."
for wf in $(kubectl -n "$NS" get workflows -o jsonpath='{.items[*].metadata.name}'); do
  kubectl -n "$NS" wait --for=jsonpath='{.status.state}'=Teardown workflow/"$wf" --timeout=10m || echo "[!] Timeout $wf"
done

echo "Waiting for all workflows to be ready (up to 5m each)..."
for wf in $(kubectl -n "$NS" get workflows -o jsonpath='{.items[*].metadata.name}'); do
  echo "[.] Waiting for $wf to be ready..."
  kubectl -n "$NS" wait --for=jsonpath='{.status.ready}'=true workflow/"$wf" --timeout=5m || echo "[!] Timeout waiting for ready: $wf"
done

echo "Deleting all workflows..."
for wf in $(kubectl -n "$NS" get workflows -o jsonpath='{.items[*].metadata.name}'); do
  echo "[-] Deleting $wf"
  kubectl -n "$NS" delete workflow "$wf" --wait=false
done

echo "Waiting for all workflows to be deleted..."
kubectl -n "$NS" wait --for=delete workflows --all --timeout=5m 2>/dev/null || echo "[!] Some workflows may still be deleting"

echo "Teardown complete."