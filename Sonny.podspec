Pod::Spec.new do |s|
  s.name = 'Sonny'
  s.version = '1.0.0'
  s.summary = 'Visitor support chat for iOS apps'
  s.homepage = 'https://github.com/usesonny/sonny-ios-sdk'
  s.license = { :type => 'MIT', :file => 'LICENSE' }
  s.author = { 'Sonny' => 'support@usesonny.com' }
  s.source = { :git => 'https://github.com/usesonny/sonny-ios-sdk.git', :tag => s.version.to_s }
  s.ios.deployment_target = '15.0'
  s.swift_version = '5.9'
  s.source_files = 'Sources/Sonny/**/*.swift'
  s.frameworks = 'UIKit', 'WebKit', 'Security', 'Combine'
  s.pod_target_xcconfig = { 'DEFINES_MODULE' => 'YES' }
end
