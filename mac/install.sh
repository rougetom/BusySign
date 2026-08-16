#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
BIN_DIR="${HOME}/.local/bin"
LAUNCH_DIR="${HOME}/Library/LaunchAgents"
LABEL="com.busysign.reporter"
PLIST="${LAUNCH_DIR}/${LABEL}.plist"
BIN="${BIN_DIR}/busysign-reporter"
ENV_FILE="${HOME}/.busysign.env"

if ! command -v swiftc >/dev/null 2>&1; then
  echo "Install Xcode Command Line Tools first: xcode-select --install" >&2
  exit 1
fi

mkdir -p "${BIN_DIR}" "${LAUNCH_DIR}"

echo "Compiling menu bar reporter..."
swiftc -O -o "${BIN}" "${ROOT}/MicReporter.swift" -framework AppKit -framework CoreAudio -framework Foundation

if [[ ! -f "${ENV_FILE}" ]]; then
  read -r -p "Worker status URL (https://busy-sign.<account>.workers.dev/status): " WORKER_URL
  read -r -p "STATUS_SECRET token: " TOKEN
  umask 077
  cat > "${ENV_FILE}" <<EOF
BUSYSIGN_URL=${WORKER_URL}
BUSYSIGN_TOKEN=${TOKEN}
EOF
  echo "Wrote ${ENV_FILE}"
else
  echo "Using existing ${ENV_FILE}"
fi

cat > "${PLIST}" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key>
  <string>${LABEL}</string>
  <key>ProgramArguments</key>
  <array>
    <string>${BIN}</string>
  </array>
  <key>RunAtLoad</key>
  <true/>
  <key>KeepAlive</key>
  <dict>
    <key>SuccessfulExit</key>
    <false/>
  </dict>
  <key>LimitLoadToSessionType</key>
  <string>Aqua</string>
  <key>WorkingDirectory</key>
  <string>${HOME}</string>
</dict>
</plist>
EOF

launchctl bootout "gui/$(id -u)/${LABEL}" >/dev/null 2>&1 || true
launchctl bootstrap "gui/$(id -u)" "${PLIST}"
launchctl enable "gui/$(id -u)/${LABEL}" >/dev/null 2>&1 || true
launchctl kickstart -k "gui/$(id -u)/${LABEL}"

echo
echo "Reporter installed and started — look for a green/red dot in the menu bar."
echo "  Click to toggle Busy/Free. Right-click for Follow microphone."
echo "  Binary:  ${BIN}"
echo "  Config:  ${ENV_FILE}"
echo "  Agent:   ${PLIST}"
echo
echo "Logs: log stream --predicate 'process == \"busysign-reporter\"' --level debug"
echo "Stop: launchctl bootout gui/\$(id -u)/${LABEL}"
