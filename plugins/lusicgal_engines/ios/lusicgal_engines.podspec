Pod::Spec.new do |s|
  s.name             = 'lusicgal_engines'
  s.version          = '0.1.0'
  s.summary          = 'LusicGal engine host bridge.'
  s.description      = <<-DESC
  LusicGal 的平台桥插件：MethodChannel / EventChannel / PlatformView，
  以及引擎核心（静态符号）探测。核心以可选模块接入，缺失不影响 App。
  DESC
  s.homepage         = 'https://github.com/sunxibing114514/LusicGal'
  s.license          = { :type => 'GPL-3.0', :file => '../../LICENSE' }
  s.author           = { 'LusicGal' => 'dev@lusicgal.local' }
  s.source           = { :path => '.' }
  s.source_files     = 'Classes/**/*.{swift,h,m}'
  s.public_header_files = 'Classes/**/*.h'
  s.dependency 'Flutter'
  s.platform         = :ios, '14.0'
  s.swift_version    = '5.0'
  s.pod_target_xcconfig = { 'DEFINES_MODULE' => 'YES' }
end
