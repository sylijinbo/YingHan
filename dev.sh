echo "Usage: sudo sh dev.sh"
echo "You may need to clean the dir: `rm -rf ~/.YingHan`"

mkdir -p ${HOME}/.YingHan/debug
xcodebuild -workspace YingHan.xcworkspace/ -scheme YingHan -configuration Release CONFIGURATION_BUILD_DIR=${HOME}/.YingHan/debug PRODUCT_NAME=YingHan PRODUCT_BUNDLE_IDENTIFIER=com.jinboli.inputmethod.yinghan
pkill -9 YingHan
sudo rm -rf  /Library/Input\ Methods/YingHan.app/
sudo cp -R ${HOME}/.YingHan/debug/YingHan.app /Library/Input\ Methods/YingHan.app
sudo /Library/Input\ Methods/YingHan.app/Contents/MacOS/YingHan --install
echo "YingHan IME is installed and activated. Wait a moment to use it..."
