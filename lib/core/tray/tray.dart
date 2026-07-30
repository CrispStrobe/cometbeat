// lib/core/tray/tray.dart
//
// WS-X6 slice 1 — the clipboard's contents.
//
// One shelf of things worth reusing, shared by every editor: a few samples put
// there from the Audio Editor and used as instruments in Loop Studio, a riff or
// a drum beat copied out of Loop Studio and placed in the Audio Editor.
//
// ⚠️ WHY THE TYPE IS NOT CALLED `Clipboard`, when that is exactly what it is.
// The name is taken twice over: Flutter's own `Clipboard` is imported by the
// Audio Editor, and four surfaces already keep private per-screen clipboards
// (`_clipClipboard` and friends) that this does NOT replace — those are
// "copy this clip, paste it two bars later", a within-surface convenience.
// `Shelf` is taken too: it is EQ terminology throughout the DSP files, so
// grepping for it returns low-shelf filters. Hence `Tray` in code, which occurs
// nowhere in `lib/` except inside the words "stray" and "betrayed". The UI says
// "Clipboard", because that is the word the person using it will think in.
//
// SYMBOLIC THINGS GO IN BY VALUE; HEAVY THINGS WILL GO IN BY REFERENCE. A
// groove, a riff, a run of tab columns are small, immutable documents and are
// held directly. Samples and instruments are not — "all the samples of a drum
// kit" is megabytes of PCM, and a clipboard that copied them could never be
// persisted and would double the memory of the thing it was copied from. Those
// already live in `InstrumentLibraryStore`, so slice 3 will name one rather than
// copy it. [TrayItem.libraryName] is that hook, unused today and reserved so the
// shape does not have to change under existing items.
//
// PURE DART, no Flutter: the whole model is testable headlessly, and the panel
// that draws it is a separate file.

import 'package:comet_beat/core/interop/app_mode.dart';
import 'package:comet_beat/core/interop/drag_payload.dart';

/// One thing on the clipboard.
class TrayItem {
  const TrayItem({
    required this.id,
    required this.kind,
    required this.label,
    required this.document,
    required this.addedAtMs,
    this.libraryName,
  });

  /// Stable for this item's lifetime — used as a widget key, and as the handle
  /// the (X) button passes back. Not derived from the content: two identical
  /// riffs are two items, because a player who put the same thing on twice
  /// meant to.
  final String id;

  /// What it is, in the same vocabulary the drop targets already speak.
  final AppMode kind;

  /// What the chip says. Supplied by whoever put it there, because only they
  /// know whether this is "Drums" or "the bit before the chorus".
  final String label;

  /// The document itself, for the symbolic kinds.
  final Object document;

  /// Reserved for slice 3: the name of an `InstrumentLibraryStore` entry, for
  /// items too heavy to hold by value. Null for everything today.
  final String? libraryName;

  final int addedAtMs;

  /// What a drag or a tap hands to a drop target — the SAME payload the four
  /// existing targets already accept, which is why they need no change to
  /// receive from here.
  MusicDragPayload get payload =>
      MusicDragPayload(kind: kind, document: document, label: label);
}

/// The clipboard. One instance, provided app-wide.
class TrayService {
  TrayService({this.maxItems = 60}) : assert(maxItems > 0, 'need room for one');

  /// How many it holds. Generous because the maintainer's own examples are
  /// bulk — every instrument of a tracker track, every sample of a drum kit —
  /// and a clipboard that forgets the fourth thing you put on it is not one.
  /// The OLDEST is dropped, never the newest.
  final int maxItems;

  final List<TrayItem> _items = [];
  int _nextId = 0;

  final List<void Function()> _listeners = [];

  /// Newest first — what you just put there is what you are about to use.
  List<TrayItem> get items => List.unmodifiable(_items);

  bool get isEmpty => _items.isEmpty;
  int get length => _items.length;

  /// Puts [document] on the clipboard and returns the item.
  ///
  /// [nowMs] is injected rather than read from the clock so a test can assert
  /// ordering without sleeping.
  TrayItem add({
    required AppMode kind,
    required String label,
    required Object document,
    String? libraryName,
    int? nowMs,
  }) {
    final item = TrayItem(
      id: 'tray-${_nextId++}',
      kind: kind,
      label: label,
      document: document,
      libraryName: libraryName,
      addedAtMs: nowMs ?? DateTime.now().millisecondsSinceEpoch,
    );
    _items.insert(0, item);
    if (_items.length > maxItems) _items.removeLast();
    _notify();
    return item;
  }

  /// Removes one item — what the (X) on a chip does. Silently ignores an id
  /// that is not there, because a double-tap on (X) is not an error.
  void remove(String id) {
    final before = _items.length;
    _items.removeWhere((i) => i.id == id);
    if (_items.length != before) _notify();
  }

  void clear() {
    if (_items.isEmpty) return;
    _items.clear();
    _notify();
  }

  TrayItem? byId(String id) {
    for (final item in _items) {
      if (item.id == id) return item;
    }
    return null;
  }

  /// Everything of one kind, newest first — for a surface that wants to offer
  /// only what it can actually take.
  List<TrayItem> ofKind(AppMode kind) => [
        for (final i in _items)
          if (i.kind == kind) i,
      ];

  // A hand-rolled listener list rather than `ChangeNotifier`, so this file
  // stays Flutter-free and the model can be tested without a binding. The panel
  // adapts it to a `Listenable`.
  void addListener(void Function() listener) => _listeners.add(listener);

  void removeListener(void Function() listener) => _listeners.remove(listener);

  void _notify() {
    // Over a copy: a listener that removes itself while being notified would
    // otherwise mutate the list mid-iteration.
    for (final listener in [..._listeners]) {
      listener();
    }
  }
}
