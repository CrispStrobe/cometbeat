// Ogg-Opus file -> PCM, the decode counterpart of glint_encode_audio's Opus
// output. LOCAL to this plugin (not vendored by sync_glint.sh), like
// flac_c_api.cpp: pure glue over glint's OggOpusReader + OpusDecoder, no
// codec logic of its own. It exists so the encode round-trip is verifiable
// end to end — encode a tone, decode it back, assert the pitch survived —
// from Dart on every platform, without pulling in glint's whole
// decode_audio_c_api closure (which would add the MP3 and AAC decoders).
//
// The body mirrors glint's own decode_opus() in src/decode_audio_c_api.cpp,
// including the edit list: apply output gain, drop pre_skip samples, then
// truncate to the last page's granule.
//
// NAMING: the symbol is deliberately `cometbeat_`-prefixed, not `glint_`.
// flac_c_api.cpp took the `glint_flac_decode` name and glint later defined
// that symbol itself in decode_audio_c_api.cpp — vendoring that file now
// collides. Ours cannot.
//
// MIT License.

#include <cstdint>
#include <cstdlib>
#include <cstring>
#include <vector>

#include "opus_decoder.hpp"
#include "opus_ms_decoder.hpp"
#include "opus_ogg.hpp"

extern "C" {

// Decode a complete in-memory Ogg-Opus stream to interleaved float PCM
// (+-1.0) at 48 kHz. Returns a malloc'd buffer of *out_frames * *out_ch
// floats — free with glint_free — or NULL if this is not a decodable
// Ogg-Opus stream. out_sr is always 48000 (Opus decodes natively there).
float* cometbeat_opus_file_decode(const uint8_t* ogg, int len, int* out_sr,
                                  int* out_ch, int* out_frames) {
    if (out_sr) *out_sr = 0;
    if (out_ch) *out_ch = 0;
    if (out_frames) *out_frames = 0;
    if (!ogg || len <= 0) return nullptr;

    glint::opus::OggOpusReader r;
    if (r.parse(ogg, static_cast<size_t>(len)) != 0) return nullptr;
    const glint::opus::OpusHead& h = r.head();
    int ch = h.channels;
    if (ch < 1 || ch > 8) return nullptr;

    // 5760 = 120 ms at 48 kHz, the largest Opus frame.
    std::vector<float> scratch(static_cast<size_t>(5760) * ch);
    std::vector<float> out;

    if (h.mapping_family == 0) {
        glint::opus::OpusDecoder dec;
        dec.init(ch);
        for (int i = 0; i < r.packet_count(); i++) {
            const std::vector<uint8_t>& p = r.packet(i);
            int s = dec.decode(p.data(), static_cast<int>(p.size()),
                               scratch.data(), 5760);
            if (s > 0)
                out.insert(out.end(), scratch.data(),
                           scratch.data() + static_cast<size_t>(s) * ch);
        }
    } else {
        glint::opus::OpusMsDecoder dec;
        if (dec.init(ch, h.stream_count, h.coupled_count, h.mapping) != 0)
            return nullptr;
        for (int i = 0; i < r.packet_count(); i++) {
            const std::vector<uint8_t>& p = r.packet(i);
            int s = dec.decode(p.data(), static_cast<int>(p.size()),
                               scratch.data(), 5760);
            if (s > 0)
                out.insert(out.end(), scratch.data(),
                           scratch.data() + static_cast<size_t>(s) * ch);
        }
    }

    // Edit list: gain, then pre-skip, then the end-trim granule.
    double gain = r.output_gain();
    if (gain != 1.0)
        for (size_t i = 0; i < out.size(); i++)
            out[i] = static_cast<float>(out[i] * gain);
    int pre = h.pre_skip;
    if (pre > 0 &&
        out.size() >= static_cast<size_t>(pre) * static_cast<size_t>(ch))
        out.erase(out.begin(),
                  out.begin() + static_cast<size_t>(pre) * ch);
    int64_t total = r.total_samples();
    if (total >= 0 &&
        out.size() > static_cast<size_t>(total) * static_cast<size_t>(ch))
        out.resize(static_cast<size_t>(total) * ch);

    if (out.empty()) return nullptr;
    float* buf = static_cast<float*>(std::malloc(sizeof(float) * out.size()));
    if (!buf) return nullptr;
    std::memcpy(buf, out.data(), sizeof(float) * out.size());
    if (out_sr) *out_sr = 48000;
    if (out_ch) *out_ch = ch;
    if (out_frames) *out_frames = static_cast<int>(out.size() / ch);
    return buf;
}

}  // extern "C"
