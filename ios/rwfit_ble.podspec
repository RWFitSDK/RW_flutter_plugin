#
# RWFIT 智能戒指 BLE Flutter 插件（iOS）。
# Run `pod lib lint rwfit_ble.podspec` to validate before publishing.
#
Pod::Spec.new do |s|
  s.name             = 'rwfit_ble'
  s.version          = '0.0.1'
  s.summary          = 'RWFIT 智能戒指 BLE Flutter 插件'
  s.description      = '桥接 RW 原生 DHBleSDK，提供扫描/连接/健康监测/设备控制/数据同步/OTA 能力。'
  s.homepage         = 'https://github.com/RWFitSDK/RW_flutter_plugin'
  s.license          = { :type => 'MIT', :file => '../LICENSE' }
  s.author           = { 'RWFitSDK' => 'developer@dhouse88.com' }
  s.source           = { :path => '.' }

  s.source_files     = 'rwfit_ble/Sources/rwfit_ble/**/*'
  s.public_header_files = 'rwfit_ble/Sources/rwfit_ble/include/**/*.h'
  s.vendored_frameworks = 'Frameworks/DHBleSDK.framework'
  s.frameworks       = 'CoreBluetooth'

  s.dependency 'Flutter'
  s.platform = :ios, '12.0'

  s.pod_target_xcconfig = {
    'DEFINES_MODULE' => 'YES',
    'EXCLUDED_ARCHS[sdk=iphonesimulator*]' => 'i386 arm64',
    'HEADER_SEARCH_PATHS' => '"${PODS_TARGET_SRCROOT}/rwfit_ble/Sources/rwfit_ble/include/rwfit_ble"'
  }
end
