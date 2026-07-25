# Flutter FFI plugin podspec (macos). Classes/ forwarders relatively #include the
# vendored glint C++ sources under ../src, so every platform builds the
# same code. C++17 + libc++.
Pod::Spec.new do |s|
  s.name             = 'glint_vorbis'
  s.version          = '0.1.0'
  s.summary          = 'Native glint codecs (MIT): Vorbis/FLAC decode + MP3/AAC/Opus encode.'
  s.description      = 'The vendored glint decode (.sf3 Vorbis, SFZ FLAC) and encode (glint_encode_audio -> MP3 / AAC-LC / Ogg-Opus export) source sets over FFI.'
  s.homepage         = 'https://github.com/CrispStrobe/cometbeat'
  s.license          = { :file => '../LICENSE' }
  s.author           = { 'CometBeat' => 'cze@mailbox.org' }
  s.source           = { :path => '.' }
  s.source_files     = 'Classes/**/*'
  s.dependency 'FlutterMacOS'
  s.platform = :osx, '10.13'
  s.pod_target_xcconfig = {
    'DEFINES_MODULE' => 'YES',
    'CLANG_CXX_LANGUAGE_STANDARD' => 'c++17',
    'CLANG_CXX_LIBRARY' => 'libc++',
    'HEADER_SEARCH_PATHS' => '"${PODS_TARGET_SRCROOT}/../src"',
  }
end
