#!/bin/bash

xcodebuild -version
clang -v
rm -rf /tmp/YingHan

xcodebuild clean -workspace YingHan.xcworkspace/ -scheme YingHan

xcodebuild -workspace YingHan.xcworkspace/ -scheme YingHan -destination "generic/platform=macOS,name=Any Mac" -configuration "Release" CONFIGURATION_BUILD_DIR=/tmp/YingHan/build/release BUILD_LIBRARY_FOR_DISTRIBUTION=YES PRODUCT_NAME=YingHan PRODUCT_BUNDLE_IDENTIFIER=com.jinboli.inputmethod.yinghan


