#!/bin/bash

## PKG_POSTINSTALL_ACTION=logout bash package/build-package.bash

set -e

cd "$(dirname $0)"
PROJECT_ROOT=$(cd ..; pwd)

Version=`date "+%Y%m%d%H%M%S"`
GitHash=`git -C "${PROJECT_ROOT}" rev-parse --short HEAD`

pushd ${PROJECT_ROOT}
sh build.sh
popd

rm -f /tmp/YingHan-*.pkg
rm -rf /tmp/YingHan/build/release/root/
mkdir -p /tmp/YingHan/build/release/root
cp -R /tmp/YingHan/build/release/YingHan.app /tmp/YingHan/build/release/root/


# Allow overriding postinstall-action via env var (e.g. PKG_POSTINSTALL_ACTION=logout)
POSTINSTALL_ACTION="${PKG_POSTINSTALL_ACTION:-none}"
sed "s/__POSTINSTALL_ACTION__/${POSTINSTALL_ACTION}/" \
    "${PROJECT_ROOT}/package/PackageInfo" \
    > /tmp/YingHan/build/release/PackageInfo

pkgbuild \
    --info /tmp/YingHan/build/release/PackageInfo \
    --root "/tmp/YingHan/build/release/root" \
    --identifier "com.jinboli.inputmethod.yinghan" \
    --version ${Version} \
    --install-location "/Library/Input Methods" \
    --scripts "${PROJECT_ROOT}/package/scripts" \
    /tmp/YingHan-${Version}-${GitHash}.pkg
