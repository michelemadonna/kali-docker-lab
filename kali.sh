#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage: ./kali.sh --name NAME [--minimal|--full|--profile LIST] [options]

Required:
  --name NAME                Name to assign to the Docker container

Options:
  --build                    Build the image before starting Kali
  --gui no|openbox|xfce      Select desktop; otherwise use DESKTOP from .env
  --minimal                  Omit base/tools; install only GUI packages if selected
  --full                     Install all optional profiles
  --profile LIST             Install comma-separated profiles (or --profile=LIST)
                             network, web, ad, exploitation, osint, wireless
  --no-privileged            Use selected capabilities (bridge mode only)
  --network host             Use host networking (default for new containers)
  --network bridge            Use KALI_DOCKER_NETWORK from .env or its default
  --network bridge=NAME       Use the specified existing Docker network
  -h, --help                 Show this help

--minimal, --full, --profile, and --gui require --build. When creating an
image, choose profiles in .env or with --minimal, --full, or --profile.
An existing container can be started with --name alone.
Without --network, an existing container keeps its current network. Switching
between host and bridge requires removing and recreating the container.
--minimal without a GUI has no APT-installed packages or services; use docker exec.
With DESKTOP in .env or --gui, minimal installs only the packages for that GUI.
--no-privileged uses NET_RAW, NET_ADMIN, and NET_BIND_SERVICE capabilities.
Host networking always uses --privileged; --no-privileged requires bridge mode.

Examples:
  ./kali.sh --name kali-lab --build --gui xfce --profile osint,wireless
  ./kali.sh --name kali-lab --build --profile=ad,exploitation
  ./kali.sh --name kali-lab
EOF
}

fail() {
  printf 'Error: %s\n' "$*" >&2
  exit 2
}

# Read only the simple KEY=value entries this launcher consumes. Shell
# environment variables take precedence over values from .env.
dotenv_value() {
  local key=$1 default_value=$2 value=''
  if [[ -n "${!key-}" ]]; then
    printf '%s' "${!key}"
    return
  fi
  if [[ -f .env ]]; then
    value=$(awk -v key="$key" '
      /^[[:space:]]*#/ || /^[[:space:]]*$/ { next }
      {
        line = $0
        sub(/\r$/, "", line)
        if (line ~ "^[[:space:]]*" key "[[:space:]]*=") {
          sub("^[[:space:]]*" key "[[:space:]]*=[[:space:]]*", "", line)
          sub(/[[:space:]]+#.*$/, "", line)
          if (line ~ /^".*"$/ || line ~ /^\047.*\047$/) line = substr(line, 2, length(line) - 2)
          found = line
        }
      }
      END { if (found != "") print found }
    ' .env)
  fi
  if [[ -n "$value" ]]; then
    printf '%s' "$value"
  else
    printf '%s' "$default_value"
  fi
}

desktop=openbox
gui_requested=false
network_mode=host
network_name=
network_requested=false
no_privileged=false
container_name=
build=false
profile_selector=
profile_arg=

while (($#)); do
  case "$1" in
    --name)
      (($# >= 2)) || fail '--name requires a container name'
      [[ -n "$2" && "$2" != -* ]] || fail '--name requires a non-empty container name'
      container_name=$2
      shift 2
      ;;
    --build)
      build=true
      shift
      ;;
    --no-privileged)
      no_privileged=true
      shift
      ;;
    --gui)
      (($# >= 2)) || fail '--gui requires no, openbox, or xfce'
      case "$2" in
        no|openbox) desktop="$2" ;;
        xfce) desktop=xfce-kali ;;
        *) fail "unsupported GUI '$2' (expected no, openbox, or xfce)" ;;
      esac
      gui_requested=true
      shift 2
      ;;
    --minimal)
      [[ -z "$profile_selector" ]] || fail '--minimal, --full, and --profile are mutually exclusive'
      profile_selector=minimal
      shift
      ;;
    --full)
      [[ -z "$profile_selector" ]] || fail '--minimal, --full, and --profile are mutually exclusive'
      profile_selector=full
      shift
      ;;
    --profile)
      (($# >= 2)) || fail '--profile requires a comma-separated profile list'
      [[ -z "$profile_selector" ]] || fail '--minimal, --full, and --profile are mutually exclusive'
      profile_selector=cli
      profile_arg=$2
      shift 2
      ;;
    --profile=*)
      [[ -z "$profile_selector" ]] || fail '--minimal, --full, and --profile are mutually exclusive'
      profile_selector=cli
      profile_arg=${1#--profile=}
      shift
      ;;
    --network)
      (($# >= 2)) || fail '--network requires host, bridge, or bridge=NAME'
      network_arg=$2
      network_requested=true
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

[[ -n "$container_name" ]] || fail '--name NAME is required'
if [[ "$build" != true ]]; then
  [[ "$profile_selector" == '' ]] || fail '--minimal, --full, and --profile can only be used with --build'
  [[ "$gui_requested" == false ]] || fail '--gui can only be used with --build'
fi

project_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
cd "$project_dir"

timezone=$(dotenv_value TZ Etc/UTC)
locale=$(dotenv_value LANG C.UTF-8)
all_profiles=network,web,ad,exploitation,osint,wireless
normalize_profiles() {
  local raw=$1 token result='' item
  local -a requested=() normalized=()
  [[ -n "$raw" ]] || fail 'profile list is empty'
  IFS=',' read -r -a requested <<< "$raw"
  for token in "${requested[@]}"; do
    token="${token#"${token%%[![:space:]]*}"}"
    token="${token%"${token##*[![:space:]]}"}"
    [[ -n "$token" ]] || fail 'profile list contains an empty entry'
    case "$token" in
      network|web|ad|exploitation|osint|wireless) ;;
      *) fail "unsupported profile '$token' (expected network, web, ad, exploitation, osint, or wireless)" ;;
    esac
    local duplicate=false
    if ((${#normalized[@]})); then
      for item in "${normalized[@]}"; do
        [[ "$item" == "$token" ]] && duplicate=true
      done
    fi
    if [[ "$duplicate" == false ]]; then
      normalized+=("$token")
    fi
  done
  if ((${#normalized[@]})); then
    local IFS=,
    result="${normalized[*]}"
  fi
  printf '%s' "$result"
}

canonical_profiles() {
  local raw=$1 selected='' profile result=''
  if [[ -n "$raw" ]]; then
    selected=$(normalize_profiles "$raw")
  fi
  for profile in network web ad exploitation osint wireless; do
    case ",$selected," in
      *",$profile,"*) result="${result:+$result,}$profile" ;;
    esac
  done
  printf '%s' "$result"
}

timezone=$(dotenv_value TZ Etc/UTC)
locale=$(dotenv_value LANG C.UTF-8)
if [[ "$network_mode" == bridge && -z "$network_name" && "$network_requested" == true ]]; then
  network_name=$(dotenv_value KALI_DOCKER_NETWORK kali-lab-bridge)
fi

image=local/kali-offsec-lab:rolling
container_status=$(docker container inspect --format '{{.State.Status}}' "$container_name" 2>/dev/null) \
  && container_exists=true || container_exists=false

if [[ "$container_exists" == true && "$build" == true ]]; then
  fail "a Docker container named '$container_name' already exists; remove it explicitly before using --build"
fi

if [[ "$no_privileged" == true ]]; then
  if [[ "$container_exists" == true && "$network_requested" == false ]]; then
    effective_network_mode=$(docker container inspect --format '{{.HostConfig.NetworkMode}}' "$container_name")
  else
    effective_network_mode=$network_mode
  fi
  [[ "$effective_network_mode" != host ]] \
    || fail '--no-privileged requires bridge networking; host networking always uses --privileged'
fi

minimal_build=false
if [[ "$container_exists" == false ]]; then
  if [[ "$gui_requested" == false ]]; then
    desktop_setting=$(dotenv_value DESKTOP '')
    if [[ -n "${desktop_setting//[[:space:]]/}" ]]; then
      desktop=$desktop_setting
    elif [[ "$profile_selector" == minimal ]]; then
      desktop=no
    else
      desktop=openbox
    fi
    case "$desktop" in
      no|openbox) ;;
      xfce|xfce-kali) desktop=xfce-kali ;;
      *) fail "unsupported DESKTOP '$desktop' (expected no, openbox, or xfce-kali)" ;;
    esac
  fi
  [[ "$profile_selector" == minimal ]] && minimal_build=true
fi

profile_selection_present=false
if [[ "$profile_selector" == minimal ]]; then
  profiles=
  profile_selection_present=true
elif [[ "$profile_selector" == full ]]; then
  profiles=$all_profiles
  profile_selection_present=true
elif [[ "$profile_selector" == cli ]]; then
  profiles=$(normalize_profiles "$profile_arg")
  profile_selection_present=true
elif [[ -z "$profile_selector" ]]; then
  profile_arg=$(dotenv_value PROFILES '')
  if [[ -n "${profile_arg//[[:space:]]/}" ]]; then
    profiles=$(normalize_profiles "$profile_arg")
    profile_selection_present=true
  elif [[ "$container_exists" == false || "$build" == true ]]; then
    fail 'select --minimal, --full, --profile LIST, or set PROFILES in .env'
  else
    profiles=
  fi
else
  fail 'invalid profile selector'
fi

if [[ "$container_exists" == true ]]; then
  container_image=$(docker container inspect --format '{{.Image}}' "$container_name")
  container_network_mode=$(docker container inspect --format '{{.HostConfig.NetworkMode}}' "$container_name")
  if [[ "$profile_selection_present" == true ]]; then
    image_profiles=$(docker image inspect --format '{{ index .Config.Labels "local.kali.profiles" }}' "$container_image" 2>/dev/null) \
      || fail "cannot read the profile label for container '$container_name'"
    [[ "$(canonical_profiles "$image_profiles")" == "$(canonical_profiles "$profiles")" ]] \
      || fail "container '$container_name' uses profiles '$image_profiles', not requested '$profiles'"
  fi

  if [[ "$container_network_mode" == host ]]; then
    container_privileged=$(docker container inspect --format '{{.HostConfig.Privileged}}' "$container_name")
    [[ "$container_privileged" == true ]] \
      || fail "host-networked container '$container_name' must be privileged; remove and recreate it"
  fi

  if [[ "$no_privileged" == true ]]; then
    container_privileged=$(docker container inspect --format '{{.HostConfig.Privileged}}' "$container_name")
    [[ "$container_privileged" == false ]] \
      || fail "container '$container_name' was created with --privileged; remove and recreate it to apply --no-privileged"
    container_cap_add=$(docker container inspect --format '{{json .HostConfig.CapAdd}}' "$container_name")
    for capability in NET_RAW NET_ADMIN NET_BIND_SERVICE; do
      [[ "$container_cap_add" == *"\"$capability\""* ]] \
        || fail "container '$container_name' lacks $capability; remove and recreate it with --no-privileged"
    done
  fi

  if [[ "$network_requested" == true ]]; then
    current_network_mode=$container_network_mode
    if [[ "$network_mode" == host || "$current_network_mode" == host ]]; then
      [[ "$network_mode" == host && "$current_network_mode" == host ]] \
        || fail "container '$container_name' cannot switch between host and bridge networking; remove it explicitly and rerun kali.sh"
    elif [[ "$current_network_mode" != "$network_name" ]]; then
      attached_network_count=$(docker container inspect --format '{{len .NetworkSettings.Networks}}' "$container_name")
      [[ "$attached_network_count" == 1 ]] \
        || fail "container '$container_name' has multiple attached networks; disconnect them manually before changing its bridge network"
      docker network connect "$network_name" "$container_name" \
        || fail "could not connect '$container_name' to bridge network '$network_name'; its existing network was kept"
      if ! docker network disconnect "$current_network_mode" "$container_name"; then
        if docker network disconnect "$network_name" "$container_name" >/dev/null 2>&1; then
          fail "could not disconnect '$container_name' from '$current_network_mode'; reverted the requested bridge connection"
        fi
        fail "could not disconnect '$container_name' from '$current_network_mode' and could not revert '$network_name'; inspect its network attachments manually"
      fi
    fi
  fi

  if [[ "$container_status" != running ]]; then
    docker start "$container_name"
  else
    printf "Container '%s' is already running.\n" "$container_name"
  fi
  exit 0
fi

if [[ "$build" == true ]]; then
  docker build \
    --build-arg "PROFILES=$profiles" \
    --build-arg "DESKTOP=$desktop" \
    --build-arg "MINIMAL=$minimal_build" \
    --label "local.kali.profiles=$profiles" \
    --label "local.kali.desktop=$desktop" \
    --tag "$image" \
    .
else
  image_profiles=$(docker image inspect --format '{{ index .Config.Labels "local.kali.profiles" }}' "$image" 2>/dev/null) \
    || fail "image '$image' not found; build it with --build"
  [[ "$image_profiles" == "$profiles" ]] \
    || fail "image profiles '$image_profiles' do not match requested '$profiles'; rebuild with --build"
  image_desktop=$(docker image inspect --format '{{ index .Config.Labels "local.kali.desktop" }}' "$image" 2>/dev/null) \
    || fail "cannot read the desktop label for image '$image'"
  [[ "$image_desktop" == "$desktop" ]] \
    || fail "image desktop '$image_desktop' does not match requested '$desktop'; rebuild with --build"
fi

run_args=(
  --detach
  --name "$container_name"
  --hostname kali-lab
  --restart unless-stopped
  --init
  --add-host kali-lab:127.0.1.1
  --env "DESKTOP=$desktop"
  --env "TZ=$timezone"
  --env "LANG=$locale"
  --env "KALI_NETWORK_MODE=$network_mode"
  --env KALI_PASSWORD_FILE=/run/secrets/kali_password
  --mount "type=volume,src=kali-lab_ssh_host_keys,dst=/etc/ssh/hostkeys"
  --mount "type=volume,src=kali-lab_metasploit_data,dst=/var/lib/postgresql/data"
  --mount "type=bind,src=$project_dir/workspace,dst=/home/kali/workspace"
  --mount "type=bind,src=$project_dir/secrets/authorized_keys,dst=/run/secrets/authorized_keys,readonly"
  --mount "type=bind,src=$project_dir/secrets/kali_password,dst=/run/secrets/kali_password,readonly"
  --mount "type=bind,src=$project_dir/secrets/postgres_password,dst=/run/secrets/postgres_password,readonly"
)

if [[ "$no_privileged" == true ]]; then
  run_args+=(--cap-add=NET_RAW --cap-add=NET_ADMIN --cap-add=NET_BIND_SERVICE)
else
  run_args+=(--privileged)
fi

if [[ "$network_mode" == host ]]; then
  run_args+=(--network host)
else
  [[ -n "$network_name" ]] || fail 'the bridge network name is empty'
  run_args+=(
    --network "$network_name"
    --publish 50022:50022
    --publish 53389:53389
  )
fi

docker run "${run_args[@]}" "$image"
