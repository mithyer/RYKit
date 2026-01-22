#
# Be sure to run `pod lib lint RYKit.podspec' to ensure this is a
# valid spec before submitting.
#
# Any lines starting with a # are optional, but their use is encouraged
# To learn more about a Podspec see https://guides.cocoapods.org/syntax/podspec.html
#

Pod::Spec.new do |s|
  s.name             = 'RYKit'
  s.version          = '2.0.7'
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

  s.subspec 'Network' do |s1|
    s1.subspec 'Http' do |ss|
      ss.source_files = 'Classes/Http/**/*'
    end
    s1.subspec 'Stomp' do |ss|
      ss.source_files = 'Classes/Stomp/*'
      ss.subspec 'Vendor' do |vendor|
        vendor.source_files = 'Classes/Stomp/SwiftStomp/**/*'
      end
    end
  end

  s.subspec 'Base' do |s1|
    s1.subspec 'Log' do |ss|
      ss.source_files = 'Classes/Log/**/*'
    end
    s1.subspec 'Capables' do |ss|
      ss.source_files = 'Classes/Capables/**/*'
    end
    s1.subspec 'Extensions' do |ss|
      ss.source_files = 'Classes/Extensions/**/*'
    end
    s1.subspec 'Lock' do |ss|
      ss.source_files = 'Classes/Lock/**/*'
    end
    s1.subspec 'ValueWrapper' do |ss|
      ss.source_files = 'Classes/ValueWrapper/*'
    end
    s1.subspec 'Collections' do |ss|
      ss.source_files = 'Classes/Collections/*'
    end
    s1.subspec 'TimeoutTask' do |ss|
      ss.source_files = 'Classes/TimeoutTask/*'
    end
  end
end
