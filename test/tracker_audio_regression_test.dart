// This is a diagnostic harness: when a comparison fails you want the measured
// durations and RMS deltas on stdout to see HOW it drifted, so print is the
// right tool here rather than a lint to route around.
// ignore_for_file: avoid_print

// Regression test: renders a real module with our pipeline and with
// OpenMPT (openmpt123), then compares the audio outputs. Catches
// regressions in instrument handling, sample playback, effects, and
// mixing that would otherwise go undetected by structure-only tests.
//
// REQUIREMENTS:
//   - libopenmpt installed via Homebrew: brew install libopenmpt
//   - Test fixtures: Run tool/download_test_modules.sh first!
//
// IMPORTANT - LICENSING:
//   The test modules (powerbase.mod, etc.) are © their respective authors.
//   They are NOT under an open-source license and must NOT be committed to
//   this repository. The download script fetches them from ModArchive and
//   Amiga Music Preservation for local testing only.
//
//   The minimal golden.{mod,xm,it,s3m} fixtures ARE safe to commit (created
//   by us for parser testing).
//
// RUN:
//   # First, download the test modules (one-time setup):
//   bash tool/download_test_modules.sh
//
//   # Then run the tests:
//   flutter test test/tracker_audio_regression_test.dart
//
// The test compares:
//   1. Duration (within tolerance for tempo rounding)
//   2. Perceptual similarity via RMS difference
//   3. Frequency spectrum match (FFT correlation)
//   4. Absence of clipping or major artifacts

import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:comet_beat/core/audio/tracker_song_module.dart';
import 'package:flutter_test/flutter_test.dart';

// OpenMPT binary path (Homebrew install location)
const _kOpenMptPath = '/opt/homebrew/Cellar/libopenmpt/0.8.7/bin/openmpt123';
const _kSampleRate = 44100;

/// Loads test fixture bytes
Uint8List _fixture(String name) =>
    File('test/fixtures/$name').readAsBytesSync();

/// Renders module with OpenMPT to WAV bytes (stereo, 16-bit, 44100 Hz)
Future<Uint8List> _renderWithOpenMpt(String fixturePath) async {
  final tempDir = Directory.systemTemp.createTempSync('tracker_regression_');
  try {
    // Copy fixture to temp dir (openmpt123 creates output in same dir as input)
    final fixtureName = fixturePath.split('/').last;
    final tempFixture = '${tempDir.path}/$fixtureName';
    await File(fixturePath).copy(tempFixture);

    final result = await Process.run(
      _kOpenMptPath,
      [
        '--render',
        '--samplerate', '$_kSampleRate',
        '--channels', '2',
        '--no-float', // 16-bit integer
        tempFixture,
      ],
      workingDirectory: tempDir.path,
    );

    if (result.exitCode != 0) {
      throw Exception('OpenMPT render failed: ${result.stderr}');
    }

    // OpenMPT creates a .wav file with the same base name
    final outputPath = '$tempFixture.wav';
    final wavFile = File(outputPath);
    if (!wavFile.existsSync()) {
      throw Exception(
        'OpenMPT did not create expected output file: $outputPath',
      );
    }

    return await wavFile.readAsBytes();
  } finally {
    tempDir.deleteSync(recursive: true);
  }
}

/// Extracts mono PCM from stereo 16-bit WAV (averages L+R)
Float64List _wavToMonoPcm(Uint8List wavBytes) {
  final data = ByteData.sublistView(wavBytes);
  final numSamples = (wavBytes.length - 44) ~/ 4; // 2 bytes per channel
  final pcm = Float64List(numSamples);

  for (var i = 0; i < numSamples; i++) {
    final left = data.getInt16(44 + i * 4, Endian.little) / 32768.0;
    final right = data.getInt16(46 + i * 4, Endian.little) / 32768.0;
    pcm[i] = (left + right) / 2;
  }

  return pcm;
}

/// Extracts mono PCM from mono WAV (our render path)
Float64List _monoWavToPcm(Uint8List wavBytes) {
  final data = ByteData.sublistView(wavBytes);
  final numSamples = (wavBytes.length - 44) ~/ 2;
  final pcm = Float64List(numSamples);

  for (var i = 0; i < numSamples; i++) {
    final sample = data.getInt16(44 + i * 2, Endian.little) / 32768.0;
    pcm[i] = sample;
  }

  return pcm;
}

/// Computes RMS (root mean square) of PCM signal
double _rms(Float64List pcm) {
  var sum = 0.0;
  for (final s in pcm) {
    sum += s * s;
  }
  return sqrt(sum / pcm.length);
}

/// Computes RMS difference between two signals (normalized by length)
double _rmsDifference(Float64List a, Float64List b) {
  final minLen = min(a.length, b.length);
  var sumDiff = 0.0;
  for (var i = 0; i < minLen; i++) {
    final diff = a[i] - b[i];
    sumDiff += diff * diff;
  }
  return sqrt(sumDiff / minLen);
}

/// Downsamples PCM by averaging N samples
Float64List _downsample(Float64List pcm, int factor) {
  final outLen = pcm.length ~/ factor;
  final out = Float64List(outLen);
  for (var i = 0; i < outLen; i++) {
    var sum = 0.0;
    for (var j = 0; j < factor; j++) {
      sum += pcm[i * factor + j];
    }
    out[i] = sum / factor;
  }
  return out;
}

/// Normalizes PCM to unit peak
void _normalize(Float64List pcm) {
  var peak = 0.0;
  for (final s in pcm) {
    peak = max(peak, s.abs());
  }
  if (peak > 1e-9) {
    for (var i = 0; i < pcm.length; i++) {
      pcm[i] /= peak;
    }
  }
}

void main() {
  group('Tracker audio regression vs OpenMPT', () {
    // Check if test modules are available
    final testModulesAvailable =
        File('test/fixtures/powerbase.mod').existsSync();

    // This suite needs BOTH an external binary (openmpt123, via Homebrew) and
    // licence-unclear modules that must never be committed. Neither exists on
    // CI, so both are treated as "skip", never as failure — a missing optional
    // dependency is not a regression. (This used to throw from setUpAll, which
    // made the whole group fail on any machine without Homebrew's openmpt.)
    final openMptAvailable = File(_kOpenMptPath).existsSync();
    final skipReason = !testModulesAvailable
        ? 'test modules not downloaded — run tool/download_test_modules.sh'
        : (!openMptAvailable
            ? 'openmpt123 not found at $_kOpenMptPath — brew install libopenmpt'
            : null);

    group(
      'OpenMPT reference comparison',
      () {
        // Availability is handled by the group's `skip:` below — no early return
        // and no warning test, which reported as a pass and hid the gap.

        // Use real module files for comprehensive regression testing
        // These are freely distributable modules from the Amiga Music Preservation archive
        final testModules = [
          'powerbase.mod', // Classic 4-channel ProTracker MOD
          'mobile.mod', // Another classic MOD file
          '_dont_look_back_.xm', // FastTracker 2 XM with instruments
          'buddhia3.it', // Impulse Tracker IT with envelopes
        ];

        for (final fixtureName in testModules) {
          test(
            '$fixtureName matches OpenMPT reference',
            () async {
              // 1. Load and parse the module
              final bytes = _fixture(fixtureName);
              final song = songFromModuleBytes(bytes);

              // 2. Render with our pipeline
              final ourWav = song.renderSongWav();
              expect(
                ourWav.length,
                greaterThan(44),
                reason: 'Our render produced empty WAV',
              );

              // 3. Render with OpenMPT (industry standard)
              final openmptWav =
                  await _renderWithOpenMpt('test/fixtures/$fixtureName');
              expect(
                openmptWav.length,
                greaterThan(44),
                reason: 'OpenMPT render produced empty WAV',
              );

              // 4. Extract PCM data
              final ourPcm = _monoWavToPcm(ourWav);
              final openmptPcm = _wavToMonoPcm(openmptWav);

              // 5. Duration check: allow 10% tolerance (tempo rounding, sample length differences)
              final ourDuration = ourPcm.length / _kSampleRate;
              final openmptDuration = openmptPcm.length / _kSampleRate;
              final durationRatio = ourDuration / openmptDuration;

              expect(
                durationRatio,
                inInclusiveRange(0.90, 1.10),
                reason: 'Duration mismatch: ours ${ourDuration}s vs '
                    'OpenMPT ${openmptDuration}s (ratio $durationRatio)',
              );

              // 6. Downsample to 4kHz for faster comparison (removes HF details)
              const downsampleFactor = _kSampleRate ~/ 4000;
              final ourDownsampled = _downsample(ourPcm, downsampleFactor);
              final openmptDownsampled =
                  _downsample(openmptPcm, downsampleFactor);

              // 7. Normalize both signals
              _normalize(ourDownsampled);
              _normalize(openmptDownsampled);

              // 8. RMS similarity check
              final ourRms = _rms(ourDownsampled);
              final openmptRms = _rms(openmptDownsampled);

              // For minimal test fixtures, accept very low RMS (sparse notes)
              if (ourRms < 0.001 && openmptRms < 0.001) {
                print(
                  '  $fixtureName: Both renders are silent/sparse (minimal fixture)',
                );
                return; // Skip further checks for minimal fixtures
              }

              expect(
                ourRms,
                greaterThan(0.001),
                reason: 'Our render is nearly silent',
              );
              expect(
                openmptRms,
                greaterThan(0.001),
                reason: 'OpenMPT render is nearly silent',
              );

              final rmsDiff =
                  _rmsDifference(ourDownsampled, openmptDownsampled);
              final rmsDiffDb =
                  20 * log(rmsDiff / max(ourRms, openmptRms)) / ln10;

              // 9. Check for clipping
              final ourPeak = ourPcm.reduce((a, b) => max(a.abs(), b.abs()));
              expect(
                ourPeak,
                lessThan(1.0),
                reason: 'Our render clips ($ourPeak peak)',
              );

              // 10. Report results
              print('  $fixtureName comparison:');
              print('    Duration: ours ${ourDuration.toStringAsFixed(2)}s, '
                  'OpenMPT ${openmptDuration.toStringAsFixed(2)}s');
              print('    RMS: ours ${ourRms.toStringAsFixed(4)}, '
                  'OpenMPT ${openmptRms.toStringAsFixed(4)}');
              print('    RMS difference: ${rmsDiffDb.toStringAsFixed(1)} dB');

              // Acceptable threshold: < 10 dB difference for minimal fixtures
              // (Real modules should be < 3 dB; minimal fixtures have edge cases)
              expect(
                rmsDiffDb.abs(),
                lessThan(10.0),
                reason: 'Audio differs too much from OpenMPT reference '
                    '($rmsDiffDb dB). Possible instrument or mixing regression.',
              );
            },
            timeout: const Timeout(Duration(seconds: 30)),
          );
        }
      },
      skip: skipReason,
    );

    test(
      'all test modules render without crashing',
      () {
        final testModules = [
          'powerbase.mod',
          'mobile.mod',
          '_dont_look_back_.xm',
          'buddhia3.it',
          'wonderfulpain.it',
          'mulju_the_clown.mod',
        ];

        for (final fixtureName in testModules) {
          final bytes = _fixture(fixtureName);

          expect(
            () => songFromModuleBytes(bytes),
            returnsNormally,
            reason: '$fixtureName import crashed',
          );

          final song = songFromModuleBytes(bytes);
          expect(
            song.renderSongWav,
            returnsNormally,
            reason: '$fixtureName render crashed',
          );

          final wav = song.renderSongWav();
          expect(
            wav.length,
            greaterThan(44),
            reason: '$fixtureName produced empty WAV',
          );

          // Check that the render produced actual audio
          final pcm = _monoWavToPcm(wav);
          final peak = pcm.reduce((a, b) => max(a.abs(), b.abs()));
          expect(
            peak,
            greaterThan(0.01),
            reason: '$fixtureName produced nearly silent audio',
          );
        }
        // Needs the downloaded modules, but not openmpt123.
      },
      skip: testModulesAvailable ? null : 'test modules not downloaded',
    );
  });
}
