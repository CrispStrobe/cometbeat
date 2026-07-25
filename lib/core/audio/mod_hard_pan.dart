// Apply hard-wired MOD panning
import 'package:comet_beat/core/audio/mod/module_doc.dart' show ModuleFormat;

// Add this logic to songFromModuleDoc after creating the channels:

// Apply hard-wired ProTracker MOD panning for 4-channel MODs
// Channel 0 = Left, Channel 1 = Right, Channel 2 = Right, Channel 3 = Left
// This is hardware-dependent (Paula chip) and NOT stored in the file.
void applyModHardPanning(List<TrackerChannel> channels, ModuleFormat format) {
  if (format == ModuleFormat.mod && channels.length == 4) {
    channels[0] = channels[0].copyWith(pan: -1.0); // Left
    channels[1] = channels[1].copyWith(pan: 1.0); // Right
    channels[2] = channels[2].copyWith(pan: 1.0); // Right
    channels[3] = channels[3].copyWith(pan: -1.0); // Left
  }
}
