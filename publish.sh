#!/bin/bash
set -e

# Configuration
BUILD_DIR="build"
GH_PAGES_BRANCH="gh-pages"
REMOTE="origin"

# 1. Ensure we are in the root of the repo
if [ ! -f "Makefile" ]; then
    echo "Error: Makefile not found."
    exit 1
fi

# 2. Build everything properly
echo "Building the entire PEP site..."
if [ ! -d ".venv" ]; then
    make venv
fi

# Clean previous builds
rm -rf "$BUILD_DIR"

# Get the GitHub repository name, owner and current branch
REPO_URL=$(git remote get-url "$REMOTE")
CURRENT_BRANCH=$(git branch --show-current)

# Extract owner/repo from git@github.com:owner/repo.git or https://github.com/owner/repo.git
if [[ "$REPO_URL" =~ github.com[:/]([^/]+)/([^/.]+)(\.git)?$ ]]; then
    OWNER="${BASH_REMATCH[1]}"
    REPO="${BASH_REMATCH[2]}"
    BASE_URL="https://$OWNER.github.io/$REPO/"
else
    echo "Error: Could not determine base URL from remote. Using default." >&2
    exit 1
fi

echo "Setting base URL to $BASE_URL"
echo "Targeting GitHub source link for $OWNER/$REPO on branch $CURRENT_BRANCH"

# Update PEP 0 and other generated files to include PEP 9999
echo "Regenerating PEP indices..."
.venv/bin/python3 -m release_management update-peps || echo "Warning: Could not update indices, continuing with build..."

# Build HTML and Search index
# We use GITHUB_PAGES=true and -D to override settings
PATH=".venv/bin:$PATH" GITHUB_PAGES=true sphinx-build \
    --builder dirhtml \
    --jobs auto \
    --fail-on-warning \
    --keep-going \
    -D "html_baseurl=$BASE_URL" \
    peps "$BUILD_DIR"

# Build search index
make search

# 3. Post-process HTML to fix GitHub source links
echo "Fixing GitHub source links in produced HTML files..."
find "$BUILD_DIR" -name "*.html" -type f -exec sed -i "s|https://github.com/python/peps/blob/main/peps/|https://github.com/$OWNER/$REPO/blob/$CURRENT_BRANCH/peps/|g" {} +

# 4. Fix for GitHub Pages
echo "Fixing build for GitHub Pages..."
rm -f "$BUILD_DIR/CNAME"
touch "$BUILD_DIR/.nojekyll"

# 5. Deploy everything
REMOTE_URL=$(git remote get-url "$REMOTE")
echo "Publishing full site to $GH_PAGES_BRANCH on $REMOTE..."

SOURCE_DIR="$BUILD_DIR"
TMP_DIR=$(mktemp -d)
echo "Preparing deployment in $TMP_DIR"
cp -a "$SOURCE_DIR"/. "$TMP_DIR/"

pushd "$TMP_DIR" > /dev/null
git init
git remote add origin "$REMOTE_URL"
git checkout -b "$GH_PAGES_BRANCH"

git add .
git commit -m "Full PEP site publish"
echo "Pushing to GitHub..."
git push -f origin "$GH_PAGES_BRANCH"

popd > /dev/null

rm -rf "$TMP_DIR"
echo "Success! Full PEP site published to GitHub Pages."
