#
# Be sure to run `pod lib lint ADKit.podspec' to ensure this is a
# valid spec before submitting.
#
# Any lines starting with a # are optional, but their use is encouraged
# To learn more about a Podspec see https://guides.cocoapods.org/syntax/podspec.html
#

Pod::Spec.new do |s|
  s.name             = 'ADKit'
  s.version          = '1.1.0'
  s.summary          = 'Kit for Aden'
  s.description      =' Kit for Aden.'
  s.homepage         = 'http://10.23.9.221/rui.mao/adkit'
  s.license          = { :type => 'MIT', :file => 'LICENSE' }
  s.author       = {'Romixery' => 'http://attar.ai'}
  s.source       = { :git => 'http://10.23.9.221/rui.mao/adkit',  :branch => "master"}

  s.ios.deployment_target = '13.0'
  s.osx.deployment_target = "10.15"
  s.tvos.deployment_target  = "13.0"
  s.swift_version    = '5.0'
  s.source_files = 'Classes/ADKit.swift'

  s.subspec 'Capables' do |ss|
    ss.source_files = 'Classes/Capables/**/*'
  end

  s.subspec 'Extensions' do |ss|
    ss.source_files = 'Classes/Extensions/**/*'
  end

  s.subspec 'Stomp' do |ss|
    ss.source_files = 'Classes/Stomp/*'
    ss.subspec 'Vendor' do |vendor|
      vendor.source_files = 'Classes/Stomp/SwiftStomp/**/*'
    end
  end

  s.subspec 'ValueWrapper' do |ss|
    ss.source_files = 'Classes/ValueWrapper/*'
  end

  s.dependency 'ReachabilitySwift', '~> 5.2.4'
end
