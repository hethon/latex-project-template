#!/usr/bin/env bash
# Installs tectonic, badness and prek (if missing) and registers the git hooks.

set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")"

install_if_missing() {
  local bin=$1 url=$2
  if command -v "$bin" >/dev/null; then
    echo "==> $bin already installed"
  else
    echo "==> Installing $bin"
    curl --proto '=https' --tlsv1.2 -LsSf "$url" | sh
    hash -r

    # Just a sanity check
    if ! command -v "$bin" >/dev/null; then
      echo "ERROR: '$bin' was not found on PATH after installation. Check the installer output." >&2
      exit 1
    fi
  fi
}

install_if_missing tectonic "https://raw.githubusercontent.com/hethon/ingen/refs/heads/master/examples/tectonic/installers/installer.sh"
install_if_missing badness "https://raw.githubusercontent.com/hethon/ingen/master/examples/badness/installers/installer.sh"
install_if_missing prek "https://github.com/j178/prek/releases/download/v0.5.9/prek-installer.sh"

echo "==> Registering git hooks"
prek install

echo "==> Done. Build with: nextonic build"
