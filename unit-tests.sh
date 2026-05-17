xcodebuild clean -workspace YingHan.xcworkspace/ -scheme Tests

xcodebuild test CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO -workspace YingHan.xcworkspace/ -scheme Tests
