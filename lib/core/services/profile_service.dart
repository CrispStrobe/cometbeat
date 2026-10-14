// lib/core/services/profile_service.dart
//
// Learner profiles and progress backup.
//
// A profile is a name plus a storage scope (see learner_scope.dart). Switching
// one re-points the scope and reloads the per-learner stores registered via
// [addReloader]. A backup is one profile's learner data as a JSON document;
// restoring always creates a NEW profile, so a restore can never overwrite
// somebody's progress.

import 'dart:convert';

import 'package:comet_beat/core/services/learner_scope.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// One learner on this device.
class LearnerProfile {
  const LearnerProfile({required this.id, required this.name});

  final String id;

  /// The name the learner typed. Empty for the built-in first profile until it
  /// is renamed — the UI shows a localized placeholder then.
  final String name;

  Map<String, dynamic> toJson() => {'id': id, 'name': name};

  static LearnerProfile? fromJson(Object? json) {
    if (json is! Map) return null;
    final id = json['id'];
    final name = json['name'];
    if (id is! String || id.isEmpty || name is! String) return null;
    return LearnerProfile(id: id, name: name);
  }
}

class ProfileService with ChangeNotifier {
  static const _profilesKey = 'learner_profiles_v1';
  static const _activeKey = 'learner_active';

  /// `format` of a backup document.
  static const backupFormat = 'cometbeat-learner';
  static const backupVersion = 1;

  // The per-learner keys (un-scoped names). Kept here rather than imported
  // from their owning services so a backup's shape is defined in one place.
  static const _sriKey = 'sri_database';
  static const _progressKey = 'game_progress';
  static const _daysKey = 'practice_days';
  static const _tutorialPrefix = 'tutorial_seen_';
  static const _songsKey = 'user_songs';

  List<LearnerProfile> _profiles = const [
    LearnerProfile(id: kDefaultLearnerId, name: ''),
  ];
  String _activeId = kDefaultLearnerId;
  final List<Future<void> Function()> _reloaders = [];

  List<LearnerProfile> get profiles => List.unmodifiable(_profiles);

  LearnerProfile get active => _profiles.firstWhere(
        (p) => p.id == _activeId,
        orElse: () => _profiles[0],
      );

  /// Registers a per-learner store's reload, run after every profile switch.
  void addReloader(Future<void> Function() reload) => _reloaders.add(reload);

  /// Reads the profile list and points the learner scope at the active one.
  /// Must complete BEFORE any per-learner store loads (main() awaits it).
  Future<void> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_profilesKey);
      if (raw != null) {
        final list = [
          for (final e in json.decode(raw) as List<dynamic>)
            if (LearnerProfile.fromJson(e) case final p?) p,
        ];
        if (list.isNotEmpty) _profiles = list;
      }
      final active = prefs.getString(_activeKey);
      if (active != null && _profiles.any((p) => p.id == active)) {
        _activeId = active;
      }
    } catch (e) {
      if (kDebugMode) debugPrint('[PROFILE] load failed: $e');
    }
    setLearnerScope(_activeId);
    notifyListeners();
  }

  Future<void> _save() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _profilesKey,
      json.encode([for (final p in _profiles) p.toJson()]),
    );
    await prefs.setString(_activeKey, _activeId);
  }

  Future<void> _activate(String id) async {
    _activeId = id;
    setLearnerScope(id);
    for (final reload in _reloaders) {
      await reload();
    }
    notifyListeners();
    await _save();
  }

  /// Makes [id] the active learner and reloads their data.
  Future<void> switchTo(String id) async {
    if (id == _activeId || !_profiles.any((p) => p.id == id)) return;
    await _activate(id);
  }

  String _newId() {
    var n = DateTime.now().microsecondsSinceEpoch;
    while (_profiles.any((p) => p.id == n.toRadixString(36))) {
      n++;
    }
    return n.toRadixString(36);
  }

  /// Adds a learner called [name], starting from nothing, and switches to
  /// them.
  Future<LearnerProfile> add(String name) async {
    final profile = LearnerProfile(id: _newId(), name: name.trim());
    _profiles = [..._profiles, profile];
    await _activate(profile.id);
    return profile;
  }

  Future<void> rename(String id, String name) async {
    _profiles = [
      for (final p in _profiles)
        p.id == id ? LearnerProfile(id: id, name: name.trim()) : p,
    ];
    notifyListeners();
    await _save();
  }

  /// Whether [id] may be deleted: the built-in first profile cannot be (it
  /// owns the un-prefixed keys), and there is always at least one learner.
  bool canDelete(String id) => id != kDefaultLearnerId && _profiles.length > 1;

  /// Deletes learner [id] and everything stored for them.
  Future<void> delete(String id) async {
    if (!canDelete(id)) return;
    if (id == _activeId) await _activate(kDefaultLearnerId);
    _profiles = [
      for (final p in _profiles)
        if (p.id != id) p,
    ];
    final prefs = await SharedPreferences.getInstance();
    final scope = learnerKeyFor(id, '');
    for (final key in prefs.getKeys().toList()) {
      if (key.startsWith(scope)) await prefs.remove(key);
    }
    notifyListeners();
    await _save();
  }

  /// The active learner's data as a backup document (pretty-printed JSON).
  /// [displayName] is recorded as the backup's name — pass the placeholder the
  /// UI shows when the profile has none of its own.
  Future<String> exportActive({String? displayName}) async {
    final prefs = await SharedPreferences.getInstance();
    Object? decoded(String base) {
      final raw = prefs.getString(learnerKey(base));
      return raw == null ? null : json.decode(raw);
    }

    final seenPrefix = learnerKey(_tutorialPrefix);
    return const JsonEncoder.withIndent(' ').convert({
      'format': backupFormat,
      'version': backupVersion,
      'name': active.name.isNotEmpty ? active.name : (displayName ?? ''),
      'exported': DateTime.now().toUtc().toIso8601String(),
      'data': {
        'sri': decoded(_sriKey) ?? <String, dynamic>{},
        'progress': decoded(_progressKey) ?? <String, dynamic>{},
        'practiceDays':
            prefs.getStringList(learnerKey(_daysKey)) ?? const <String>[],
        // Optional on import: version-1 backups written before songs were
        // per learner simply have none.
        'songs': decoded(_songsKey),
        'tutorialsSeen': [
          for (final key in prefs.getKeys())
            if (key.startsWith(seenPrefix) && (prefs.getBool(key) ?? false))
              key.substring(seenPrefix.length),
        ]..sort(),
      },
    });
  }

  /// Restores a backup [document] as a NEW learner and switches to them.
  /// Throws [FormatException] if it is not a backup this version can read;
  /// nothing is written in that case.
  Future<LearnerProfile> importAsNew(String document) async {
    final Object? root;
    try {
      root = json.decode(document);
    } on FormatException {
      throw const FormatException('not JSON');
    }
    if (root is! Map<String, dynamic> || root['format'] != backupFormat) {
      throw const FormatException('not a CometBeat learner backup');
    }
    final version = root['version'];
    if (version is! int || version > backupVersion) {
      throw const FormatException('backup is from a newer version');
    }
    final data = root['data'];
    if (data is! Map<String, dynamic>) {
      throw const FormatException('backup has no data');
    }
    final sri = data['sri'];
    final progress = data['progress'];
    final days = data['practiceDays'];
    final seen = data['tutorialsSeen'];
    if (sri is! Map<String, dynamic> ||
        progress is! Map<String, dynamic> ||
        days is! List<dynamic> ||
        seen is! List<dynamic> ||
        sri.values.any((v) => v is! Map<String, dynamic>) ||
        progress.values.any((v) => v is! Map<String, dynamic>)) {
      throw const FormatException('backup data is malformed');
    }

    // Validated: only now does anything get written.
    final name = root['name'];
    final profile = LearnerProfile(
      id: _newId(),
      name: name is String ? name.trim() : '',
    );
    final prefs = await SharedPreferences.getInstance();
    String key(String base) => learnerKeyFor(profile.id, base);
    await prefs.setString(key(_sriKey), json.encode(sri));
    await prefs.setString(key(_progressKey), json.encode(progress));
    await prefs.setStringList(key(_daysKey), days.whereType<String>().toList());
    final songs = data['songs'];
    if (songs is Map<String, dynamic>) {
      await prefs.setString(key(_songsKey), json.encode(songs));
    }
    for (final gameId in seen.whereType<String>()) {
      await prefs.setBool(key('$_tutorialPrefix$gameId'), true);
    }
    _profiles = [..._profiles, profile];
    await _activate(profile.id);
    return profile;
  }
}
