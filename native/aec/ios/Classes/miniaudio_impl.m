// Forwarder (Objective-C) — on iOS the miniaudio implementation must be compiled
// as Objective-C because its Core Audio backend uses AVAudioSession (see
// miniaudio.h: "The iOS build needs to be compiled as Objective-C"). macOS uses
// the plain Core Audio C API, so its forwarder stays .c. The pure-C aec_dsp.c /
// aec_shim.c forwarders only pull miniaudio DECLARATIONS (no AVFoundation), so
// they remain .c on iOS too.
#include "../../src/miniaudio_impl.c"
