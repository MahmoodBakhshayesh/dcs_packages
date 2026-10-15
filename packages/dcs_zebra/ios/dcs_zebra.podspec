#
# To learn more about a Podspec see http://guides.cocoapods.org/syntax/podspec.html
#
Pod::Spec.new do |s|
  s.name             = 'dcs_zebra'
  s.version          = '0.2.1'
  s.summary          = 'Zebra Link-OS Flutter plugin for DCS'
  s.description      = 'TCP and MFi Bluetooth printing via Zebra Link-OS iOS SDK.'
  s.homepage         = 'https://github.com/MahmoodBakhshayesh/dcs_packages'
  s.license          = { :type => 'MIT' }
  s.author           = { 'DCS' => 'dev@dcs.local' }
  s.source           = { :path => '.' }
  s.source_files     = 'Classes/**/*'
  s.dependency 'Flutter'
  s.platform = :ios, '15.5'
  s.vendored_frameworks = 'Frameworks/ZSDK_API.xcframework'
  s.pod_target_xcconfig = {
    'DEFINES_MODULE' => 'YES',
    'HEADER_SEARCH_PATHS' => '"${PODS_TARGET_SRCROOT}/Frameworks/ZSDK_API.xcframework/ios-arm64/Headers"',
  }
  # Flutter's link step sometimes resolves -lZSDK_API before XCFrameworkIntermediates
  # is populated — also search the plugin symlink paths directly.
  s.user_target_xcconfig = {
    'LIBRARY_SEARCH_PATHS' => '$(inherited) "${PODS_XCFRAMEWORKS_BUILD_DIR}/dcs_zebra" "${PODS_ROOT}/../.symlinks/plugins/dcs_zebra/ios/Frameworks/ZSDK_API.xcframework/ios-arm64" "${PODS_ROOT}/../.symlinks/plugins/dcs_zebra/ios/Frameworks/ZSDK_API.xcframework/ios-arm64_x86_64-simulator"',
  }
  s.frameworks = 'ExternalAccessory'
end
