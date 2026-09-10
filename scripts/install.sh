#!/bin/bash
set -euo pipefail
PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
WORKFLOW="$PROJECT_DIR/build/Install on Device.workflow"
# Override only for isolated installation tests.
SERVICES_DIR="${INSTALL_SERVICES_DIR:-$HOME/Library/Services}"
if [[ ! -x "$WORKFLOW/Contents/Resources/Install on Device.app/Contents/MacOS/DeviceInstaller" ]]; then
  "$PROJECT_DIR/scripts/build.sh"
fi
mkdir -p "$SERVICES_DIR"
/usr/bin/ditto "$WORKFLOW" "$SERVICES_DIR/Install on Device.workflow"
/usr/bin/codesign --verify --deep --strict "$SERVICES_DIR/Install on Device.workflow/Contents/Resources/Install on Device.app"
if [[ -z "${INSTALL_SERVICES_DIR:-}" ]]; then
  /System/Library/CoreServices/pbs -update || printf 'Services refresh unavailable; Finder may need to be reopened.\n' >&2
fi
printf 'Installed: %s\n' "$SERVICES_DIR/Install on Device.workflow"
