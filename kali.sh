#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage: ./kali.sh [options]

Options:
  --build                    Build the image before starting Kali
  --gui no|openbox|xfce      Select the desktop (default: openbox)
  --minimal                  Use MODE=minimal (default: full)
  --full                     Use MODE=full
  --network host             Use host networking (default)
  --network bridge            Use the existing network from KALI_DOCKER_NETWORK
  --network bridge=NAME       Use the specified existing Docker network
  -h, --help                 Show this help

Examples:
  ./kali.sh --build --gui xfce --minimal
  ./kali.sh --network bridge=lab-net --gui no
EOF
}

fail() {
  printf 'Error: %s\n' "$*" >&2
  exit 2
}

mode=full
desktop=openbox
network_mode=host
network_name=
build=false

while (($#)); do
  case "$1" in
    --build)
      build=true
      shift
      ;;
    --gui)
      (($# >= 2)) || fail '--gui requires no, openbox, or xfce'
      case "$2" in
        no|openbox) desktop="$2" ;;
        xfce) desktop=xfce-kali ;;
        *) fail "unsupported GUI '$2' (expected no, openbox, or xfce)" ;;
      esac
      shift 2
      ;;
    --minimal)
      mode=minimal
      shift
      ;;
    --full)
      mode=full
      shift
      ;;
    --network)
      (($# >= 2)) || fail '--network requires host, bridge, or bridge=NAME'
      network_arg=$2
      shift 2
      case "$network_arg" in
        host)
          network_mode=host
          network_name=
          ;;
        bridge)
          network_mode=bridge
          network_name=
          ;;
        bridge=*)
          network_mode=bridge
          network_name=${network_arg#bridge=}
          [[ -n "$network_name" ]] || fail '--network bridge= requires a network name'
          ;;
        *) fail "unsupported network '$network_arg' (expected host, bridge, or bridge=NAME)" ;;
      esac
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *) fail "unknown option '$1'" ;;
  esac
done

project_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
cd "$project_dir"

export MODE="$mode"
export DESKTOP="$desktop"

compose_files=(-f compose.yaml)
if [[ "$network_mode" == bridge ]]; then
  compose_files+=(-f compose.bridge.yaml)
  if [[ -n "$network_name" ]]; then
    export KALI_DOCKER_NETWORK="$network_name"
  fi
fi

compose=(docker compose "${compose_files[@]}")
if [[ "$build" == true ]]; then
  "${compose[@]}" up --build -d kali
else
  "${compose[@]}" up -d kali
fi
