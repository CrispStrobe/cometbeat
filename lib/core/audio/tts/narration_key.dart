// narration_key.dart — the shared, PURE-DART key logic for pre-baked narration.
// Imported by BOTH the runtime lookup (prebaked_narration.dart) and the offline
// bake tool (tool/bake_narration.dart), so the key computed at bake time
// matches the key looked up at runtime on every target (VM, web, wasm).
//
// The key is a plain string (`"<lang>|<normalized text>"`), never a numeric
// hash — a VM-side hash wouldn't match on the web (53-bit ints).

/// Collapse whitespace + trim so trivial formatting differences still match.
String normalizeNarration(String text) =>
    text.trim().replaceAll(RegExp(r'\s+'), ' ');

String narrationLang(String langCode) =>
    langCode.toLowerCase().split(RegExp('[-_]')).first;

/// The manifest key for a narration string — `"<lang>|<normalized text>"`.
String narrationKey(String text, String langCode) =>
    '${narrationLang(langCode)}|${normalizeNarration(text)}';
