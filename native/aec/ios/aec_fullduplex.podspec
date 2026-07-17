#
# Flutter FFI plugin podspec (iOS). Shares the C sources under ../src via the
# Classes/ forwarders. Apps embedding this must declare NSMicrophoneUsageDescription.
#
Pod::Spec.new do |s|
  s.name             = 'aec_fullduplex'
  s.version          = '0.1.0'
  s.summary          = 'Native full-duplex acoustic echo cancellation (AEC Tier 3b).'
  s.description      = <<-DESC
miniaudio (MIT-0) duplex host + a cleanroom MIT echo-canceller, exposed over FFI.
                       DESC
  s.homepage         = 'https://github.com/CrispStrobe/crisp_notation'
  s.license          = { :file => '../LICENSE' }
  s.author           = { 'CometBeat' => 'cze@mailbox.org' }

  s.source           = { :path => '.' }
  s.source_files     = 'Classes/**/*'
  s.dependency 'Flutter'
  s.platform = :ios, '13.0'

  # miniaudio's iOS backend (Core Audio / AVAudioSession).
  s.frameworks = 'CoreFoundation', 'CoreAudio', 'AudioToolbox', 'AVFoundation'
  s.pod_target_xcconfig = {
    'DEFINES_MODULE' => 'YES',
    'EXCLUDED_ARCHS[sdk=iphonesimulator*]' => 'i386'
  }
  s.swift_version = '5.0'
end
