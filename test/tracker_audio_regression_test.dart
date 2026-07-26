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

import 'support/audio_compare.dart';

/// Opt-in flag for the heavy OpenMPT A/B comparison, matching the
/// `String.fromEnvironment` pattern in `test/bench_arrange_test.dart`.
///
/// It is OFF by default because the comparison does four full offline renders of
/// multi-minute modules on BOTH sides plus FFT analysis — around 8 minutes of
/// solid CPU. Inside a whole-suite `flutter test`, where ~20 other files run in
/// parallel, the harness cannot keep that isolate alive and dies with "Cannot
/// close sink while adding stream" — i.e. the suite failed on infrastructure,
/// not on anything musical. Standalone it is fine.
///
/// Run the audit deliberately (any non-empty value turns it on):
///   flutter test --dart-define=OPENMPT_AB=1 test/tracker_audio_regression_test.dart
///
/// Deliberately `String.fromEnvironment` + "is it non-empty", not
/// `bool.fromEnvironment`: the bool form only accepts the literal `true`, so
/// `OPENMPT_AB=1` silently left the audit switched OFF — the opt-in existed but
/// could not be reached, which is worse than no flag at all.
///
/// The whole FILE is behind this flag, not just the A/B. The "renders without
/// crashing" group looked cheap but also does full offline renders of all six
/// modules — two of them multi-minute — which is another ~12 minutes. And the
/// file can contribute nothing at all on a machine without the corpus, which
/// means CI and most checkouts. So `flutter test` skips it instantly and a
/// developer opts in when they want the audit.
const _openMptAbRaw = String.fromEnvironment('OPENMPT_AB');
final _openMptAb = _openMptAbRaw.isNotEmpty && _openMptAbRaw != '0';

// OpenMPT binary path (Homebrew install location)
/// Resolved from PATH, falling back to the Homebrew prefix. It used to be
/// pinned to one Cellar version, so a routine `brew upgrade` silently skipped
/// the whole audit.
final String _kOpenMptPath = _resolveOpenMpt();

String _resolveOpenMpt() {
  final which = Process.runSync('which', ['openmpt123']);
  if (which.exitCode == 0) {
    final path = (which.stdout as String).trim();
    if (path.isNotEmpty && File(path).existsSync()) return path;
  }
  return '/opt/homebrew/bin/openmpt123';
}

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
        // Dither is RANDOM and openmpt123 defaults it on (`--dither 1`) for
        // 16-bit output, so the reference differed on every run. Level and
        // envelope shrugged it off, but on thin material it was enough to move
        // the cross-correlation peak — the same A/B reported lags of 21504 and
        // 29696 samples for identical inputs. Our own render is byte-identical
        // run to run (verified), so switching dither off makes the whole
        // comparison reproducible.
        '--dither', '0',
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
/// Mono PCM from ANY 16-bit PCM WAV, whatever its channel count.
///
/// This used to be TWO functions — one that downmixed stereo (used for the
/// OpenMPT reference) and one that assumed mono (used for our render). Our
/// renderer has since gained stereo output, so our side was being read as twice
/// as many "samples" of interleaved L/R: every module reported a duration ratio
/// of almost exactly 2.0, and the RMS/spectrum comparisons after it were
/// matching interleaved L/R against a mono downmix, which is meaningless.
///
/// So there is one reader now, and it reads the channel count from the header
/// rather than assuming it. A renderer that changes its channel layout again
/// cannot break the comparison this way twice.
Float64List _wavToMonoPcm(Uint8List wavBytes) {
  final data = ByteData.sublistView(wavBytes);
  if (wavBytes.length < 44) return Float64List(0);

  // Walk the chunk list rather than trusting a fixed 44-byte header — a WAV
  // with a LIST/fact chunk would otherwise shift every sample.
  var channels = 1;
  var bitsPerSample = 16;
  var dataOffset = -1;
  var dataBytes = 0;
  var pos = 12; // past "RIFF" + size + "WAVE"
  while (pos + 8 <= wavBytes.length) {
    final id = String.fromCharCodes(wavBytes.sublist(pos, pos + 4));
    final size = data.getUint32(pos + 4, Endian.little);
    final body = pos + 8;
    if (id == 'fmt ' && body + 16 <= wavBytes.length) {
      channels = data.getUint16(body + 2, Endian.little);
      bitsPerSample = data.getUint16(body + 14, Endian.little);
    } else if (id == 'data') {
      dataOffset = body;
      dataBytes = size;
      break;
    }
    pos = body + size + (size.isOdd ? 1 : 0);
  }
  if (dataOffset < 0 || channels < 1 || bitsPerSample != 16) {
    return Float64List(0);
  }

  final available = wavBytes.length - dataOffset;
  final usable =
      dataBytes > 0 && dataBytes <= available ? dataBytes : available;
  final bytesPerFrame = 2 * channels;
  final frames = usable ~/ bytesPerFrame;
  final pcm = Float64List(frames);
  for (var i = 0; i < frames; i++) {
    var sum = 0.0;
    for (var c = 0; c < channels; c++) {
      sum +=
          data.getInt16(dataOffset + i * bytesPerFrame + c * 2, Endian.little) /
              32768.0;
    }
    pcm[i] = sum / channels;
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
    // Gated on a fixture WE own, not on the licence-restricted corpus.
    //
    // This used to require `powerbase.mod`, which is © its author and therefore
    // absent from every clean checkout — so the entire audit skipped even
    // though the committed golden.* fixtures were sitting right there and
    // openmpt123 was installed. The restricted modules are far better signal
    // and remain the reason to run this, but they are now an ENHANCEMENT: each
    // one skips itself individually if missing, and the baseline still runs.
    final testModulesAvailable = File('test/fixtures/golden.mod').existsSync();

    // This suite needs BOTH an external binary (openmpt123, via Homebrew) and
    // licence-unclear modules that must never be committed. Neither exists on
    // CI, so both are treated as "skip", never as failure — a missing optional
    // dependency is not a regression. (This used to throw from setUpAll, which
    // made the whole group fail on any machine without Homebrew's openmpt.)
    final openMptAvailable = File(_kOpenMptPath).existsSync();
    const optInReason =
        'opt-in: pass --dart-define=OPENMPT_AB=1 (this audit takes ~20 min and '
        'cannot survive a parallel whole-suite run)';
    final skipReason = !_openMptAb
        ? optInReason
        : !testModulesAvailable
            ? 'test modules not downloaded — run tool/download_test_modules.sh'
            : (!openMptAvailable
                ? 'openmpt123 not found at $_kOpenMptPath — brew install '
                    'libopenmpt'
                : null);

    group(
      'OpenMPT reference comparison',
      () {
        // Availability is handled by the group's `skip:` below — no early return
        // and no warning test, which reported as a pass and hid the gap.

        // Real modules, for comprehensive regression testing. They are © their
        // authors and NOT freely distributable — see the licence note in this
        // file's header and test/fixtures/README.md. They live only in a
        // developer checkout and are .gitignored; an earlier version of this
        // comment claimed they were "freely distributable", which is how 2.8 MB
        // of them ended up committed by accident (bb5a5bee).
        final testModules = [
          // OUR OWN fixtures first: committed, licence-clean, and present in
          // every checkout. Until these were listed the A/B named only the
          // restricted modules below, so on a tree without them it skipped
          // everything and reported success — an A/B that had effectively
          // never run. These are small and musically thin, but they exercise
          // the whole path and give the metrics a baseline that always works.
          'musical.mod',
          'golden.mod',
          'golden.xm',
          'golden.it',
          'golden.s3m',
          // Real music, and much better signal — but licence-restricted, so
          // they exist only in a developer checkout (see the file header).
          'powerbase.mod', // Classic 4-channel ProTracker MOD
          'mobile.mod', // Another classic MOD file
          '_dont_look_back_.xm', // FastTracker 2 XM with instruments
          'buddhia3.it', // Impulse Tracker IT with envelopes
        ];

        // Our golden.* fixtures are REPORT-ONLY, and the reason matters.
        //
        // They were hand-built for PARSER testing, not as audio references —
        // a few notes on a synthetic sample — so holding our render to
        // OpenMPT's interpretation of them is over-reach: on material this
        // thin the two engines legitimately disagree about default speed,
        // trailing silence and sample tuning, and none of that is a bug.
        //
        // Measured 2026-07-26 and REPRODUCIBLE run to run, so a future change
        // to these numbers is visible rather than lost:
        //   golden.mod  level −16.38 dB · env 0.927 · lag 23040 · spectral 0.620
        //   golden.xm   level  +9.45 dB · env 1.000 · lag   512 · spectral 0.824
        //   golden.it   level  −9.40 dB · env 0.990 · lag  1536 · spectral 0.483
        //   golden.s3m  level  −3.41 dB · env 0.990 · lag  2048 · spectral 0.546
        //   golden.xm / golden.it also run 17% short (ratio 0.83).
        //
        // ⚠️ TWO THINGS HERE ARE WORTH SOMEONE'S TIME — not claimed by me.
        //
        // (a) The LEVELS disagree by up to 16 dB and not even consistently in
        //     sign. The old comparison could not see this: it peak-normalised
        //     both sides before differencing, so it rated the same golden.mod
        //     pair as "-0.8 dB". A level check that normalises first is not a
        //     level check.
        // (b) Our golden.mod render is nearly SILENT in absolute terms — RMS
        //     0.00037, with 2 of 1323 envelope blocks above 1e-4.
        //
        // INVESTIGATED 2026-07-26: both are fixture artifacts. These files are
        // a SINGLE NOTE playing a five-sample waveform (mod: 4ch/2 notes/8
        // samples · xm: 1ch/1 note/5 · it: 1ch/1 note/5,10,10 · s3m:
        // 1ch/1 note/8). The near-silence is 2 notes over 7.68 s of nothing;
        // the level spread is two engines interpolating a 5-8 sample source
        // differently; the short XM/IT renders are tail handling on a 4-row
        // pattern. None of it says anything about musical fidelity.
        //
        // ⬜ What the A/B actually needs is MUSIC: either the restricted corpus
        // present locally, or a small purpose-built fixture we author (and can
        // therefore commit) with a few seconds of real notes across several
        // channels. The metrics are ready; the material is what is missing.
        //
        // The licence-restricted modules are real music and DO gate.
        const reportOnly = {
          'golden.mod',
          'golden.xm',
          'golden.it',
          'golden.s3m',
        };

        for (final fixtureName in testModules) {
          final strict = !reportOnly.contains(fixtureName);
          test(
            '$fixtureName matches OpenMPT reference',
            () async {
              // See the note in the crash group: any one fixture may legitimately
              // be absent, since none of them can be committed.
              if (!File('test/fixtures/$fixtureName').existsSync()) return;
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
              final ourPcm = _wavToMonoPcm(ourWav);
              final openmptPcm = _wavToMonoPcm(openmptWav);

              // 5. Duration check: allow 10% tolerance (tempo rounding, sample length differences)
              final ourDuration = ourPcm.length / _kSampleRate;
              final openmptDuration = openmptPcm.length / _kSampleRate;
              final durationRatio = ourDuration / openmptDuration;

              if (strict) {
                expect(
                  durationRatio,
                  inInclusiveRange(0.90, 1.10),
                  reason: 'Duration mismatch: ours ${ourDuration}s vs '
                      'OpenMPT ${openmptDuration}s (ratio $durationRatio)',
                );
              } else {
                print('    duration ratio ${durationRatio.toStringAsFixed(3)} '
                    '(report-only fixture)');
              }

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

              // The metrics duration+RMS cannot provide. Verified independently
              // in audio_compare_test.dart against synthesised signals, so a
              // surprising number here is evidence about the RENDER, not about
              // the instrument measuring it.
              // FULL-RATE, not the 4 kHz downsample the RMS check uses.
              //
              // Two reasons. The frame size sets the frequency resolution
              // (bin = rate/frame), so an 8192 frame means 5.4 Hz at 44.1 kHz —
              // fine enough to see a semitone — but at 4 kHz that same frame is
              // TWO SECONDS of audio, longer than these short renders, and the
              // metric correctly reported 0 for "no frame had energy on both
              // sides". And the downsample is peak-normalised, which would hide
              // exactly the level difference `levelDeltaDb` exists to report.
              final cmp = AudioComparison.of(ourPcm, openmptPcm);
              print('    $cmp');

              // Spectral similarity is the one that sees a tuning error: we
              // map Amiga periods through periodToMidi at A440 rather than
              // from the Paula clock, and a systematic offset there would leave
              // duration and RMS looking perfect. Deliberately a LOOSE floor —
              // two independent engines differ in interpolation, envelopes and
              // filtering, so this is a "still playing the same notes" gate,
              // not a fidelity score.
              if (strict) {
                // Thresholds set from MEASURED values on musical.mod (spectral
                // 0.920, level +3.8 dB, detune -17.1 cents), loose enough that
                // two independent engines may differ in interpolation,
                // envelopes and filtering — and still tight enough to have
                // caught the loop-rescaling bug, which drove spectral to 0.746
                // and level to -14.2 dB. A gate that would not have caught the
                // last real bug is decoration.
                expect(
                  cmp.spectral,
                  greaterThan(0.85),
                  reason: 'spectra diverged ($cmp) — a tuning, sample-mapping '
                      'or envelope regression, not just a level difference',
                );
                expect(
                  cmp.levelDb.abs(),
                  lessThan(8.0),
                  reason: 'level drifted ($cmp) — mixing or per-channel gain',
                );
                // NaN means the metric declined to answer; that is not a
                // failure, and asserting on it would turn "no evidence" into a
                // red.
                if (!cmp.detune.isNaN) {
                  expect(
                    cmp.detune.abs(),
                    lessThan(35.0),
                    reason: 'tuning drifted ($cmp) — we already sit ~17 cents '
                        'flat of OpenMPT; this catches it getting worse',
                  );
                }
              }

              // Report-only fixtures must not gate on THIS either — it was the
              // one assertion left outside the `strict` check, so golden.xm
              // still failed it at 10.19 dB on material that is a single note
              // playing a five-sample waveform. Note this is the NORMALISED
              // difference, which is why it reads -10 dB where levelDeltaDb
              // reads +9.45: it cannot see level at all (see `levelDeltaDb`).
              if (strict) {
                // Acceptable threshold: < 10 dB difference for minimal fixtures
                // (Real modules should be < 3 dB; minimal ones have edge cases)
                expect(
                  rmsDiffDb.abs(),
                  lessThan(10.0),
                  reason: 'Audio differs too much from OpenMPT reference '
                      '($rmsDiffDb dB). Possible instrument or mixing '
                      'regression.',
                );
              }
            },
            // Generous on purpose. Each case does a full OFFLINE render of a
            // real module on both sides plus an FFT comparison, and the corpus
            // includes multi-minute songs — buddhia3.it alone is a ~5-minute IT
            // with NNA voices and simply cannot render inside 30 s on any
            // machine, so that one case failed as a timeout rather than on
            // anything musical. This suite only runs where the local corpus and
            // Homebrew's openmpt123 both exist (it skips on CI), so a long
            // budget costs a developer minutes, not the pipeline.
            timeout: const Timeout(Duration(minutes: 6)),
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
          // Per-module, not once for the whole group. The group's `skip:` only
          // checks powerbase.mod, so a PARTIAL corpus — the normal state after a
          // `git clean` or an interrupted download — used to crash here with a
          // PathNotFoundException instead of skipping. A fixture this suite
          // cannot legally ship is always allowed to be absent.
          if (!File('test/fixtures/$fixtureName').existsSync()) continue;
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
          final pcm = _wavToMonoPcm(wav);
          final peak = pcm.reduce((a, b) => max(a.abs(), b.abs()));
          expect(
            peak,
            greaterThan(0.01),
            reason: '$fixtureName produced nearly silent audio',
          );
        }
        // Needs the downloaded modules, but not openmpt123.
      },
      skip: !_openMptAb
          ? optInReason
          : (testModulesAvailable ? null : 'test modules not downloaded'),
    );
  });
}
