#!/usr/bin/env bash
# Reports anything in the openshift-storage namespace that is NOT in its
# desired/ready state. Sections shrink as a rollout converges; an empty
# report (other than the cluster CRs at the bottom) means done.
#
# Why no hardcoded ODF package list: the CSV section uses the label
# selector "!olm.copiedFrom" to pick CSVs natively installed in this
# namespace, excluding copies that OLM propagates from AllNamespaces
# operators living in other namespaces (metallb, gitops, builds, ...).
# This auto-includes any new component Red Hat adds in a future ODF
# version without script changes.
#
# Why -o json | jq and -o custom-columns everywhere: `oc get` column
# order is not a stable API; kubectl reserves the right to change it.
# JSONPath and jq read structured fields and are stable.
#
# Intended usage:  watch -n 3 ./odf-rollout-status.sh

NS=openshift-storage

echo "=== CSVs not yet Succeeded (natively installed in $NS) ==="
oc get csv -n "$NS" -l '!olm.copiedFrom' -o json | jq -r '
  .items[]
  | select(.status.phase != "Succeeded")
  | "  \(.metadata.name)\t\(.status.phase)\t\(.spec.version)"
' | column -t -s $'\t'

echo
echo "=== InstallPlans not Complete ==="
oc get installplan -n "$NS" -o json | jq -r '
  .items[]
  | select(.status.phase != "Complete")
  | "  \(.metadata.name)\t\(.spec.clusterServiceVersionNames[0])\tapproval=\(.spec.approval)\tapproved=\(.spec.approved)\tphase=\(.status.phase // "?")"
' | column -t -s $'\t'

echo
echo "=== Deployments not fully Available ==="
oc get deploy -n "$NS" -o json | jq -r '
  .items[]
  | select((.status.availableReplicas // 0) < .spec.replicas)
  | "  \(.metadata.name)\t\(.status.availableReplicas // 0)/\(.spec.replicas) available\tgen=\(.metadata.generation) observed=\(.status.observedGeneration // 0)"
' | column -t -s $'\t'

echo
echo "=== StatefulSets not ready ==="
oc get statefulset -n "$NS" -o json | jq -r '
  .items[]
  | select((.status.readyReplicas // 0) < .spec.replicas)
  | "  \(.metadata.name)\t\(.status.readyReplicas // 0)/\(.spec.replicas) ready"
' | column -t -s $'\t'

echo
echo "=== DaemonSets not ready ==="
oc get daemonset -n "$NS" -o json | jq -r '
  .items[]
  | select((.status.numberReady // 0) < .status.desiredNumberScheduled)
  | "  \(.metadata.name)\t\(.status.numberReady // 0)/\(.status.desiredNumberScheduled) ready"
' | column -t -s $'\t'

echo
echo "=== Pods not Ready (phase!=Succeeded and Ready!=True) ==="
oc get pods -n "$NS" -o json | jq -r '
  .items[]
  | select(.status.phase != "Succeeded")
  | (.status.conditions[]? | select(.type=="Ready") | .status) as $ready
  | select($ready != "True")
  | (.status.containerStatuses // []
      | map(select(.ready != true) | .name + "=" + (.state | keys[0] // "?"))
      | join(",")) as $bad
  | "  \(.metadata.name)\tphase=\(.status.phase)\tready=\($ready // "Unknown")\tbad=\($bad)"
' | column -t -s $'\t'

echo
echo "=== StorageCluster ==="
oc get storagecluster -n "$NS" -o custom-columns='NAME:.metadata.name,PHASE:.status.phase,VERSION:.status.version'

echo
echo "=== CephCluster ==="
oc get cephcluster -n "$NS" -o custom-columns='NAME:.metadata.name,PHASE:.status.phase,HEALTH:.status.ceph.health,VERSION:.status.ceph.versions.overall'
