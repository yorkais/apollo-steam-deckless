#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'USAGE'
Usage:
  setup-linux-sunshine-appimage.sh [options]

Options:
  --base-dir PATH       Isolated game-stream directory. Default: $HOME/game-stream
  --display DISPLAY     X11 display Sunshine should capture. Default: current $DISPLAY or :0
  --version TAG         Sunshine release tag. Default: v2025.924.154138
  --appimage-url URL    Override Sunshine AppImage URL.
  -h, --help            Show this help.

This installs no system packages. It creates an isolated AppImage-based Sunshine
runtime with HOME and XDG paths redirected under --base-dir.
USAGE
}

BASE_DIR="${HOME}/game-stream"
SUNSHINE_VERSION="v2025.924.154138"
SUNSHINE_DISPLAY="${DISPLAY:-:0}"
SUNSHINE_APPIMAGE_URL=""

while [ "$#" -gt 0 ]; do
  case "$1" in
    --base-dir)
      BASE_DIR="${2:?missing value for --base-dir}"
      shift 2
      ;;
    --display)
      SUNSHINE_DISPLAY="${2:?missing value for --display}"
      shift 2
      ;;
    --version)
      SUNSHINE_VERSION="${2:?missing value for --version}"
      shift 2
      ;;
    --appimage-url)
      SUNSHINE_APPIMAGE_URL="${2:?missing value for --appimage-url}"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown option: $1" >&2
      usage >&2
      exit 2
      ;;
  esac
done

if [ -z "$SUNSHINE_APPIMAGE_URL" ]; then
  SUNSHINE_APPIMAGE_URL="https://github.com/LizardByte/Sunshine/releases/download/${SUNSHINE_VERSION}/sunshine.AppImage"
fi

mkdir -p "$BASE_DIR"/{bin,apps,config,cache,state,logs,run,steam-library,tmp,home,docs}
chmod 700 "$BASE_DIR" "$BASE_DIR"/{config,cache,state,logs,run,tmp} "$BASE_DIR/home"
chmod 755 "$BASE_DIR"/{bin,apps,steam-library,docs}

cat > "$BASE_DIR/config/host.env" <<EOF
GAME_BASE="$BASE_DIR"
SUNSHINE_DISPLAY="$SUNSHINE_DISPLAY"
SUNSHINE_VERSION="$SUNSHINE_VERSION"
SUNSHINE_APPIMAGE_URL="$SUNSHINE_APPIMAGE_URL"
EOF
chmod 600 "$BASE_DIR/config/host.env"

app="$BASE_DIR/apps/sunshine-${SUNSHINE_VERSION}.AppImage"
if [ ! -s "$app" ]; then
  tmp="$app.tmp"
  rm -f "$tmp"
  if command -v curl >/dev/null 2>&1; then
    curl -fL --retry 3 --connect-timeout 20 -o "$tmp" "$SUNSHINE_APPIMAGE_URL"
  elif command -v wget >/dev/null 2>&1; then
    wget -O "$tmp" "$SUNSHINE_APPIMAGE_URL"
  else
    echo "curl or wget is required to download Sunshine." >&2
    exit 1
  fi
  mv "$tmp" "$app"
fi
chmod +x "$app"
ln -sfn "$app" "$BASE_DIR/apps/sunshine.AppImage"

cat > "$BASE_DIR/bin/game-env" <<'SCRIPT'
#!/usr/bin/env bash
set -euo pipefail
if [ -z "${GAME_BASE:-}" ]; then
  script_dir="$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
  GAME_BASE="$(CDPATH= cd -- "$script_dir/.." && pwd -P)"
fi
export GAME_BASE
export HOME="$GAME_BASE/home"
export XDG_CONFIG_HOME="$GAME_BASE/config"
export XDG_CACHE_HOME="$GAME_BASE/cache"
export XDG_DATA_HOME="$GAME_BASE/state/share"
export XDG_STATE_HOME="$GAME_BASE/state"
export XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"
export STEAM_COMPAT_DATA_PATH="$GAME_BASE/state/steam-compat"
export STEAM_COMPAT_CLIENT_INSTALL_PATH="$GAME_BASE/state/steam-client"
export TMPDIR="$GAME_BASE/tmp"
export NVIDIA_DRIVER_CAPABILITIES="${NVIDIA_DRIVER_CAPABILITIES:-all}"
mkdir -p "$HOME" "$XDG_CONFIG_HOME" "$XDG_CACHE_HOME" "$XDG_DATA_HOME" \
  "$XDG_STATE_HOME" "$STEAM_COMPAT_DATA_PATH" "$STEAM_COMPAT_CLIENT_INSTALL_PATH" "$TMPDIR"
exec "$@"
SCRIPT

cat > "$BASE_DIR/bin/show-game-env" <<'SCRIPT'
#!/usr/bin/env bash
set -euo pipefail
if [ -z "${GAME_BASE:-}" ]; then
  script_dir="$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
  GAME_BASE="$(CDPATH= cd -- "$script_dir/.." && pwd -P)"
fi
"$GAME_BASE/bin/game-env" bash -lc 'printf "GAME_BASE=%s\nHOME=%s\nXDG_CONFIG_HOME=%s\nXDG_CACHE_HOME=%s\nXDG_DATA_HOME=%s\nXDG_STATE_HOME=%s\nSTEAM_COMPAT_DATA_PATH=%s\nTMPDIR=%s\nDISPLAY=%s\nXDG_RUNTIME_DIR=%s\n" "$GAME_BASE" "$HOME" "$XDG_CONFIG_HOME" "$XDG_CACHE_HOME" "$XDG_DATA_HOME" "$XDG_STATE_HOME" "$STEAM_COMPAT_DATA_PATH" "$TMPDIR" "${DISPLAY:-}" "${XDG_RUNTIME_DIR:-}"'
SCRIPT

cat > "$BASE_DIR/bin/status-game-stream" <<'SCRIPT'
#!/usr/bin/env bash
set -euo pipefail
if [ -z "${GAME_BASE:-}" ]; then
  script_dir="$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
  GAME_BASE="$(CDPATH= cd -- "$script_dir/.." && pwd -P)"
fi
echo '=== game env ==='
"$GAME_BASE/bin/show-game-env"
echo '=== sunshine processes ==='
pgrep -a -u "$(id -u)" -f "${GAME_BASE}/apps/sunshine.AppImage|${GAME_BASE}/tmp/.mount.*sunshine|/usr/bin/sunshine" || true
echo '=== sunshine ports ==='
ss -lntup 2>/dev/null | grep -E ':(47984|47989|47990|48010)\b' || true
echo '=== gpu ==='
nvidia-smi --query-gpu=index,name,utilization.gpu,memory.used,power.draw --format=csv 2>/dev/null || true
SCRIPT

cat > "$BASE_DIR/bin/start-sunshine" <<'SCRIPT'
#!/usr/bin/env bash
set -euo pipefail
if [ -z "${GAME_BASE:-}" ]; then
  script_dir="$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
  GAME_BASE="$(CDPATH= cd -- "$script_dir/.." && pwd -P)"
fi
if [ -f "$GAME_BASE/config/host.env" ]; then
  # shellcheck disable=SC1091
  . "$GAME_BASE/config/host.env"
fi
LOG_DIR="$GAME_BASE/logs"
mkdir -p "$LOG_DIR" "$GAME_BASE/run"
export DISPLAY="${SUNSHINE_DISPLAY:-${DISPLAY:-:0}}"
export XAUTHORITY="${XAUTHORITY:-/run/user/$(id -u)/gdm/Xauthority}"
export PULSE_SERVER="${PULSE_SERVER:-unix:/run/user/$(id -u)/pulse/native}"

if pgrep -u "$(id -u)" -f "${GAME_BASE}/apps/sunshine.AppImage|${GAME_BASE}/tmp/.mount.*sunshine|/usr/bin/sunshine" >/dev/null 2>&1; then
  echo "Sunshine already appears to be running for $(id -un)."
  "$GAME_BASE/bin/status-game-stream"
  exit 0
fi

nohup "$GAME_BASE/bin/game-env" "$GAME_BASE/apps/sunshine.AppImage" "$@" >> "$LOG_DIR/sunshine.log" 2>&1 &
echo $! > "$GAME_BASE/run/sunshine.pid"
sleep 3
"$GAME_BASE/bin/status-game-stream"
SCRIPT

cat > "$BASE_DIR/bin/stop-sunshine" <<'SCRIPT'
#!/usr/bin/env bash
set -euo pipefail
if [ -z "${GAME_BASE:-}" ]; then
  script_dir="$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
  GAME_BASE="$(CDPATH= cd -- "$script_dir/.." && pwd -P)"
fi
pids="$(pgrep -u "$(id -u)" -f "${GAME_BASE}/apps/sunshine.AppImage|${GAME_BASE}/tmp/.mount.*sunshine|/usr/bin/sunshine" || true)"
if [ -n "$pids" ]; then
  for pid in $pids; do
    kill "$pid" 2>/dev/null || true
  done
  sleep 2
  for pid in $pids; do
    kill -0 "$pid" 2>/dev/null && kill -9 "$pid" 2>/dev/null || true
  done
fi
rm -f "$GAME_BASE/run/sunshine.pid"
SCRIPT

cat > "$BASE_DIR/bin/sunshine-set-creds" <<'SCRIPT'
#!/usr/bin/env bash
set -euo pipefail
if [ "$#" -ne 2 ]; then
  echo "usage: $0 <username> <password>" >&2
  exit 2
fi
if [ -z "${GAME_BASE:-}" ]; then
  script_dir="$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
  GAME_BASE="$(CDPATH= cd -- "$script_dir/.." && pwd -P)"
fi
"$GAME_BASE/bin/game-env" "$GAME_BASE/apps/sunshine.AppImage" --creds "$1" "$2"
SCRIPT

cat > "$BASE_DIR/bin/fix-sunshine-input-permissions.sh" <<'SCRIPT'
#!/usr/bin/env bash
set -euo pipefail
if [ "$(id -u)" -ne 0 ]; then
  echo "Run with sudo: sudo $0 [user]" >&2
  exit 1
fi

target_user="${1:-${SUDO_USER:-}}"
if [ -z "$target_user" ] || [ "$target_user" = "root" ]; then
  echo "Pass the desktop user: sudo $0 <user>" >&2
  exit 2
fi

getent group input >/dev/null || groupadd --system input
install -m 0644 /dev/stdin /etc/udev/rules.d/85-sunshine-uinput.rules <<'RULE'
KERNEL=="uinput", GROUP="input", MODE="0660", OPTIONS+="static_node=uinput"
RULE
usermod -aG input "$target_user"
modprobe uinput || true
udevadm control --reload-rules
udevadm trigger /dev/uinput || true
if [ -e /dev/uinput ]; then
  chgrp input /dev/uinput || true
  chmod 0660 /dev/uinput || true
fi
echo "Sunshine input permission rule installed for $target_user. Re-login may be needed."
SCRIPT

chmod +x "$BASE_DIR"/bin/*

cat > "$BASE_DIR/docs/COMMANDS.md" <<EOF
# Commands

\`\`\`bash
$BASE_DIR/bin/start-sunshine
$BASE_DIR/bin/status-game-stream
$BASE_DIR/bin/stop-sunshine
$BASE_DIR/bin/sunshine-set-creds <username> <password>
\`\`\`

Fix Moonlight keyboard, mouse, and gamepad input once:

\`\`\`bash
sudo $BASE_DIR/bin/fix-sunshine-input-permissions.sh $(id -un)
\`\`\`

Open the Sunshine Web UI through SSH when only SSH is reachable:

\`\`\`bash
ssh -L 127.0.0.1:47990:127.0.0.1:47990 <host>
\`\`\`

Then browse to:

\`\`\`text
https://127.0.0.1:47990
\`\`\`
EOF

cat <<EOF
Prepared isolated Sunshine runtime:
  $BASE_DIR

Next:
  $BASE_DIR/bin/sunshine-set-creds <username> <password>
  $BASE_DIR/bin/start-sunshine
  sudo $BASE_DIR/bin/fix-sunshine-input-permissions.sh $(id -un)
EOF
