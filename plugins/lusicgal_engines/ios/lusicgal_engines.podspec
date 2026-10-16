Pod::Spec.new do |s|
  s.name             = 'lusicgal_engines'
  s.version          = '0.1.0'
  s.summary          = 'LusicGal engine host bridge.'
  s.description      = <<-DESC
  LusicGal 的平台桥插件：MethodChannel / EventChannel / PlatformView，
  以及引擎核心（静态符号）探测与派发。核心 .a 缺失不影响 App
  （native/stubs 弱符号兜底；接入见 docs/BUILD.md）。
  DESC
  s.homepage         = 'https://github.com/sunxibing114514/LusicGal'
  s.license          = { :type => 'GPL-3.0', :file => '../../LICENSE' }
  s.author           = { 'LusicGal' => 'dev@lusicgal.local' }
  s.source           = { :path => '.' }

  # Swift 桥 + iOS C 桥 + 统一 ABI 头 + 核心 stub（弱符号兜底）。
  # 核心 .a（liblusicgal_<id>.a）经构建脚本以 vendored 方式追加（v2）。
  s.source_files = 'Classes/**/*.{swift,h,m}',
                    '../../../native/bridge/ios/*.{h,c}',
                    '../../../native/bridge/ios/include/*.h',
                    '../../../native/include/lusicgal/*.h',
                    '../../../native/stubs/*.c'
  s.public_header_files = 'Classes/**/*.h',
                           '../../../native/bridge/ios/include/*.h',
                           '../../../native/include/lusicgal/*.h'

  s.dependency 'Flutter'
  s.platform         = :ios, '14.0'
  s.swift_version    = '5.0'
  # Web 引擎启动 hook（与 Android 共用同一资产；WKUserScript 注入用）。
  s.resource_bundles = { 'lusicgal_engines' => ['../android/src/main/assets/*.js'] }
  s.pod_target_xcconfig = {
    'DEFINES_MODULE' => 'YES',
    # 弱符号（核心 stub）依赖 GNU ld 行为；Swift 与 C 混编模块照常工作。
    'OTHER_LDFLAGS' => '$(inherited)',
  }
end
