#!/usr/bin/env bash
#
# Builds a latexdiff PDF of src/ between two git revisions.
#
# Usage:
#   scripts/diff.sh [BASE] [HEAD] [OUT_PDF]
#
# BASE     any git ref or sha. The diff starts at merge-base(BASE, HEAD), so
#          for a rebased branch you only see the branch's own work.
#          Default: origin/master, else master.
# HEAD     any git ref or sha. When omitted, your working tree is used, so
#          uncommitted and untracked changes are included.
# OUT_PDF  Default: build/diff/diff-<base>-<head>.pdf
#
# Exits 0 without output when no .tex file in src/ has a meaningful change.
# The generated diff .tex is kept in build/diff/last-diff.tex for debugging.
#
# Examples:
#   scripts/diff.sh                      # my work so far vs master
#   scripts/diff.sh v1.0.0 HEAD          # everything since a release
#   scripts/diff.sh HEAD~1 HEAD          # just the last commit

set -euo pipefail

usage() {
    sed -n '3,21p' "$0" | sed 's/^# \{0,1\}//' >&2
    exit 1
}

[[ $# -le 3 && ${1:-} != -h && ${1:-} != --help ]] || usage

for tool in git latexdiff tectonic biber; do
    command -v "$tool" >/dev/null 2>&1 || {
        echo "ERROR: $tool not found on PATH; run ./setup.sh first" >&2
        exit 1
    }
done

root=$(git rev-parse --show-toplevel)
cd "$root"

base_arg=${1:-}
head_arg=${2:-}

if [[ -z $base_arg ]]; then
    for candidate in origin/master master; do
        if git rev-parse --verify --quiet "$candidate^{commit}" >/dev/null; then
            base_arg=$candidate
            break
        fi
    done
    [[ -n $base_arg ]] || {
        echo "ERROR: no origin/master or master found; pass BASE explicitly" >&2
        exit 1
    }
fi

head_commit=$(git rev-parse --verify "${head_arg:-HEAD}^{commit}")
base_sha=$(git merge-base "$base_arg" "$head_commit") || {
    echo "ERROR: no common ancestor between '$base_arg' and '${head_arg:-HEAD}'" >&2
    exit 1
}

if [[ -n $head_arg ]]; then
    head_label=${head_commit:0:7}
    head_name=$head_label
else
    head_label="working tree"
    head_name="worktree"
fi

out=${3:-build/diff/diff-${base_sha:0:7}-$head_name.pdf}
[[ $out = /* ]] || out=$root/$out

echo "==> Diffing ${base_sha:0:7}..$head_label"

# Only .tex matters: latexdiff cannot mark up .bib or other files. In a git
# pathspec `*` also matches `/`, so this covers nested subfiles too.
# For the working tree, `git diff <commit>` compares against the files on disk.
if git diff --quiet -w --ignore-blank-lines "$base_sha" ${head_arg:+"$head_commit"} -- 'src/*.tex'; then
    echo "==> No meaningful change in src/*.tex, skipping"
    exit 0
fi

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

mkdir "$work/old" "$work/new"
git archive "$base_sha" | tar -x -C "$work/old"

if [[ -n $head_arg ]]; then
    git archive "$head_commit" | tar -x -C "$work/new"
else
    # tracked + untracked-but-not-ignored files, skipping tracked files that
    # were deleted on disk
    while IFS= read -r -d '' f; do
        [[ -f $f ]] || continue
        mkdir -p "$work/new/$(dirname "$f")"
        cp "$f" "$work/new/$f"
    done < <(git ls-files -z --cached --others --exclude-standard)
fi

echo "==> Running latexdiff"
# --flatten inlines \input/\include on both sides, each resolved relative to
# its own file, so old and new subfiles are never mixed up.
latexdiff --flatten "$work/old/src/index.tex" "$work/new/src/index.tex" \
    >"$work/diff.tex"

mkdir -p "$(dirname "$out")" "$root/build/diff"
cp "$work/diff.tex" "$root/build/diff/last-diff.tex"

# Compile inside the new tree so figures, refs.bib and Tectonic.toml are found.
cp "$work/diff.tex" "$work/new/src/index.tex"

echo "==> Building diff PDF"
(cd "$work/new" && tectonic -X build)

cp "$work/new/build/default/default.pdf" "$out"

echo "==> Wrote ${out#"$root"/}"
