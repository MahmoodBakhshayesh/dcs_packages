#
# To learn more about a Podspec see http://guides.cocoapods.org/syntax/podspec.html
#
Pod::Spec.new do |s|
  s.name             = 'dcs_zebra'
  s.version          = '0.1.0'
  s.summary          = 'Zebra Link-OS Flutter plugin for DCS'
  s.description      = 'TCP and MFi Bluetooth printing via Zebra Link-OS iOS SDK.'
  s.homepage         = 'https://github.com/MahmoodBakhshayesh/dcs_packages'
  s.license          = { :type => 'MIT' }
  s.author           = { 'DCS' => 'dev@dcs.local' }
  s.source           = { :path => '.' }
  s.source_files     = 'Classes/**/*'
  s.dependency 'Flutter'
  s.platform = :ios, '13.0'
  s.vendored_frameworks = 'Frameworks/ZSDK_API.xcframework'
  s.pod_target_xcconfig = {
    'DEFINES_MODULE' => 'YES',
    'HEADER_SEARCH_PATHS' => '"${PODS_TARGET_SRCROOT}/Frameworks/ZSDK_API.xcframework/ios-arm64/Headers"'
  }
  s.frameworks = 'ExternalAccessory'
end
