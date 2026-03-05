#!/usr/bin/env bash
set -euo pipefail

# ── Vibma Release Script ─────────────────────────────────────────────
# Usage: ./scripts/release.sh <version>
# Example: ./scripts/release.sh 0.4.0        # stable release
#          ./scripts/release.sh 0.4.0-rc.1   # release candidate (npm: next tag, GH: prerelease)
#
# Bumps version everywhere, commits, tags, and pushes.
# CI handles the rest (build, npm publish, GH release, docs).
# ─────────────────────────────────────────────────────────────────────

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

VERSION="${1:-}"
if [[ -z "$VERSION" ]]; then
  echo "Usage: ./scripts/release.sh <version>"
  echo "Current version: $(node -p "require('./packages/core/package.json').version")"
  exit 1
fi

# Strip leading v if provided
VERSION="${VERSION#v}"
TAG="v${VERSION}"
CURRENT="$(node -p "require('./packages/core/package.json').version")"

if [[ "$VERSION" == "$CURRENT" ]]; then
  echo "Error: version $VERSION is already the current version."
  exit 1
fi

IS_PRERELEASE=false
if [[ "$VERSION" =~ -[a-zA-Z] ]]; then
  IS_PRERELEASE=true
fi

echo "Releasing $CURRENT -> $VERSION"
if [[ "$IS_PRERELEASE" == true ]]; then
  echo "  (pre-release — npm dist-tag: next, GH: prerelease)"
fi
echo ""

# ── Preflight ────────────────────────────────────────────────────────

if [[ -n "$(git diff --name-only HEAD)" ]]; then
  echo "Error: working tree has uncommitted changes. Commit or stash first."
  exit 1
fi

# ── Bump versions ────────────────────────────────────────────────────

echo "Bumping versions..."

for pkg in packages/core/package.json packages/adapter-figma/package.json packages/tunnel/package.json; do
  node -e "
    const fs = require('fs');
    const p = JSON.parse(fs.readFileSync('$pkg', 'utf8'));
    p.version = '$VERSION';
    fs.writeFileSync('$pkg', JSON.stringify(p, null, 2) + '\n');
  "
  echo "  $pkg -> $VERSION"
done

sed -i '' "s/const VIBMA_VERSION = \"[^\"]*\"/const VIBMA_VERSION = \"$VERSION\"/" \
  packages/adapter-figma/src/plugin/ui.html
echo "  packages/adapter-figma/src/plugin/ui.html -> $VERSION"
echo ""

# ── Commit, tag, push ────────────────────────────────────────────────

echo "Committing and tagging..."
git add packages/core/package.json packages/adapter-figma/package.json packages/tunnel/package.json packages/adapter-figma/src/plugin/ui.html
git commit -m "release: $TAG"
git tag "$TAG"

echo ""
echo "Ready to push. This will trigger CI to:"
echo "  - Build all packages"
echo "  - Publish @ufira/vibma + @ufira/vibma-tunnel to npm"
echo "  - Create GH release with zip assets"
echo "  - Deploy docs"
echo ""
read -rp "Push $TAG to origin? [y/N] " confirm
if [[ "$confirm" != [yY] ]]; then
  echo "Aborted. Tag and commit are local — undo with:"
  echo "  git tag -d $TAG && git reset HEAD~1"
  exit 1
fi

git push origin main "$TAG"

echo ""
echo "Pushed $TAG — CI is running."
echo "  Watch: gh run watch"
