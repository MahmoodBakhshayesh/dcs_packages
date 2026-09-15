#
# To learn more about a Podspec see http://guides.cocoapods.org/syntax/podspec.html
#
Pod::Spec.new do |s|
  s.name             = 'dcs_zebra'
  s.version          = '0.1.0'
  s.summary          = 'Zebra Link-OS Flutter plugin for DCS (macOS TCP via Dart)'
  s.description      = 'macOS uses Dart TCP; native BT/USB are not available without a macOS Link-OS SDK.'
  s.homepage         = 'https://github.com/MahmoodBakhshayesh/dcs_packages'
  s.license          = { :type => 'MIT' }
  s.author           = { 'DCS' => 'dev@dcs.local' }
  s.source           = { :path => '.' }
  s.source_files     = 'Classes/**/*'
  s.dependency 'FlutterMacOS'
  s.platform = :osx, '10.14'
  s.pod_target_xcconfig = { 'DEFINES_MODULE' => 'YES' }
  s.swift_version = '5.0'
end
