#!/usr/bin/env bash
set -euo pipefail

# Openflow Release Creator
# Creates a git tag and pushes to trigger GitHub Actions release workflow
# Usage: ./scripts/create-release.sh [version]
#   Example: ./scripts/create-release.sh 0.2.0

VERSION="${1:-}"

if [ -z "$VERSION" ]; then
    echo "Usage: $0 <version>"
    echo ""
    echo "Examples:"
    echo "  $0 0.2.0        # Create v0.2.0 release"
    echo "  $0 1.0.0-beta.1 # Create v1.0.0-beta.1 pre-release"
    echo ""
    exit 1
fi

# Add v prefix if not present
if [[ ! "$VERSION" =~ ^v ]]; then
    VERSION="v$VERSION"
fi

# Validate version format (basic check)
if [[ ! "$VERSION" =~ ^v[0-9]+\.[0-9]+\.[0-9]+(-[a-zA-Z0-9.]+)?$ ]]; then
    echo "Error: Invalid version format: $VERSION"
    echo "Expected format: v<major>.<minor>.<patch> or v<major>.<minor>.<patch>-<prerelease>"
    echo "Examples: v0.2.0, v1.0.0, v1.0.0-beta.1"
    exit 1
fi

# Check if tag already exists
if git rev-parse "$VERSION" >/dev/null 2>&1; then
    echo "Error: Tag $VERSION already exists"
    echo "Use 'git tag -d $VERSION' to delete it locally first"
    exit 1
fi

# Check if working directory is clean
if ! git diff-index --quiet HEAD --; then
    echo "Error: Working directory has uncommitted changes"
    echo "Commit or stash your changes before creating a release"
    git status --short
    exit 1
fi

# Get current branch
CURRENT_BRANCH=$(git rev-parse --abbrev-ref HEAD)

echo "========================================="
echo "Creating Openflow Release"
echo "========================================="
echo ""
echo "Version:       $VERSION"
echo "Branch:        $CURRENT_BRANCH"
echo "Commit:        $(git rev-parse --short HEAD)"
echo ""

# Confirm
read -p "Create and push this release tag? (y/N): " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "Release creation cancelled"
    exit 0
fi

echo ""
echo "Creating tag $VERSION..."
git tag -a "$VERSION" -m "Release $VERSION"

echo "Pushing tag to origin..."
git push origin "$VERSION"

echo ""
echo "========================================="
echo "✓ Release tag created and pushed!"
echo "========================================="
echo ""
echo "GitHub Actions will now:"
echo "  1. Build release .app bundle"
echo "  2. Create DMG with bundled backend"
echo "  3. Generate checksums"
echo "  4. Create GitHub release with DMG"
echo ""
echo "Monitor progress at:"
echo "  https://github.com/$(git remote get-url origin | sed 's/.*github.com[:/]\(.*\)\.git/\1/')/actions"
echo ""
echo "Release will be available at:"
echo "  https://github.com/$(git remote get-url origin | sed 's/.*github.com[:/]\(.*\)\.git/\1/')/releases/tag/$VERSION"
echo ""
