Pod::Spec.new do |s|
  s.name             = 'DataKeepSyncthing'
  s.version          = '0.1.0'
  s.summary          = 'In-process Syncthing engine for DataKeep (gomobile, shared with Android)'
  s.homepage         = 'https://github.com/oldfeel/datakeep'
  s.license          = { :type => 'MPL-2.0' }
  s.author           = { 'DataKeep' => 'dev@local' }
  s.source           = { :path => '.' }
  s.platform         = :ios, '13.0'
  s.vendored_frameworks = 'build/DataKeepSyncthing.xcframework'
  s.libraries        = 'resolv'
  s.frameworks       = 'CoreFoundation', 'Security'
  s.pod_target_xcconfig = {
    'OTHER_LDFLAGS' => '-framework DataKeepSyncthing'
  }
end
