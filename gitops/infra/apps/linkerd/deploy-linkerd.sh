#!/usr/bin/env bash
# Deploy Linkerd from local manifests (to be executed on master)
# Assumes the following files exist:
#   linkerd/linkerd-crds.yaml
#   linkerd/linkerd-control-plane.yaml
#   linkerd/linkerd-viz.yaml
#   linkerd/dashboard.yaml
#   linkerd/linkerd-grafana.yaml
#
# Uses /home/ubuntu/.kube/config as kubeconfig. Adjust if different.

set -euo pipefail

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
NC='\033[0m'

KUBECONFIG_PATH="/home/ubuntu/.kube/config"
MANIFEST_DIR="/home/ubuntu/projects/apps/linkerd"
CRDS_FILE="$MANIFEST_DIR/linkerd-crds.yaml"
CONTROL_PLANE_FILE="$MANIFEST_DIR/linkerd-control-plane.yaml"
VIZ_FILE="$MANIFEST_DIR/linkerd-viz.yaml"
INGRESS_FILE="$MANIFEST_DIR/dashboard.yaml"
GRAFANA_FILE="$MANIFEST_DIR/linkerd-grafana.yaml"
LINKERD_BIN="${HOME}/.linkerd2/bin/linkerd"

REDEPLOY=false

print_status() { echo -e "${GREEN}[INFO]${NC} $1"; }
print_warn()   { echo -e "${YELLOW}[WARN]${NC} $1"; }
print_error()  { echo -e "${RED}[ERROR]${NC} $1"; exit 1; }

ensure_file() {
  [[ -f "$1" ]] || print_error "Required file not found: $1"
}

kubectl() {
  command kubectl --kubeconfig "$KUBECONFIG_PATH" "$@"
}

wait_for_deployments_ready_in_ns() {
  local ns="$1"
  local timeout="${2:-300s}"   # default 300s
  print_status "Waiting for all deployments in namespace '$ns' to be available (timeout: $timeout)..."

  mapfile -t deployments < <(kubectl -n "$ns" get deploy -o name || true)
  if [[ ${#deployments[@]} -eq 0 ]]; then
    print_warn "No deployments found in namespace '$ns'. Skipping wait."
    return
  fi

  for d in "${deployments[@]}"; do
    print_status "Waiting for $d..."
    kubectl -n "$ns" rollout status "$d" --timeout="$timeout"
  done
}

# Update --enforced-host line in the Linkerd dashboard manifest if it exists
update_enforced_host() {
    local manifest_file="$1"
    local enforced_hosts="localhost|127\.0\.0\.1|web\.linkerd-viz\.svc\.cluster\.local|web\.linkerd-viz\.svc|\[::1\]|linkerd.local|grafana\.linkerd.local|prometheus\.linkerd.local"

    if [[ ! -f "$manifest_file" ]]; then
        print_warn "Manifest file not found: $manifest_file"
        return
    fi

    # Detect OS for sed compatibility
    local SED_INPLACE
    if [[ "$(uname)" == "Darwin" ]]; then
        SED_INPLACE=(-i '')
    else
        SED_INPLACE=(-i)
    fi

    # Only update if the --enforced-host line exists
    if grep -q -- '--enforced-host=' "$manifest_file"; then
        print_status "Updating --enforced-host line in $manifest_file"
        sed "${SED_INPLACE[@]}" -E "s#(--enforced-host=).*#\1^($enforced_hosts)(:\\d+)?$#" "$manifest_file"
    else
        print_status "--enforced-host line not found in $manifest_file — skipping"
    fi
}

parse_args() {
  for arg in "$@"; do
    case "$arg" in
      --redeploy) REDEPLOY=true ;;
      -h|--help)
        echo "Usage: $0 [--redeploy]"
        echo
        echo "  --redeploy    Delete existing Linkerd control plane & viz before reapplying"
        exit 0
        ;;
      *) print_error "Unknown argument: $arg" ;;
    esac
  done
}

main() {
  parse_args "$@"

  print_status "Using kubeconfig: $KUBECONFIG_PATH"
  [[ -f "$KUBECONFIG_PATH" ]] || print_error "Kubeconfig not found at $KUBECONFIG_PATH"

  # Ensure manifest files exist
  ensure_file "$CRDS_FILE"
  ensure_file "$CONTROL_PLANE_FILE"
  ensure_file "$VIZ_FILE"
  ensure_file "$INGRESS_FILE"
  ensure_file "$GRAFANA_FILE"

  # 1) Apply CRDs (always safe to reapply)
  print_status "Applying Linkerd CRDs: $CRDS_FILE"
  kubectl apply -f "$CRDS_FILE"

  # 2) Optionally redeploy control plane
  if $REDEPLOY; then
    print_warn "Redeploy mode enabled: deleting control plane first"
    kubectl delete -f "$CONTROL_PLANE_FILE" --ignore-not-found || true
  fi
  print_status "Applying Linkerd control plane manifest: $CONTROL_PLANE_FILE"
  kubectl apply -f "$CONTROL_PLANE_FILE"

  # 3) Wait for control plane to be ready
  wait_for_deployments_ready_in_ns "linkerd" "300s"

  # 4) Optionally redeploy viz
  if $REDEPLOY; then
    print_warn "Redeploy mode enabled: deleting viz extension first"
    kubectl delete -f "$VIZ_FILE" --ignore-not-found || true
  fi
  print_status "Applying Linkerd Viz manifest: $VIZ_FILE"
  kubectl apply -f "$VIZ_FILE"

  # 5) Wait for Viz
  wait_for_deployments_ready_in_ns "linkerd-viz" "300s"

  # 6) Apply dashboard ingress
  print_status "Updating --enforced-host line in dashboard manifest"
  update_enforced_host "$VIZ_FILE"

  print_status "Applying Linkerd Ingress/Dashboard manifest: $INGRESS_FILE"
  kubectl apply -f "$INGRESS_FILE"

  # 7) Run linkerd check
  if command -v linkerd >/dev/null 2>&1; then
    print_status "Running 'linkerd check'..."
    linkerd check --wait=120s
  elif [[ -x "$LINKERD_BIN" ]]; then
    print_status "Running 'linkerd check' using $LINKERD_BIN..."
    "$LINKERD_BIN" check --wait=120s
  else
    print_warn "Linkerd CLI not found on PATH."
    print_status "Install it with: curl --proto '=https' --tlsv1.2 -sSfL https://run.linkerd.io/install | sh"
  fi

  # 8) Deploy Grafana
  if $REDEPLOY; then
    print_warn "Redeploy mode enabled: deleting Grafana first"
    kubectl delete -f "$GRAFANA_FILE" --ignore-not-found || true
  fi
  print_status "Applying Grafana manifest: $GRAFANA_FILE"
  kubectl apply -f "$GRAFANA_FILE"
  wait_for_deployments_ready_in_ns "linkerd-grafana" "300s"

  print_status "Linkerd deployment finished."
  echo
  print_status "Helpful commands:"
  echo "  kubectl --kubeconfig $KUBECONFIG_PATH get pods -n linkerd"
  echo "  kubectl --kubeconfig $KUBECONFIG_PATH get pods -n linkerd-viz"
  echo "  kubectl --kubeconfig $KUBECONFIG_PATH get pods -n linkerd-grafana"
  echo "  linkerd check"
  echo "  linkerd viz dashboard"
  echo "  kubectl -n linkerd-grafana port-forward svc/grafana 3000:3000"
}

main "$@"