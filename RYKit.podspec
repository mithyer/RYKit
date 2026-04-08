#
# Be sure to run `pod lib lint RYKit.podspec' to ensure this is a
# valid spec before submitting.
#
# Any lines starting with a # are optional, but their use is encouraged
# To learn more about a Podspec see https://guides.cocoapods.org/syntax/podspec.html
#

Pod::Spec.new do |s|
  s.name             = 'RYKit'
  s.version          = '2.1.1'
  s.summary          = 'RYKit...'
  s.description      = 'RYKit.....'
  s.homepage         = 'https://github.com/mithyer/RYKit'
  s.license          = { :type => 'MIT', :file => 'LICENSE' }
  s.author       = {'Ray' => 'http://github.com/mithyer'}
  s.source       = { :git => 'https://github.com/mithyer/RYKit.git', :tag => s.version.to_s}

  s.ios.deployment_target = '13.0'
  s.osx.deployment_target = "10.15"
  s.tvos.deployment_target  = "13.0"
  s.swift_version    = '5.0'
  s.source_files = 'Classes/RYKit.swift'

  s.subspec 'Core' do |core|
    core.source_files = 'Classes/Core/**/*'
  end

  s.subspec 'NetworkHttp' do |http|
    http.source_files = 'Classes/Http/**/*'
  end

  s.subspec 'NetworkStomp' do |stomp|
    stomp.source_files = 'Classes/Stomp/*', 'Classes/Stomp/SwiftStomp/**/*'
  end
end
