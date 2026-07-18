# Flutter FFI plugin podspec (ios). Classes/ forwarders relatively #include the
# vendored glint Vorbis C++ sources under ../src, so every platform builds the
# same code. C++17 + libc++.
Pod::Spec.new do |s|
  s.name             = 'glint_vorbis'
  s.version          = '0.1.0'
  s.summary          = 'Native Ogg-Vorbis decoder (glint, MIT) for CometBeat .sf3.'
  s.description      = 'The minimal glint Ogg-Vorbis decode source set over FFI.'
  s.homepage         = 'https://github.com/CrispStrobe/cometbeat'
  s.license          = { :file => '../LICENSE' }
  s.author           = { 'CometBeat' => 'cze@mailbox.org' }
  s.source           = { :path => '.' }
  s.source_files     = 'Classes/**/*'
  s.dependency 'Flutter'
  s.platform = :ios, '12.0'
  s.pod_target_xcconfig = {
    'DEFINES_MODULE' => 'YES',
    'CLANG_CXX_LANGUAGE_STANDARD' => 'c++17',
    'CLANG_CXX_LIBRARY' => 'libc++',
    'HEADER_SEARCH_PATHS' => '"${PODS_TARGET_SRCROOT}/../src"',
  }
end
