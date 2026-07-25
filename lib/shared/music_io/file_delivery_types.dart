// Result of delivering exported bytes to the user, so the caller can show the
// right confirmation (a saved path on desktop, a download on web) or stay quiet
// when the user cancels the save dialog.

/// How the exported bytes reached the user.
enum DeliveryKind {
  /// Written to a file the user picked (desktop save dialog).
  saved,

  /// Handed to the browser as a download (web).
  downloaded,

  /// The user dismissed the save dialog — nothing was written.
  cancelled,
}

/// The outcome of [deliverBytes], carrying the file path when one exists.
class DeliveryResult {
  const DeliveryResult(this.kind, {this.path});

  final DeliveryKind kind;

  /// The written file's path (only for [DeliveryKind.saved]).
  final String? path;
}
