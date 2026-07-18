// glint_free: its real definition (src/decoder_c_api.cpp) is entangled with
// the AAC/MP3 decoders, which the Vorbis-only plugin does not compile. It is just
// free(); provide it here so glint_vorbis_decode buffers can be released.
#include <cstdlib>
extern "C" void glint_free(void* p) { std::free(p); }
