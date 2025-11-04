#!/usr/bin/env bash
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