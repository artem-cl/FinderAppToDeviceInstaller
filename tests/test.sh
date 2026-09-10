#!/bin/bash
set -euo pipefail
PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
"$PROJECT_DIR/scripts/build.sh"
"$PROJECT_DIR/build/Install on Device.workflow/Contents/Resources/Install on Device.app/Contents/MacOS/DeviceInstaller" --self-test
TEST_DIR=$(mktemp -d)
trap 'rm -rf -- "$TEST_DIR"' EXIT
export INSTALL_SERVICES_DIR="$TEST_DIR/Services with spaces"
"$PROJECT_DIR/scripts/install.sh"
[[ -f "$INSTALL_SERVICES_DIR/Install on Device.workflow/Contents/document.wflow" ]]
"$PROJECT_DIR/scripts/uninstall.sh"
[[ ! -e "$INSTALL_SERVICES_DIR/Install on Device.workflow" ]]
"$PROJECT_DIR/scripts/uninstall.sh"
printf 'PASS: build, package, isolated install and uninstall\n'
