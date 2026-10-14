// lib/core/services/error_log.dart
//
// The app's black box: every uncaught error, kept on the device.
//
// Six platforms, FFI and ONNX, and until this file nothing caught an error
// that escaped a widget build or an unawaited future — in a release build it
// vanished. This records them to a small rolling log that survives a restart,
// and Settings ▸ Debug shows it, so a failure in the field can be read back
// (and copied into a bug report) instead of being described from memory.
//
// Nothing leaves the device. There is no reporting service here on purpose:
// this is a children's app, and "send diagnostics" is a decision for a parent
// to make by copying the text, not for the app to make for them.

import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// One recorded error.
class ErrorLogEntry {
  const ErrorLogEntry({
    required this.time,
    required this.source,
    required this.message,
    required this.stack,
  });

  final DateTime time;

  /// Where it was caught: `flutter` (framework: build/layout/paint/gesture) or
  /// `platform` (an uncaught async error).
  final String source;
  final String message;

  /// The first [ErrorLog.maxStackLines] frames; empty when none was given.
  final String stack;

  Map<String, dynamic> toJson() => {
        't': time.toUtc().toIso8601String(),
        's': source,
        'm': message,
        'k': stack,
      };

  static ErrorLogEntry? fromJson(Object? json) {
    if (json is! Map) return null;
    final time = DateTime.tryParse('${json['t']}');
    final message = json['m'];
    if (time == null || message is! String) return null;
    return ErrorLogEntry(
      time: time,
      source: '${json['s'] ?? ''}',
      message: message,
      stack: '${json['k'] ?? ''}',
    );
  }

  @override
  String toString() => '[${time.toUtc().toIso8601String()}] $source: $message'
      '${stack.isEmpty ? '' : '\n$stack'}';
}

class ErrorLog with ChangeNotifier {
  ErrorLog({DateTime Function()? now}) : _now = now ?? DateTime.now;

  /// The app-wide log the global handlers write to.
  static final ErrorLog instance = ErrorLog();

  static const _key = 'error_log_v1';

  /// Entries kept; the oldest is dropped beyond this.
  static const maxEntries = 50;

  /// Stack frames kept per entry — enough to locate it, small enough that 50
  /// entries stay a few kilobytes in preferences.
  static const maxStackLines = 12;
  static const _maxMessageLength = 600;

  final DateTime Function() _now;
  List<ErrorLogEntry> _entries = [];
  bool _loaded = false;
  bool _unsaved = false;

  /// Newest first.
  List<ErrorLogEntry> get entries => List.unmodifiable(_entries.reversed);

  bool get isEmpty => _entries.isEmpty;

  /// Restores what earlier runs recorded. Entries recorded before this
  /// completes (an error during start-up) are kept, after the stored ones.
  ///
  /// Nothing is WRITTEN until this has run: a start-up error saved on its own
  /// would overwrite the stored log before it had been read.
  Future<void> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_key);
      if (raw != null) {
        final stored = [
          for (final e in json.decode(raw) as List<dynamic>)
            if (ErrorLogEntry.fromJson(e) case final entry?) entry,
        ];
        _entries = _trimmed([...stored, ..._entries]);
        notifyListeners();
      }
    } catch (_) {
      // An unreadable log is not worth an error of its own: start empty.
    }
    _loaded = true;
    if (_unsaved) await _save();
  }

  static List<ErrorLogEntry> _trimmed(List<ErrorLogEntry> all) =>
      all.length <= maxEntries ? all : all.sublist(all.length - maxEntries);

  /// Records [error]. Never throws — an error handler that throws would take
  /// the place of the error it was reporting.
  void record(Object error, StackTrace? stack, {required String source}) {
    try {
      var message = error.toString();
      if (message.length > _maxMessageLength) {
        message = '${message.substring(0, _maxMessageLength)}…';
      }
      final frames = stack == null
          ? const <String>[]
          : stack.toString().trimRight().split('\n');
      _entries = _trimmed([
        ..._entries,
        ErrorLogEntry(
          time: _now(),
          source: source,
          message: message,
          stack: frames.take(maxStackLines).join('\n'),
        ),
      ]);
      // A framework error is reported mid-frame, where notifying listeners
      // would itself throw ("setState during build"): defer it.
      scheduleMicrotask(notifyListeners);
      unawaited(_save());
    } catch (_) {
      // See the doc comment: swallowing here is the point.
    }
  }

  Future<void> clear() async {
    _entries = [];
    notifyListeners();
    await _save();
  }

  /// The whole log as plain text, newest first — for copying into a report.
  String asText() => entries.join('\n\n');

  Future<void> _save() async {
    if (!_loaded) {
      _unsaved = true; // load() writes it once the stored log has been merged
      return;
    }
    _unsaved = false;
    try {
      final encoded = json.encode([for (final e in _entries) e.toJson()]);
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_key, encoded);
    } catch (_) {
      // Storage being unavailable must not turn into a second error.
    }
  }
}

/// Routes every uncaught error into [log], keeping what the framework already
/// does with it (the red-screen / console dump in debug builds).
void installErrorHandlers(ErrorLog log) {
  final previous = FlutterError.onError;
  FlutterError.onError = (details) {
    log.record(details.exception, details.stack, source: 'flutter');
    previous?.call(details);
  };
  PlatformDispatcher.instance.onError = (error, stack) {
    log.record(error, stack, source: 'platform');
    if (kDebugMode) debugPrint('Uncaught: $error\n$stack');
    // Handled: without this an uncaught async error ends the isolate on some
    // embedders, and a children's app should not close over a failed fetch.
    return true;
  };
}
