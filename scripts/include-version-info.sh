# Use Xcode's copy of the Git binary
GIT=`xcrun -find git`

# Use the commit count as CFBundleVersion
GIT_COMMIT_COUNT=`${GIT} rev-list --count HEAD`
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion ${GIT_COMMIT_COUNT}" "${BUILT_PRODUCTS_DIR}/${INFOPLIST_PATH}"

## Use the last annotated tag as CFBundleShortVersionString
GIT_TAG=`${GIT} describe --tags --always --dirty`
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString ${GIT_TAG}" "${BUILT_PRODUCTS_DIR}/${INFOPLIST_PATH}"

echo "Added release ${GIT_TAG} version ${GIT_COMMIT_COUNT}"
