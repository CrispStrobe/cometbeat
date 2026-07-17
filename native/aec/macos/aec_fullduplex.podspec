#
# Flutter FFI plugin podspec (macOS). The Classes/ forwarders relatively include
# the shared C sources under ../src so all platforms build the same code.
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
  s.dependency 'FlutterMacOS'

  s.platform = :osx, '10.13'
  s.pod_target_xcconfig = { 'DEFINES_MODULE' => 'YES' }
  # miniaudio's CoreAudio backend needs these system frameworks.
  s.frameworks = 'CoreFoundation', 'CoreAudio', 'AudioToolbox', 'AudioUnit'
  s.swift_version = '5.0'
end
