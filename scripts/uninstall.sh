#!/bin/bash
set -euo pipefail
SERVICES_DIR="${INSTALL_SERVICES_DIR:-$HOME/Library/Services}"
WORKFLOW="$SERVICES_DIR/Install on Device.workflow"
if [[ ! -e "$WORKFLOW" ]]; then
  printf 'Install on Device is not installed.\n'
  exit 0
fi
IDENTIFIER=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$WORKFLOW/Contents/Info.plist")
if [[ "$IDENTIFIER" != 'local.artem.InstallOnDevice.QuickAction' ]]; then
  printf 'Refusing to remove an unrecognized workflow: %s\n' "$WORKFLOW" >&2
  exit 1
fi
rm -rf -- "$WORKFLOW"
if [[ -z "${INSTALL_SERVICES_DIR:-}" ]]; then
  /System/Library/CoreServices/pbs -update || true
fi
printf 'Removed: %s\n' "$WORKFLOW"
