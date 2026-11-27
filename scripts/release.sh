#!/bin/bash
# Pith release: `make release VERSION=X.Y.Z` (DRY_RUN=1 builds and packs, then prints what would be published).
#   scripts/release.sh --check   build and check the bundle and the CHANGELOG only, no git preconditions, nothing published
# Environment: VERSION (X.Y.Z; with --check defaults to the one in project.yml), DRY_RUN.
set -euo pipefail

cd "$(dirname "$0")/.."
root="$PWD"

check_only=0
case "${1:-}" in
    "") ;;
    --check) check_only=1 ;;
    *) echo "usage: scripts/release.sh [--check]  (VERSION=X.Y.Z in the environment)" >&2; exit 2 ;;
esac

repo="itigancov/pith"
tap="itigancov/homebrew-tap"
bundle_id="io.github.itigancov.pith"
dry_run="${DRY_RUN:-}"
version="${VERSION:-}"
if [[ -z "$version" && $check_only -eq 1 ]]; then
    version="$(sed -nE 's/^ *MARKETING_VERSION: *"?([0-9.]+)"?.*/\1/p' project.yml | head -n1)"
fi

die() { echo "release: $*" >&2; exit 1; }
step() { echo "==> $*"; }

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

# --- 1. Preconditions ---------------------------------------------------------------------------------------------
[[ "$version" =~ ^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)$ ]] || die "VERSION must be X.Y.Z, got '${version}'"
tag="v$version"

grep -q "^## \[$version\]" CHANGELOG.md || die "CHANGELOG.md has no '## [$version]' section"
# The section up to the next `## [` or the link references at the bottom, without its heading and the blank lines around it.
notes="$work/notes.md"
awk -v h="## [$version]" 'index($0, h) == 1 { on = 1; next } /^## \[/ || /^\[[^]]+\]: / { on = 0 } on' CHANGELOG.md >"$work/section.md"
awk 'NF { for (i = 0; i < blank; i++) print ""; blank = 0; started = 1; print; next } started { blank++ }' "$work/section.md" >"$notes"
[[ -s "$notes" ]] || die "the '## [$version]' section of CHANGELOG.md is empty"

if [[ $check_only -eq 0 ]]; then
    step "Preconditions"
    [[ "$(git branch --show-current)" == main ]] || die "not on main"
    [[ -z "$(git status --porcelain)" ]] || die "working tree is not clean"
    git fetch --quiet origin main
    [[ "$(git rev-parse HEAD)" == "$(git rev-parse origin/main)" ]] || die "HEAD differs from origin/main"
    if git rev-parse --verify --quiet "refs/tags/$tag" >/dev/null; then die "tag $tag exists locally"; fi
    # `--exit-code`: 0 the tag exists, 2 it does not; anything else is a failure to ask.
    remote_tag=0
    git ls-remote --exit-code --tags origin "refs/tags/$tag" >/dev/null 2>&1 || remote_tag=$?
    [[ $remote_tag -ne 0 ]] || die "tag $tag exists in origin"
    [[ $remote_tag -eq 2 ]] || die "cannot ask origin about tag $tag (git ls-remote failed with $remote_tag)"
    gh auth status >/dev/null 2>&1 || die "gh is not logged in (gh auth login)"
fi

# --- 2. Build -----------------------------------------------------------------------------------------------------
build="$(git rev-list --count HEAD)"
derived=".build/release"
app="$derived/Build/Products/Release/Pith.app"

step "Building Pith $version ($build), universal Release"
xcodegen generate >/dev/null
xcodebuild -project Pith.xcodeproj -scheme Pith -configuration Release \
    -derivedDataPath "$derived" -destination 'generic/platform=macOS' \
    MARKETING_VERSION="$version" CURRENT_PROJECT_VERSION="$build" clean build >"$work/xcodebuild.log" 2>&1 \
    || { tail -n 40 "$work/xcodebuild.log" >&2; die "xcodebuild failed"; }

# --- 3. Bundle checks ---------------------------------------------------------------------------------------------
step "Checking the bundle"
plist="$app/Contents/Info.plist"
read_plist() { /usr/libexec/PlistBuddy -c "Print :$1" "$plist"; }

archs="$(lipo -archs "$app/Contents/MacOS/Pith")"
[[ " $archs " == *" x86_64 "* && " $archs " == *" arm64 "* ]] || die "the binary is not universal: $archs"
codesign --verify --deep --strict "$app" || die "the signature is not valid"
signature="$(codesign -dv "$app" 2>&1)"
[[ "$signature" == *$'\nSignature=adhoc'* ]] || die "the signature is not ad-hoc"
[[ "$(read_plist CFBundleShortVersionString)" == "$version" ]] || die "CFBundleShortVersionString is $(read_plist CFBundleShortVersionString), expected $version"
[[ "$(read_plist CFBundleVersion)" == "$build" ]] || die "CFBundleVersion is $(read_plist CFBundleVersion), expected $build"
[[ "$(read_plist CFBundleIdentifier)" == "$bundle_id" ]] || die "bundle ID is $(read_plist CFBundleIdentifier), expected $bundle_id"
echo "    $archs, $bundle_id, $version ($build), signature valid"

if [[ $check_only -eq 1 ]]; then
    step "Release notes of $version"
    cat "$notes"
    echo "release: --check passed"
    exit 0
fi

# --- 4. Archive ---------------------------------------------------------------------------------------------------
dist=".build/dist"
zip="$root/$dist/Pith-$version.zip"
mkdir -p "$dist"
rm -f "$zip"
step "Packing $zip"
# ditto keeps the signature and the extended attributes that zip(1) drops.
ditto -c -k --keepParent "$app" "$zip"
sha="$(shasum -a 256 "$zip" | cut -d' ' -f1)"
mkdir "$work/unpacked"
ditto -x -k "$zip" "$work/unpacked"
codesign --verify --deep --strict "$work/unpacked/Pith.app" || die "the signature is not valid after unzipping"

# --- The cask: the tap's own, or the template when the tap has none -----------------------------------------------
tapdir="$work/tap"
cask_path="Casks/pith.rb"
tap_cloned=1
if ! gh repo clone "$tap" "$tapdir" -- --quiet 2>/dev/null; then
    tap_cloned=0
    [[ -n "$dry_run" ]] || die "cannot clone $tap (create the tap first)"
    mkdir -p "$tapdir"
fi
if [[ -f "$tapdir/$cask_path" ]]; then
    cp "$tapdir/$cask_path" "$work/cask-old.rb"
else
    cp scripts/pith.rb.template "$work/cask-old.rb"
fi
sed -E -e "s/^( *version )\".*\"/\1\"$version\"/" -e "s/^( *sha256 )\".*\"/\1\"$sha\"/" "$work/cask-old.rb" >"$work/cask-new.rb"

# --- 5. Dry run: print what would be published and stop ----------------------------------------------------------
if [[ -n "$dry_run" ]]; then
    step "DRY_RUN: nothing is published"
    echo "zip:    $zip"
    echo "sha256: $sha"
    echo "tag:    $tag on $(git rev-parse --short HEAD)"
    echo "--- release notes ---"
    cat "$notes"
    if [[ $tap_cloned -eq 1 ]]; then echo "--- $cask_path of $tap ---"; else echo "--- $cask_path (the tap is not reachable, the template stands in) ---"; fi
    diff -u "$work/cask-old.rb" "$work/cask-new.rb" || true
    exit 0
fi

# --- 6-8. Publish: the tag, the GitHub Release, the tap -----------------------------------------------------------
step "Tagging $tag"
git tag -a "$tag" -m "Pith $version"
git push origin "$tag"

step "Creating the GitHub Release"
gh release create "$tag" "$zip" --repo "$repo" --title "Pith $version" --notes-file "$notes" --verify-tag \
    || die "the tag $tag is pushed, but the Release failed; create it by hand (gh release create $tag $zip) and update the cask (sha256 $sha)"

step "Updating the cask in $tap"
mkdir -p "$tapdir/Casks"
cp "$work/cask-new.rb" "$tapdir/$cask_path"
git -C "$tapdir" add "$cask_path"
git -C "$tapdir" commit --quiet -m "pith $version"
git -C "$tapdir" push --quiet origin HEAD:main \
    || die "the tag and the Release are published, but the tap push failed (sha256 $sha); update $cask_path by hand"

echo "release: Pith $version published: https://github.com/$repo/releases/tag/$tag"
