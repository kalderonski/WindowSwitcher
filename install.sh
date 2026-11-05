#!/bin/zsh
# Builds and installs WindowSwitcher into /Applications, then launches it.
set -euo pipefail
cd "$(dirname "$0")"
./build.sh
pkill -f WindowSwitcher.app/Contents/MacOS || true
sleep 1
rm -rf /Applications/WindowSwitcher.app
ditto build/WindowSwitcher.app /Applications/WindowSwitcher.app
open /Applications/WindowSwitcher.app
