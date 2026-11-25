#!/usr/bin/env bash
#
# Installs the tools below (if missing or at the wrong version) and registers
# the git hooks.
#
# Usage:
#   ./setup.sh
#   ./setup.sh --bin-dir DIR
#
# --bin-dir: install binaries there, without modifying shell profiles.

set -euo pipefail

((BASH_VERSINFO[0] >= 4)) || {
    echo "ERROR: bash 4+ is required" >&2
    exit 1
}

cd "$(dirname "${BASH_SOURCE[0]}")"

BIN_DIR=""

if [[ ${1:-} == --bin-dir ]]; then
    [[ -n ${2:-} && $# -eq 2 ]] || {
        echo "ERROR: --bin-dir requires exactly one directory path" >&2
        exit 1
    }

    BIN_DIR=$2
    mkdir -p "$BIN_DIR"
    BIN_DIR=$(cd "$BIN_DIR" && pwd -P)
    export PATH="$BIN_DIR:$PATH"

    echo "==> Using custom binary directory: $BIN_DIR"
elif [[ $# -eq 0 ]]; then
    # Installers only edit shell profiles, which this running script can't see,
    # so add the default install locations here for the checks below.
    export PATH="$HOME/.local/bin:$HOME/.cargo/bin:$PATH"
else
    echo "ERROR: unknown argument: $1" >&2
    echo "Usage: ./setup.sh [--bin-dir DIR]" >&2
    exit 1
fi

declare -A TOOLS=(
    # latex engine
    [tectonic]="https://raw.githubusercontent.com/hethon/ingen/v0.4.1/examples/tectonic/installers/installer.sh"
    [tectonic,version]="0.17.0"

    # formatter and linter
    [badness]="https://raw.githubusercontent.com/hethon/ingen/v0.4.1/examples/badness/installers/installer.sh"
    [badness,version]="0.28.0"

    # changelog manager
    [knope]="https://raw.githubusercontent.com/hethon/ingen/v0.4.1/examples/knope/installers/installer.sh"
    [knope,version]="0.24.0"

    # precommit hooks manager
    [prek]="https://github.com/j178/prek/releases/download/v0.5.9/prek-installer.sh"
    [prek,version]="0.5.9"

    # pdf diff generator
    [latexdiff]="https://github.com/hethon/latexdiff-bin/releases/download/v1.4.0-2/installer.sh"
    [latexdiff,version]="1.4.0"

    # biblatex backend
    [biber]="https://github.com/hethon/biber-bin/releases/download/v2.17/installer.sh"
    [biber,version]="2.17"
)

installed_ok() {
    local bin=$1
    local version=$2
    local out

    command -v "$bin" >/dev/null 2>&1 || return 1

    out=$("$bin" --version 2>&1) || return 1

    grep -qF -- "$version" <<<"$out"
}

install_tool() {
    local bin=$1
    local url=$2
    local version=$3
    local var

    if [[ -z $BIN_DIR ]] && installed_ok "$bin" "$version"; then
        echo "==> $bin $version ok"
        return 0
    fi

    echo "==> Installing $bin ($version)"

    if [[ -n $BIN_DIR ]]; then
        # Example:
        #   tectonic -> TECTONIC_UNMANAGED_INSTALL
        var="${bin^^}"
        var="${var//-/_}_UNMANAGED_INSTALL"

        curl --proto '=https' --tlsv1.2 -LsSf "$url" |
            env "$var=$BIN_DIR" sh
    else
        curl --proto '=https' --tlsv1.2 -LsSf "$url" | sh
    fi

    # Clear Bash's cached command locations after installation.
    hash -r

    if ! installed_ok "$bin" "$version"; then
        echo "ERROR: $bin installation failed or wrong version installed." >&2
        echo "Expected version: $version" >&2
        echo "Check that the installation directory is on PATH." >&2
        return 1
    fi

    echo "==> $bin installed successfully"
}

# keys without a comma are the tools; sort for stable output
for bin in $(printf '%s\n' "${!TOOLS[@]}" | sort); do
    [[ $bin == *,* ]] && continue
    install_tool "$bin" "${TOOLS[$bin]}" "${TOOLS[$bin,version]}"
done

echo "==> Registering git hooks"
prek install

echo "==> Done."

if [[ -n $BIN_DIR ]]; then
    echo "    Binaries installed in: $BIN_DIR"
    echo "    Build with: $BIN_DIR/tectonic -X build"
else
    echo "    Open a new terminal (and restart VS Code) so the new tools are on PATH."
    echo "    Build with: tectonic -X build"
fi
