// Native profile-only metrics. No production instrumentation or fake audio.
import 'dart:convert';
import 'dart:developer' as developer;
import 'dart:ffi';
import 'dart:io';
import 'dart:isolate';
import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';

class CompositionProfiler {
  CompositionProfiler() {
    if (!kProfileMode || !Platform.isMacOS) {
      throw StateError('Run with flutter drive --profile -d macos');
    }
  }

  // Darwin clock(3): cumulative process CPU time; CLOCKS_PER_SEC = 1,000,000.
  // Includes all process threads, not just the Dart UI isolate.
  final int Function() _clock = DynamicLibrary.process()
      .lookupFunction<IntPtr Function(), int Function()>('clock');
  final List<Map<String, Object?>> results = [];

  Future<Map<String, Object?>> _allocation({
    String method = 'getAllocationProfile',
    Map<String, String> parameters = const {},
  }) async {
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 2);
    try {
      final info = await developer.Service.getInfo();
      final uri = info.serverUri;
      if (uri == null) {
        return {'available': false, 'reason': 'No VM service URI'};
      }
      final request = await client.getUrl(
        uri.resolve(method).replace(
          queryParameters: {
            'isolateId': developer.Service.getIsolateId(Isolate.current)!,
            ...parameters,
          },
        ),
      );
      final response =
          await request.close().timeout(const Duration(seconds: 3));
      final body = jsonDecode(await response.transform(utf8.decoder).join())
          as Map<String, dynamic>;
      if (body.containsKey('error')) {
        return {'available': false, 'response': body};
      }
      return {'available': true, 'response': body};
    } catch (error) {
      return {'available': false, 'reason': error.toString()};
    } finally {
      client.close(force: true);
    }
  }

  Future<void> measure(
    String editor,
    String phase,
    Future<void> Function() body,
  ) async {
    // Allocation snapshots are outside the CPU/frame window; no forced GC/reset.
    final allocationBefore = await _allocation();
    final frames = <FrameTiming>[];
    void collect(List<FrameTiming> batch) => frames.addAll(batch);
    SchedulerBinding.instance.addTimingsCallback(collect);
    final rssBefore = ProcessInfo.currentRss;
    final cpuBefore = _clock();
    final startUs = developer.Timeline.now;
    final task = developer.TimelineTask()..start('composition/$editor/$phase');
    Object? failure;
    try {
      await body();
    } catch (error) {
      failure = error;
      rethrow;
    } finally {
      final endUs = developer.Timeline.now;
      final cpuAfter = _clock();
      final rssAfter = ProcessInfo.currentRss;
      task.finish();
      // Engine FrameTiming delivery is batched. Flush, then filter by frame time.
      await Future<void>.delayed(const Duration(milliseconds: 500));
      SchedulerBinding.instance.removeTimingsCallback(collect);
      final allocationAfter = await _allocation();
      final cpuSamples = await _allocation(
        method: 'getCpuSamples',
        parameters: {
          'timeOriginMicros': '$startUs',
          'timeExtentMicros': '${endUs - startUs}',
        },
      );
      final measured = frames.where((f) {
        final t = f.timestampInMicroseconds(FramePhase.vsyncStart);
        return t >= startUs && t <= endUs;
      }).toList();
      final wallMs = (endUs - startUs) / 1000;
      final cpuMs =
          cpuBefore < 0 || cpuAfter < 0 ? null : (cpuAfter - cpuBefore) / 1000;
      results.add({
        'editor': editor,
        'phase': phase,
        'wall_ms': wallMs,
        'failure': failure?.toString(),
        'process_cpu_ms': cpuMs,
        'process_cpu_percent_one_core':
            cpuMs == null ? null : cpuMs / wallMs * 100,
        'rss_before_bytes': rssBefore,
        'rss_after_bytes': rssAfter,
        'max_rss_bytes': ProcessInfo.maxRss,
        'frame_count': measured.length,
        'build_ms':
            _stats(measured.map((f) => f.buildDuration.inMicroseconds / 1000)),
        'raster_ms':
            _stats(measured.map((f) => f.rasterDuration.inMicroseconds / 1000)),
        'total_span_ms':
            _stats(measured.map((f) => f.totalSpan.inMicroseconds / 1000)),
        'frames': [
          for (final f in measured)
            {
              'vsync_us': f.timestampInMicroseconds(FramePhase.vsyncStart),
              'build_us': f.buildDuration.inMicroseconds,
              'raster_us': f.rasterDuration.inMicroseconds,
              'total_span_us': f.totalSpan.inMicroseconds,
            },
        ],
        'cpu_samples': cpuSamples,
        'allocation_before': allocationBefore,
        'allocation_after': allocationAfter,
      });
    }
  }

  Map<String, Object?> _stats(Iterable<double> values) {
    final sorted = values.toList()..sort();
    if (sorted.isEmpty) return {'available': false};
    double p(double q) =>
        sorted[((sorted.length * q).ceil() - 1).clamp(0, sorted.length - 1)];
    return {
      'mean': sorted.reduce((a, b) => a + b) / sorted.length,
      'p50': p(.5),
      'p90': p(.9),
      'p99': p(.99),
      'max': sorted.last,
      'over_16_67ms': sorted.where((v) => v > 1000 / 60).length,
    };
  }

  Future<String> save(Map<String, Object?> metadata) async {
    const runId =
        String.fromEnvironment('PROFILE_RUN_ID', defaultValue: 'manual');
    final directory =
        Directory('${Directory.systemTemp.path}/composition-profile/$runId')
          ..createSync(recursive: true);
    final file = File('${directory.path}/metrics.json');
    await file
        .writeAsString(jsonEncode({'metadata': metadata, 'results': results}));
    // ignore: avoid_print
    print('COMPOSITION_PROFILE_ARTIFACT=${file.path}');
    return file.path;
  }
}
