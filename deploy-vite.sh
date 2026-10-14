#!/bin/bash

# ==============================================================================
# UNIVERSAL VITE DEPLOY v3.1
# React + Vite + Git + GitHub + Tag + Release + GitHub Pages
# ==============================================================================

set -e

echo ""
echo "============================================================"
echo "        🚀 UNIVERSAL VITE DEPLOY v3.1"
echo "============================================================"
echo ""

# ------------------------------------------------------------
# 1. Kiểm tra công cụ
# ------------------------------------------------------------

for CMD in git gh npm; do
    if ! command -v "$CMD" >/dev/null 2>&1; then
        echo "❌ Không tìm thấy: $CMD"
        exit 1
    fi
done

# ------------------------------------------------------------
# 2. Kiểm tra GitHub CLI
# ------------------------------------------------------------

if ! gh auth status >/dev/null 2>&1; then
    echo "❌ GitHub CLI chưa đăng nhập."
    echo "Hãy chạy: gh auth login"
    exit 1
fi

# ------------------------------------------------------------
# 3. Kiểm tra package.json
# ------------------------------------------------------------

if [ ! -f "package.json" ]; then
    echo "❌ Không tìm thấy package.json."
    exit 1
fi

if ! grep -q '"vite"' package.json; then
    echo "❌ package.json không phát hiện Vite."
    exit 1
fi

# ------------------------------------------------------------
# 4. Lấy repository thật từ origin
# ------------------------------------------------------------

ORIGIN_URL="$(git remote get-url origin 2>/dev/null || true)"

if [ -z "$ORIGIN_URL" ]; then
    echo "❌ Repository chưa có remote origin."
    exit 1
fi

REPO_PATH="$(
    echo "$ORIGIN_URL" |
    sed -E 's#^https://github.com/##; s#^git@github.com:##; s#\.git$##'
)"

if [[ ! "$REPO_PATH" =~ ^[^/]+/[^/]+$ ]]; then
    echo "❌ Không thể xác định owner/repository từ origin:"
    echo "   $ORIGIN_URL"
    exit 1
fi

GITHUB_USER="${REPO_PATH%%/*}"
REPO_NAME="${REPO_PATH##*/}"

REPO_URL="https://github.com/${GITHUB_USER}/${REPO_NAME}"
APP_URL="https://${GITHUB_USER}.github.io/${REPO_NAME}/"
FORK_URL="${REPO_URL}/fork"
RELEASE_URL="${REPO_URL}/releases"

echo "👤 GitHub user : $GITHUB_USER"
echo "📦 Repository  : $REPO_NAME"
echo "🔗 Origin      : $ORIGIN_URL"
echo "🌐 App URL     : $APP_URL"
echo ""

# ------------------------------------------------------------
# 5. Kiểm tra repository
# ------------------------------------------------------------

if ! gh repo view "${GITHUB_USER}/${REPO_NAME}" >/dev/null 2>&1; then
    echo "❌ Repository không tồn tại hoặc không có quyền truy cập:"
    echo "   ${GITHUB_USER}/${REPO_NAME}"
    exit 1
fi

echo "✅ GitHub repository tồn tại."

# ------------------------------------------------------------
# 6. Đảm bảo branch main
# ------------------------------------------------------------

git branch -M main

# ------------------------------------------------------------
# 7. Kiểm tra Vite base
# ------------------------------------------------------------

echo ""
echo "🔍 Kiểm tra Vite base..."

if [ ! -f "vite.config.js" ] && \
   [ ! -f "vite.config.ts" ] && \
   [ ! -f "vite.config.mjs" ] && \
   [ ! -f "vite.config.cjs" ]; then

    echo "❌ Không tìm thấy vite.config."
    exit 1
fi

if ! grep -R -q "base: '/${REPO_NAME}/'" \
    vite.config.js \
    vite.config.ts \
    vite.config.mjs \
    vite.config.cjs 2>/dev/null; then

    echo ""
    echo "❌ Chưa tìm thấy cấu hình:"
    echo ""
    echo "    base: '/${REPO_NAME}/'"
    echo ""
    echo "GitHub Pages của repository này cần base path chính xác."
    exit 1
fi

echo "✅ Vite base path chính xác."

# ------------------------------------------------------------
# 8. Kiểm tra source thay đổi
# ------------------------------------------------------------

echo ""
echo "🔍 Git status:"
git status --short || true

# ------------------------------------------------------------
# 9. BUILD
# ------------------------------------------------------------

echo ""
echo "============================================================"
echo "🏗️  BUILD PROJECT"
echo "============================================================"
echo ""

npm run build

# ------------------------------------------------------------
# 10. Kiểm tra build
# ------------------------------------------------------------

if [ ! -f "dist/index.html" ]; then
    echo "❌ Build không tạo dist/index.html."
    exit 1
fi

echo ""
echo "✅ Build thành công."
echo "📁 dist/index.html tồn tại."

# ------------------------------------------------------------
# 11. React BrowserRouter → 404 fallback
# ------------------------------------------------------------

if grep -R -q "BrowserRouter" src 2>/dev/null; then

    echo ""
    echo "🔀 Phát hiện React BrowserRouter."

    cp dist/index.html dist/404.html

    echo "✅ Đã tạo dist/404.html."

else

    echo "ℹ️ Không phát hiện BrowserRouter."
fi

# ------------------------------------------------------------
# 12. Commit source
# ------------------------------------------------------------

echo ""
echo "============================================================"
echo "📦 COMMIT SOURCE"
echo "============================================================"
echo ""

git add .

# ------------------------------------------------------------
# 13. Version
# ------------------------------------------------------------

git fetch --tags origin >/dev/null 2>&1 || true

if [ -n "$1" ]; then

    VERSION="$1"

else

    LATEST_TAG="$(
        git tag --list 'v[0-9]*.[0-9]*.[0-9]*' |
        sed 's/^v//' |
        sort -t. -k1,1n -k2,2n -k3,3n |
        tail -n 1
    )"

    if [ -z "$LATEST_TAG" ]; then

        VERSION="v1.0.0"

    else

        IFS='.' read -r MAJOR MINOR PATCH <<< "$LATEST_TAG"
        PATCH=$((PATCH + 1))
        VERSION="v${MAJOR}.${MINOR}.${PATCH}"

    fi
fi

if [[ ! "$VERSION" =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    echo "❌ Version không hợp lệ: $VERSION"
    exit 1
fi

echo "🏷️ Version: $VERSION"

# ------------------------------------------------------------
# 14. Commit
# ------------------------------------------------------------

if ! git diff --cached --quiet; then

    git commit -m "Release ${REPO_NAME} ${VERSION}"

else

    echo "ℹ️ Không có source thay đổi mới."

fi

# ------------------------------------------------------------
# 15. Push main
# ------------------------------------------------------------

echo ""
echo "⬆️ Push main..."

git push -u origin main

# ------------------------------------------------------------
# 16. Tag
# ------------------------------------------------------------

if git rev-parse "$VERSION" >/dev/null 2>&1; then

    echo "ℹ️ Tag ${VERSION} đã tồn tại."

else

    git tag -a "$VERSION" -m "${REPO_NAME} ${VERSION}"

    echo "✅ Created tag ${VERSION}."

fi

git push origin "$VERSION"

# ------------------------------------------------------------
# 17. GitHub Release
# ------------------------------------------------------------

echo ""
echo "📦 GitHub Release..."

if gh release view "$VERSION" \
    --repo "${GITHUB_USER}/${REPO_NAME}" >/dev/null 2>&1; then

    echo "ℹ️ Release ${VERSION} đã tồn tại."

else

    gh release create "$VERSION" \
        --repo "${GITHUB_USER}/${REPO_NAME}" \
        --title "${REPO_NAME} ${VERSION}" \
        --generate-notes

    echo "✅ Release created."

fi

# ------------------------------------------------------------
# 18. Deploy dist → gh-pages
# ------------------------------------------------------------

echo ""
echo "============================================================"
echo "🌐 DEPLOY DIST → GH-PAGES"
echo "============================================================"
echo ""

SOURCE_DIR="$(pwd)"
DEPLOY_DIR="$(mktemp -d)"

cleanup() {
    cd "$SOURCE_DIR" 2>/dev/null || true
    rm -rf "$DEPLOY_DIR"
}

trap cleanup EXIT

echo "📁 Temporary deployment directory:"
echo "   $DEPLOY_DIR"

# Clone repository vào thư mục tạm độc lập
git clone --quiet "$ORIGIN_URL" "$DEPLOY_DIR"

cd "$DEPLOY_DIR"

# ------------------------------------------------------------
# 19. Checkout / tạo gh-pages
# ------------------------------------------------------------

if git ls-remote --exit-code --heads origin gh-pages \
    >/dev/null 2>&1; then

    echo "ℹ️ gh-pages đã tồn tại."

    git fetch origin gh-pages --quiet

    git checkout -B gh-pages origin/gh-pages

else

    echo "🆕 Tạo branch gh-pages."

    git checkout --orphan gh-pages

    git rm -rf . >/dev/null 2>&1 || true

fi

# ------------------------------------------------------------
# 20. Copy dist
# ------------------------------------------------------------

echo "📋 Copy dist → gh-pages..."

if command -v rsync >/dev/null 2>&1; then

    rsync -a --delete \
        --exclude='.git' \
        "${SOURCE_DIR}/dist/" \
        "${DEPLOY_DIR}/"

else

    find "$DEPLOY_DIR" -mindepth 1 \
        -maxdepth 1 \
        ! -name '.git' \
        -exec rm -rf {} +

    cp -R "${SOURCE_DIR}/dist/." "${DEPLOY_DIR}/"

fi

# GitHub Pages: không dùng Jekyll
touch .nojekyll

# ------------------------------------------------------------
# 21. Commit gh-pages
# ------------------------------------------------------------

git add -A

if git diff --cached --quiet; then

    echo "ℹ️ gh-pages không có thay đổi."

else

    git commit \
        -m "Deploy ${REPO_NAME} ${VERSION}" \
        >/dev/null

    echo "✅ gh-pages commit created."

fi

# ------------------------------------------------------------
# 22. Push gh-pages
# ------------------------------------------------------------

echo "⬆️ Push gh-pages..."

git push origin gh-pages --force

echo "✅ dist đã được deploy lên gh-pages."

# ------------------------------------------------------------
# 23. GitHub Pages
# ------------------------------------------------------------

cd "$SOURCE_DIR"

echo ""
echo "🌐 Kiểm tra GitHub Pages..."

if gh api \
    "repos/${GITHUB_USER}/${REPO_NAME}/pages" \
    >/dev/null 2>&1; then

    echo "✅ GitHub Pages đã tồn tại."

else

    echo "🚀 Bật GitHub Pages..."

    gh api \
        --method POST \
        "repos/${GITHUB_USER}/${REPO_NAME}/pages" \
        -f 'source[branch]=gh-pages' \
        -f 'source[path]=/' \
        -f 'build_type=legacy' \
        >/dev/null

    echo "✅ GitHub Pages đã bật."

fi

# ------------------------------------------------------------
# 24. Kiểm tra gh-pages thực sự tồn tại
# ------------------------------------------------------------

if ! git ls-remote --exit-code --heads origin gh-pages \
    >/dev/null 2>&1; then

    echo "❌ Không tìm thấy branch gh-pages sau deployment."
    exit 1
fi

# ------------------------------------------------------------
# 25. Kết quả
# ------------------------------------------------------------

echo ""
echo "============================================================"
echo "              🎉 DEPLOY THÀNH CÔNG"
echo "============================================================"
echo ""

echo "👤 OWNER:"
echo "$GITHUB_USER"
echo ""

echo "📦 REPOSITORY:"
echo "$REPO_URL"
echo ""

echo "🌐 LINK ỨNG DỤNG:"
echo "$APP_URL"
echo ""

echo "🔀 LINK FORK CHO SINH VIÊN:"
echo "$FORK_URL"
echo ""

echo "📦 LINK RELEASE:"
echo "$RELEASE_URL"
echo ""

echo "🏷️ VERSION:"
echo "$VERSION"
echo ""

echo "============================================================"
echo "        🚀 ${REPO_NAME} ${VERSION} READY"
echo "============================================================"
echo ""
