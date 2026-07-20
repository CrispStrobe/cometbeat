// Build-time provenance, baked in at `flutter build` time via --dart-define
// (see .github/workflows/*.yml). Empty when built without the defines (a plain
// `flutter run` / IDE build), so the UI just falls back to the pubspec version.
class BuildInfo {
  const BuildInfo._();

  /// Short git commit SHA the build was made from (e.g. "2943ec8"), or '' when
  /// not injected. Wire it with `--dart-define=GIT_COMMIT=$(git rev-parse
  /// --short HEAD)`.
  static const commit = String.fromEnvironment('GIT_COMMIT');

  /// UTC build timestamp (e.g. "2026-07-20T10:14Z"), or '' when not injected.
  static const buildTime = String.fromEnvironment('BUILD_TIME');

  static bool get hasCommit => commit.isNotEmpty;

  /// `<version> · <commit>` when a commit is baked in, else just `<version>`.
  static String versionLabel(String version) =>
      hasCommit ? '$version · $commit' : version;
}
