Pod::Spec.new do |s|
  s.name             = 'MyDataSyncthing'
  s.version          = '0.1.0'
  s.summary          = 'In-process Syncthing engine for MyData iOS (gomobile)'
  s.homepage         = 'https://gitee.com/yuncommunity/mydata'
  s.license          = { :type => 'MPL-2.0' }
  s.author           = { 'MyData' => 'dev@local' }
  s.source           = { :path => '.' }
  s.platform         = :ios, '13.0'
  s.vendored_frameworks = 'build/MyDataSyncthing.xcframework'
  s.libraries        = 'resolv'
  s.frameworks       = 'CoreFoundation', 'Security'
  s.pod_target_xcconfig = {
    'OTHER_LDFLAGS' => '-framework MyDataSyncthing'
  }
end
