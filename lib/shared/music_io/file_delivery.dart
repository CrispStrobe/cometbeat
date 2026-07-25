// Cross-platform delivery of exported bytes to the user.
//
// Desktop has a native "Save as…" dialog (file_selector's getSaveLocation);
// the web has no filesystem, so an export must be handed to the browser as a
// download instead. This facade picks the right one at compile time so callers
// (Score Workshop export, …) get a working Save/Download on every platform
// instead of a save dialog that throws on web.
//
// The default is the io implementation (desktop save dialog); web swaps in the
// browser-download implementation. Native share sheets (iOS/macOS/AirDrop) are a
// follow-up that needs a share plugin.
export 'file_delivery_io.dart'
    if (dart.library.js_interop) 'file_delivery_web.dart';
export 'file_delivery_types.dart';
