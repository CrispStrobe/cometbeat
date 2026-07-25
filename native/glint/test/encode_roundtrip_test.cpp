// Native verification for the glint ENCODE seam this plugin vendors.
// Render -> encode -> decode -> assert, not "it compiled":
//
//   1. Opus  — a 440 Hz tone survives encode+decode with its pitch intact.
//              Opus always decodes at 48 kHz, so we assert the PITCH, never
//              the sample rate.
//   2. Stereo — hard-panned L/R do not collapse into each other or swap.
//   3. MP3 / AAC — structurally valid streams (MPEG / ADTS sync, plausible
//              size). This plugin vendors no MP3/AAC *decoder*, so their deep
//              verification lives in glint's own decoder gates upstream.
//   4. Bad input is rejected without a crash, and a long encode/free loop
//              does not grow RSS — that is where a wrong glint_free shows up.
//
// Build:  cmake -B build -DGLINT_BUILD_TESTS=ON native/glint/src
//         cmake --build build && ctest --test-dir build --output-on-failure

#include <sys/resource.h>

#include <algorithm>
#include <cmath>
#include <cstdint>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <vector>

#include "glint/glint.h"

// Our local Ogg-Opus decode glue (src/opus_file_c_api.cpp).
extern "C" float* cometbeat_opus_file_decode(const uint8_t* ogg, int len,
                                             int* out_sr, int* out_ch,
                                             int* out_frames);

namespace {

int g_failures = 0;

void check(bool ok, const char* what) {
    std::printf("  [%s] %s\n", ok ? "PASS" : "FAIL", what);
    if (!ok) g_failures++;
}

void checkf(bool ok, const char* what, double got, double want) {
    std::printf("  [%s] %s (got %.3f, want %.3f)\n", ok ? "PASS" : "FAIL", what,
                got, want);
    if (!ok) g_failures++;
}

constexpr double kPi = 3.14159265358979323846;

// Interleaved sine. `freqs` gives one frequency per channel, so a
// hard-panned pair is just two different entries.
std::vector<float> tone(const std::vector<double>& freqs, int sample_rate,
                        double seconds, double amp = 0.5) {
    int ch = static_cast<int>(freqs.size());
    int frames = static_cast<int>(sample_rate * seconds);
    std::vector<float> pcm(static_cast<size_t>(frames) * ch);
    for (int i = 0; i < frames; i++)
        for (int c = 0; c < ch; c++)
            pcm[static_cast<size_t>(i) * ch + c] = static_cast<float>(
                amp * std::sin(2.0 * kPi * freqs[c] * i / sample_rate));
    return pcm;
}

// Autocorrelation pitch estimate over one channel of an interleaved buffer.
// The signal under test is a pure tone, but two details still matter and both
// bit me while writing this:
//
//   * every lag must correlate the SAME number of terms. Dividing by (n-lag)
//     instead inflates long lags, and the estimator happily reports 80 Hz for
//     an 880 Hz tone (lag 600 = 11 periods).
//   * a periodic signal correlates just as well at 2T, 3T, ... as at T, so
//     take the FIRST lag that reaches most of the peak, not the global max.
//
// Parabolic interpolation on the chosen lag is not optional either: at 48 kHz
// an 880 Hz period is 54.5 samples, and the neighbouring integer lags read
// 872.7 / 888.9 Hz.
double estimate_pitch(const float* pcm, int frames, int ch, int channel,
                      int sample_rate) {
    // Skip the codec's start-up transient, then take a stable window.
    int skip = std::min(frames / 4, sample_rate / 4);
    int n = std::min(frames - skip, sample_rate / 2);
    if (n < 2048) return 0.0;
    std::vector<double> x(n);
    for (int i = 0; i < n; i++)
        x[i] = pcm[static_cast<size_t>(skip + i) * ch + channel];

    int min_lag = sample_rate / 2000;  // 2 kHz ceiling
    int max_lag = sample_rate / 50;    // 50 Hz floor
    if (max_lag >= n / 2) max_lag = n / 2 - 1;
    if (max_lag <= min_lag) return 0.0;
    int terms = n - max_lag;  // same term count for every lag

    std::vector<double> r(max_lag + 1, 0.0);
    double peak = 0.0;
    for (int lag = min_lag; lag <= max_lag; lag++) {
        double s = 0.0;
        for (int i = 0; i < terms; i++) s += x[i] * x[i + lag];
        r[lag] = s;
        if (s > peak) peak = s;
    }
    if (peak <= 0.0) return 0.0;

    // First local maximum reaching 85% of the global peak = the fundamental.
    int best_lag = 0;
    for (int lag = min_lag + 1; lag < max_lag; lag++) {
        if (r[lag] >= 0.85 * peak && r[lag] >= r[lag - 1] &&
            r[lag] >= r[lag + 1]) {
            best_lag = lag;
            break;
        }
    }
    if (best_lag <= 0) return 0.0;

    // Parabolic interpolation through (lag-1, lag, lag+1).
    double y0 = r[best_lag - 1], y1 = r[best_lag], y2 = r[best_lag + 1];
    double denom = 2.0 * (2.0 * y1 - y0 - y2);
    double refined = best_lag;
    if (denom != 0.0) refined += (y2 - y0) / denom;
    return refined > 0.0 ? static_cast<double>(sample_rate) / refined : 0.0;
}

double rms(const float* pcm, int frames, int ch, int channel) {
    double s = 0.0;
    for (int i = 0; i < frames; i++) {
        double v = pcm[static_cast<size_t>(i) * ch + channel];
        s += v * v;
    }
    return frames > 0 ? std::sqrt(s / frames) : 0.0;
}

long peak_rss_kb() {
    struct rusage ru;
    getrusage(RUSAGE_SELF, &ru);
#ifdef __APPLE__
    return ru.ru_maxrss / 1024;  // bytes on Darwin
#else
    return ru.ru_maxrss;  // kilobytes on Linux
#endif
}

// ---------------------------------------------------------------------------

// Calibrate the measuring instrument before measuring the codec with it: if
// this fails, a later pitch failure is the estimator's fault, not glint's.
void test_pitch_estimator_selftest() {
    std::printf("Pitch estimator self-test (on undecoded tones)\n");
    const int sr = 48000;
    const double freqs[] = {110.0, 440.0, 880.0, 1318.5};
    for (double want : freqs) {
        std::vector<float> pcm = tone({want}, sr, 1.0);
        double got = estimate_pitch(pcm.data(), static_cast<int>(pcm.size()), 1,
                                    0, sr);
        checkf(std::fabs(got - want) < 1.0, "estimator reads a pure tone", got,
               want);
    }
    // Stereo interleaving: channel 1 must be read, not channel 0.
    std::vector<float> st = tone({220.0, 660.0}, sr, 1.0);
    double c1 = estimate_pitch(st.data(), static_cast<int>(st.size() / 2), 2, 1,
                               sr);
    checkf(std::fabs(c1 - 660.0) < 1.0, "estimator indexes the right channel",
           c1, 660.0);
}

void test_opus_roundtrip() {
    std::printf("Opus round-trip (440 Hz mono, 44.1 kHz in)\n");
    const int sr = 44100;
    std::vector<float> pcm = tone({440.0}, sr, 2.0);
    int frames = static_cast<int>(pcm.size());

    int n = 0;
    uint8_t* enc = glint_encode_audio(pcm.data(), frames, 1, sr,
                                      GLINT_ENC_OPUS, 96, -1, 5, &n);
    check(enc != nullptr && n > 0, "encoder returned a stream");
    if (!enc) return;
    check(n >= 4 && !std::memcmp(enc, "OggS", 4), "Ogg container magic");

    int dsr = 0, dch = 0, dframes = 0;
    float* dec = cometbeat_opus_file_decode(enc, n, &dsr, &dch, &dframes);
    glint_free(enc);
    check(dec != nullptr, "decoded back");
    if (!dec) return;

    check(dch == 1, "channel count survived");
    checkf(dsr == 48000, "Opus decodes at 48 kHz", dsr, 48000);
    // Duration is asserted loosely: the codec has its own delay and the
    // encoder pads the last frame.
    double secs = dframes / 48000.0;
    checkf(secs > 1.8 && secs < 2.3, "duration ~2 s", secs, 2.0);

    double f = estimate_pitch(dec, dframes, dch, 0, dsr);
    checkf(std::fabs(f - 440.0) < 3.0, "pitch is A4", f, 440.0);
    glint_free(dec);
}

void test_opus_stereo_panning() {
    std::printf("Opus stereo (L=440 Hz, R=880 Hz — must not collapse/swap)\n");
    const int sr = 48000;
    std::vector<float> pcm = tone({440.0, 880.0}, sr, 2.0);
    int frames = static_cast<int>(pcm.size() / 2);

    int n = 0;
    uint8_t* enc = glint_encode_audio(pcm.data(), frames, 2, sr,
                                      GLINT_ENC_OPUS, 128, -1, 5, &n);
    check(enc != nullptr && n > 0, "encoder returned a stream");
    if (!enc) return;

    int dsr = 0, dch = 0, dframes = 0;
    float* dec = cometbeat_opus_file_decode(enc, n, &dsr, &dch, &dframes);
    glint_free(enc);
    check(dec != nullptr, "decoded back");
    if (!dec) return;
    check(dch == 2, "stayed stereo");
    if (dch == 2) {
        double l = estimate_pitch(dec, dframes, 2, 0, dsr);
        double r = estimate_pitch(dec, dframes, 2, 1, dsr);
        checkf(std::fabs(l - 440.0) < 4.0, "left is 440 Hz", l, 440.0);
        checkf(std::fabs(r - 880.0) < 6.0, "right is 880 Hz", r, 880.0);
    }
    glint_free(dec);
}

void test_opus_hard_pan() {
    std::printf("Opus hard pan (L tone, R silent — must not bleed)\n");
    const int sr = 48000;
    std::vector<float> pcm = tone({440.0, 440.0}, sr, 1.5);
    for (size_t i = 1; i < pcm.size(); i += 2) pcm[i] = 0.0f;  // mute right
    int frames = static_cast<int>(pcm.size() / 2);

    int n = 0;
    uint8_t* enc = glint_encode_audio(pcm.data(), frames, 2, sr,
                                      GLINT_ENC_OPUS, 128, -1, 5, &n);
    check(enc != nullptr, "encoded");
    if (!enc) return;

    int dsr = 0, dch = 0, dframes = 0;
    float* dec = cometbeat_opus_file_decode(enc, n, &dsr, &dch, &dframes);
    glint_free(enc);
    check(dec != nullptr && dch == 2, "decoded stereo");
    if (!dec) return;
    if (dch == 2) {
        double l = rms(dec, dframes, 2, 0);
        double r = rms(dec, dframes, 2, 1);
        checkf(l > 0.2, "left carries the tone", l, 0.35);
        // A lossy codec leaks a little; require the channels stay far apart.
        checkf(r < l * 0.1, "right stayed quiet", r / (l > 0 ? l : 1), 0.0);
    }
    glint_free(dec);
}

void test_mp3_and_aac_structure() {
    std::printf("MP3 / AAC streams are structurally valid\n");
    const int sr = 44100;
    std::vector<float> pcm = tone({440.0, 440.0}, sr, 1.0);
    int frames = static_cast<int>(pcm.size() / 2);

    int n = 0;
    uint8_t* mp3 = glint_encode_audio(pcm.data(), frames, 2, sr,
                                      GLINT_ENC_MP3, 128, -1, 5, &n);
    check(mp3 != nullptr && n > 1000, "MP3 stream produced");
    if (mp3) {
        // MPEG audio syncword 0xFFE with layer bits != 00 (not ADTS).
        bool sync = n >= 2 && mp3[0] == 0xFF && (mp3[1] & 0xE0) == 0xE0 &&
                    (mp3[1] & 0xF6) != 0xF0;
        check(sync, "MPEG frame sync at offset 0");
        // ~128 kbps for 1 s: expect roughly 16 kB, allow wide slack.
        check(n > 8000 && n < 40000, "MP3 size plausible for 128 kbps/1 s");
        glint_free(mp3);
    }

    n = 0;
    uint8_t* aac = glint_encode_audio(pcm.data(), frames, 2, sr,
                                      GLINT_ENC_AAC, 128, -1, 5, &n);
    check(aac != nullptr && n > 1000, "AAC stream produced");
    if (aac) {
        // ADTS: 12-bit sync + layer bits 00.
        bool sync = n >= 2 && aac[0] == 0xFF && (aac[1] & 0xF6) == 0xF0;
        check(sync, "ADTS frame sync at offset 0");
        check(n > 8000 && n < 40000, "AAC size plausible for 128 kbps/1 s");
        glint_free(aac);
    }
}

void test_rejects_bad_input() {
    std::printf("Bad input is rejected, not crashed on\n");
    std::vector<float> pcm = tone({440.0}, 44100, 0.2);
    int frames = static_cast<int>(pcm.size());
    int n = 123;
    check(glint_encode_audio(nullptr, frames, 1, 44100, GLINT_ENC_OPUS, 96, -1,
                             5, &n) == nullptr,
          "null PCM rejected");
    check(glint_encode_audio(pcm.data(), 0, 1, 44100, GLINT_ENC_OPUS, 96, -1, 5,
                             &n) == nullptr,
          "zero frames rejected");
    check(glint_encode_audio(pcm.data(), frames, 0, 44100, GLINT_ENC_OPUS, 96,
                             -1, 5, &n) == nullptr,
          "zero channels rejected");
    check(glint_encode_audio(pcm.data(), frames, 3, 44100, GLINT_ENC_OPUS, 96,
                             -1, 5, &n) == nullptr,
          "3 channels rejected (glint encodes mono/stereo)");
    check(glint_encode_audio(pcm.data(), frames, 1, 44100, /*format=*/99, 96,
                             -1, 5, &n) == nullptr,
          "unknown format rejected");
    // Decoder glue must reject non-Opus bytes rather than wander off.
    int a = 0, b = 0, c = 0;
    const uint8_t junk[64] = {0};
    check(cometbeat_opus_file_decode(junk, sizeof(junk), &a, &b, &c) == nullptr,
          "decoder rejects junk");
    check(cometbeat_opus_file_decode(nullptr, 10, &a, &b, &c) == nullptr,
          "decoder rejects null");
}

// The point of this one: a mismatched glint_free (or a leak in the encoder's
// own buffers) shows up as RSS that keeps climbing instead of plateauing.
void test_no_leak_under_repetition() {
    const int kIters = 250;
    std::printf("Encode/free x%d — RSS must plateau\n", kIters);
    const int sr = 48000;
    std::vector<float> pcm = tone({440.0, 660.0}, sr, 0.25);
    int frames = static_cast<int>(pcm.size() / 2);

    long before = 0;
    bool ok = true;
    for (int i = 0; i < kIters; i++) {
        int n = 0;
        uint8_t* p = glint_encode_audio(pcm.data(), frames, 2, sr,
                                        GLINT_ENC_OPUS, 96, -1, 5, &n);
        if (!p || n <= 0) {
            ok = false;
            break;
        }
        glint_free(p);
        if (i == kIters / 5) before = peak_rss_kb();  // after warm-up
    }
    check(ok, "every iteration encoded");
    long after = peak_rss_kb();
    long growth = after - before;
    std::printf("  peak RSS %ld KB -> %ld KB (growth %ld KB)\n", before, after,
                growth);
    // Peak RSS never shrinks, so any real per-call leak over 200 iterations of
    // ~3 kB streams plus internal buffers would blow well past this.
    check(growth < 16 * 1024, "no runaway growth over 200 encodes");
}

}  // namespace

int main() {
    std::printf("glint encode seam — native round-trip tests\n\n");
    test_pitch_estimator_selftest();
    test_opus_roundtrip();
    test_opus_stereo_panning();
    test_opus_hard_pan();
    test_mp3_and_aac_structure();
    test_rejects_bad_input();
    test_no_leak_under_repetition();
    std::printf("\n%s (%d failure%s)\n", g_failures == 0 ? "ALL PASS" : "FAILED",
                g_failures, g_failures == 1 ? "" : "s");
    return g_failures == 0 ? 0 : 1;
}
