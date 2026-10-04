#include "luat_base.h"
#ifdef LUAT_USE_VOIP_PLAY
#include "luat_voip_play.h"
#include "luat_rtos.h"
#include "luat_audio_define.h"
#include "luat_audio_data_codec.h"
#include "luat_fs.h"
#include "luat_malloc.h"
#include "speex/speex_resampler.h"
#include <limits.h>
#include <string.h>

#define PLAY_FRAME 160
#define PLAY_DEPTH 6
#define PLAY_PREBUFFER 3
#define PLAY_INPUT_BYTES 4096

typedef struct {
    int16_t pcm[PLAY_DEPTH][PLAY_FRAME];
    uint16_t valid[PLAY_DEPTH];
    uint8_t read, count, pending;
} play_queue_t;
typedef struct {
    luat_voip_play_status_t status;
    luat_voip_play_options_t options;
    play_queue_t queue[2];
    char *input;
    size_t input_len;
    luat_voip_play_cc_media_t cc_media;
    uint8_t is_tts, eof, admitted, failed;
} play_job_t;
typedef struct {
    SpeexResamplerState *resampler;
    uint32_t rate;
    uint64_t input_samples, output_samples;
    int16_t frame[PLAY_FRAME];
    uint16_t used;
    uint8_t channels;
} play_converter_t;

static play_job_t s_play;
static luat_rtos_task_handle s_task;
static luat_rtos_semaphore_t s_wake;
static uint32_t s_next_id;
static uint8_t s_initializing;
static void (*s_notify)(const char *, const luat_voip_play_status_t *);

#ifndef LUAT_USE_CC_PCM_BRIDGE
int luat_voip_play_cc_snapshot(luat_voip_play_cc_media_t *media)
{
    if (media) memset(media, 0, sizeof(*media));
    return LUAT_VOIP_PLAY_E_CC_NOT_READY;
}
#endif

const char *luat_voip_play_error(int error)
{
    switch (error) {
    case LUAT_VOIP_PLAY_OK: return "ok";
    case LUAT_VOIP_PLAY_E_INVALID: return "invalid_argument";
    case LUAT_VOIP_PLAY_E_BUSY: return "busy";
    case LUAT_VOIP_PLAY_E_NOT_RUNNING: return "not_running";
    case LUAT_VOIP_PLAY_E_UNSUPPORTED: return "unsupported";
    case LUAT_VOIP_PLAY_E_CC_NOT_READY: return "cc_not_ready";
    case LUAT_VOIP_PLAY_E_NO_MEMORY: return "no_memory";
    case LUAT_VOIP_PLAY_E_OPEN: return "open_failed";
    case LUAT_VOIP_PLAY_E_NOT_FOUND: return "not_found";
    default: return "decode_failed";
    }
}
static void play_reason(char out[32], const char *reason)
{
    size_t n = strlen(reason);
    if (n > 31) n = 31;
    memcpy(out, reason, n);
    out[n] = 0;
}
void luat_voip_play_get_status(luat_voip_play_status_t *status)
{
    uint32_t key;
    if (!status) return;
    key = luat_rtos_entry_critical();
    *status = s_play.status;
    luat_rtos_exit_critical(key);
}
static void play_notify(const char *event)
{
    luat_voip_play_status_t snapshot;
    void (*notify)(const char *, const luat_voip_play_status_t *);
    uint32_t key = luat_rtos_entry_critical();
    snapshot = s_play.status;
    notify = s_notify;
    luat_rtos_exit_critical(key);
    if (notify && (strcmp(event, "started") || snapshot.state == LUAT_VOIP_PLAY_PLAYING))
        notify(event, &snapshot);
}
/* expected_id prevents a delayed identity check from cancelling a newer job. */
static void play_request_end(uint8_t target, uint32_t expected_id,
                             const char *reason, uint8_t failed)
{
    uint8_t changed = 0;
    uint32_t key = luat_rtos_entry_critical();
    if (s_play.status.state != LUAT_VOIP_PLAY_IDLE &&
        s_play.status.state != LUAT_VOIP_PLAY_STOPPING &&
        (!expected_id || s_play.status.id == expected_id) &&
        (s_play.status.target & target)) {
        s_play.status.state = LUAT_VOIP_PLAY_STOPPING;
        s_play.failed = failed;
        play_reason(s_play.status.reason, reason ? reason : (failed ? "play_failed" : "stopped"));
        changed = 1;
    }
    luat_rtos_exit_critical(key);
    if (changed) {
        if (s_wake) luat_rtos_semaphore_release(s_wake);
        voip_play_wakeup();
    }
}
void luat_voip_play_cancel_target(uint8_t target, const char *reason)
{
    play_request_end(target, 0, reason, 0);
}
void luat_voip_play_fail_target(uint8_t target, const char *reason)
{
    play_request_end(target, 0, reason, 1);
}
void luat_voip_play_cancel(const char *reason)
{
    luat_voip_play_cancel_target(LUAT_VOIP_PLAY_TARGET_BOTH, reason);
}
int luat_voip_play_stop(uint32_t id)
{
    int result = 0;
    uint32_t key = luat_rtos_entry_critical();
    if (!id || s_play.status.id != id || s_play.status.state == LUAT_VOIP_PLAY_IDLE)
        result = LUAT_VOIP_PLAY_E_NOT_FOUND;
    else if (s_play.status.state != LUAT_VOIP_PLAY_STOPPING) {
        s_play.status.state = LUAT_VOIP_PLAY_STOPPING;
        s_play.failed = 0;
        play_reason(s_play.status.reason, "stopped");
    }
    luat_rtos_exit_critical(key);
    if (!result) {
        luat_rtos_semaphore_release(s_wake);
        voip_play_wakeup();
    }
    return result;
}
static int play_same_cc(const luat_voip_play_cc_media_t *a,
                        const luat_voip_play_cc_media_t *b)
{
    return a->session == b->session &&
        a->phase == b->phase && a->epoch == b->epoch;
}
static int play_alive(void)
{
    luat_voip_play_status_t status;
    luat_voip_play_cc_media_t bound, current;
    uint32_t session = 0, key = luat_rtos_entry_critical();
    status = s_play.status;
    bound = s_play.cc_media;
    luat_rtos_exit_critical(key);
    if (status.state == LUAT_VOIP_PLAY_STOPPING || status.state == LUAT_VOIP_PLAY_IDLE) return 0;
    /* Media snapshots may lock the transport: always take them without the
     * play lock, matching the transport -> play order used by CC rendering. */
    if (voip_play_media_snapshot(&session) || session != status.session) {
        play_request_end(LUAT_VOIP_PLAY_TARGET_BOTH, status.id, "media_stopped", 0);
        return 0;
    }
    if ((status.target & LUAT_VOIP_PLAY_TARGET_CC) &&
        (luat_voip_play_cc_snapshot(&current) || !play_same_cc(&bound, &current))) {
        play_request_end(LUAT_VOIP_PLAY_TARGET_CC, status.id, "cc_media_changed", 0);
        return 0;
    }
    return 1;
}
/* The ring lock contains only bounded copies and scalar state changes. */
static int play_ready_locked(void)
{
    unsigned i;
    if (s_play.status.state != LUAT_VOIP_PLAY_LOADING) return 0;
    for (i = 0; i < 2; ++i) {
        if (!(s_play.status.target & (1u << i))) continue;
        if (!s_play.queue[i].count || (!s_play.eof && s_play.queue[i].count < PLAY_PREBUFFER)) return 0;
    }
    s_play.status.state = LUAT_VOIP_PLAY_PLAYING;
    return 1;
}
static int play_enqueue(const int16_t *pcm, uint16_t valid)
{
    unsigned i;
    while (play_alive()) {
        int full = 0, ready;
        uint32_t key = luat_rtos_entry_critical();
        if (s_play.status.state == LUAT_VOIP_PLAY_STOPPING) {
            luat_rtos_exit_critical(key);
            return -1;
        }
        for (i = 0; i < 2; ++i)
            if ((s_play.status.target & (1u << i)) && s_play.queue[i].count == PLAY_DEPTH) full = 1;
        if (!full) {
            for (i = 0; i < 2; ++i) {
                play_queue_t *q = &s_play.queue[i];
                uint8_t slot;
                if (!(s_play.status.target & (1u << i))) continue;
                slot = (uint8_t)((q->read + q->count) % PLAY_DEPTH);
                memcpy(q->pcm[slot], pcm, sizeof(q->pcm[slot]));
                q->valid[slot] = valid;
                ++q->count;
            }
            ready = play_ready_locked();
            luat_rtos_exit_critical(key);
            if (ready) { play_notify("started"); voip_play_wakeup(); }
            return 0;
        }
        luat_rtos_exit_critical(key);
        luat_rtos_semaphore_take(s_wake, 100);
    }
    return -1;
}
uint32_t luat_voip_play_active(uint8_t target)
{
    uint32_t id = 0, key = luat_rtos_entry_critical();
    unsigned index = target == LUAT_VOIP_PLAY_TARGET_CC ? 1 : 0;
    if ((target == LUAT_VOIP_PLAY_TARGET_SIP || target == LUAT_VOIP_PLAY_TARGET_CC) &&
        s_play.status.state == LUAT_VOIP_PLAY_PLAYING && (s_play.status.target & target) &&
        (!s_play.eof || s_play.queue[index].count)) id = s_play.status.id;
    luat_rtos_exit_critical(key);
    return id;
}
uint32_t luat_voip_play_render(uint8_t target, int16_t *pcm, uint16_t samples,
        uint32_t rate, const luat_voip_play_cc_media_t *media)
{
    int16_t source[PLAY_FRAME];
    luat_voip_play_options_t options;
    uint32_t id, key, session = 0;
    int media_result = 0;
    unsigned i;
    play_queue_t *q;
    if (!pcm || (target != LUAT_VOIP_PLAY_TARGET_SIP && target != LUAT_VOIP_PLAY_TARGET_CC) ||
        !((rate == 8000 && samples == 160) || (rate == 16000 && samples == 320))) return 0;
    if (target == LUAT_VOIP_PLAY_TARGET_SIP) media_result = voip_play_media_snapshot(&session);
    key = luat_rtos_entry_critical();
    if (s_play.status.state != LUAT_VOIP_PLAY_PLAYING || !(s_play.status.target & target)) {
        luat_rtos_exit_critical(key);
        return 0;
    }
    if ((target == LUAT_VOIP_PLAY_TARGET_SIP && (media_result || session != s_play.status.session)) ||
        (target == LUAT_VOIP_PLAY_TARGET_CC && (!media || !play_same_cc(media, &s_play.cc_media)))) {
        id = s_play.status.id;
        luat_rtos_exit_critical(key);
        play_request_end(target, id, target == LUAT_VOIP_PLAY_TARGET_SIP ? "media_stopped" : "cc_media_changed", 0);
        return 0;
    }
    q = &s_play.queue[target == LUAT_VOIP_PLAY_TARGET_CC];
    options = s_play.options;
    if (!q->count) {
        int underrun = !s_play.eof;
        q->pending = 0;
        luat_rtos_exit_critical(key);
        if (underrun && options.mode == LUAT_VOIP_PLAY_REPLACE) memset(pcm, 0, samples * sizeof(*pcm));
        return 0;
    }
    memcpy(source, q->pcm[q->read], sizeof(source));
    q->pending = 1;
    id = s_play.status.id;
    luat_rtos_exit_critical(key);
    for (i = 0; i < samples; ++i) {
        /* Retryable conversion: no resampler state advances until commit.
         * The CC 16 kHz leg receives one interpolated 20 ms source frame. */
        unsigned pos = rate == 16000 ? i / 2 : i;
        int32_t value = source[pos], mixed;
        if (rate == 16000 && (i & 1) && pos + 1 < PLAY_FRAME) value = (value + source[pos + 1]) / 2;
        mixed = value * options.gain_q15;
        if (options.mode == LUAT_VOIP_PLAY_MIX) mixed += (int32_t)pcm[i] * options.speech_gain_q15;
        mixed /= 32768;
        if (mixed > 32767) mixed = 32767;
        if (mixed < -32768) mixed = -32768;
        pcm[i] = (int16_t)mixed;
    }
    return id;
}
void luat_voip_play_commit(uint8_t target, uint32_t id)
{
    uint8_t committed = 0;
    uint32_t key, session = 0;
    int media_result = 0;
    play_queue_t *q;
    if (target != LUAT_VOIP_PLAY_TARGET_SIP && target != LUAT_VOIP_PLAY_TARGET_CC) return;
    if (target == LUAT_VOIP_PLAY_TARGET_SIP) media_result = voip_play_media_snapshot(&session);
    key = luat_rtos_entry_critical();
    if (id && s_play.status.id == id && target == LUAT_VOIP_PLAY_TARGET_SIP &&
        (media_result || session != s_play.status.session)) {
        luat_rtos_exit_critical(key);
        play_request_end(target, id, "media_stopped", 0);
        return;
    }
    q = &s_play.queue[target == LUAT_VOIP_PLAY_TARGET_CC];
    if (id && s_play.status.id == id && s_play.status.state == LUAT_VOIP_PLAY_PLAYING &&
        (s_play.status.target & target) && q->count && q->pending) {
        s_play.status.played_samples[target == LUAT_VOIP_PLAY_TARGET_CC] += q->valid[q->read];
        q->read = (uint8_t)((q->read + 1) % PLAY_DEPTH);
        --q->count;
        q->pending = 0;
        committed = 1;
    }
    luat_rtos_exit_critical(key);
    if (committed) luat_rtos_semaphore_release(s_wake);
}
static int converter_config(play_converter_t *c, uint32_t rate, uint8_t channels)
{
    int error;
    if (rate < 8000 || rate > 48000 || (channels != 1 && channels != 2)) return LUAT_VOIP_PLAY_E_UNSUPPORTED;
    if (c->rate) return c->rate == rate && c->channels == channels ? 0 : LUAT_VOIP_PLAY_E_UNSUPPORTED;
    c->rate = rate;
    c->channels = channels;
    if (rate != 8000) {
        c->resampler = speex_resampler_init(1, rate, 8000, 4, &error);
        if (!c->resampler) return LUAT_VOIP_PLAY_E_NO_MEMORY;
        speex_resampler_skip_zeros(c->resampler);
    }
    return 0;
}
static int converter_output(play_converter_t *c, const int16_t *pcm, uint32_t count)
{
    while (count) {
        uint32_t take = PLAY_FRAME - c->used;
        if (take > count) take = count;
        memcpy(c->frame + c->used, pcm, take * sizeof(*pcm));
        c->used += (uint16_t)take;
        c->output_samples += take;
        count -= take;
        pcm += take;
        if (c->used == PLAY_FRAME) {
            if (play_enqueue(c->frame, PLAY_FRAME)) return -1;
            c->used = 0;
        }
    }
    return 0;
}
static int converter_pcm(play_converter_t *c, const uint8_t *bytes, uint32_t length)
{
    int16_t mono[256], output[256];
    uint32_t frames, done = 0, n, i;
    if (!c->rate || length % (2u * c->channels)) return LUAT_VOIP_PLAY_E_DECODE;
    frames = length / (2u * c->channels);
    c->input_samples += frames;
    while (done < frames) {
        if (!play_alive()) return -1;
        n = frames - done;
        if (n > 256) n = 256;
        for (i = 0; i < n; ++i) {
            const uint8_t *p = bytes + (done + i) * 2u * c->channels;
            int32_t sample = (int16_t)((uint16_t)p[0] | ((uint16_t)p[1] << 8));
            if (c->channels == 2) sample = (sample + (int16_t)((uint16_t)p[2] | ((uint16_t)p[3] << 8))) / 2;
            mono[i] = (int16_t)sample;
        }
        if (c->resampler) {
            uint32_t offset = 0;
            while (offset < n) {
                spx_uint32_t in_count = n - offset, out_count = 256;
                if (speex_resampler_process_int(c->resampler, 0, mono + offset, &in_count, output, &out_count) ||
                    (!in_count && !out_count)) return LUAT_VOIP_PLAY_E_DECODE;
                if (converter_output(c, output, out_count)) return -1;
                offset += in_count;
            }
        } else if (converter_output(c, mono, n)) return -1;
        done += n;
    }
    return 0;
}
static int converter_finish(play_converter_t *c)
{
    if (c->resampler) {
        int16_t zero[256] = {0}, output[256];
        uint64_t expected = c->input_samples * 8000 / c->rate;
        while (c->output_samples < expected) {
            spx_uint32_t in_count = 256, out_count = 256;
            uint64_t remaining = expected - c->output_samples;
            if (remaining < out_count) out_count = (spx_uint32_t)remaining;
            if (!play_alive()) return -1;
            if (speex_resampler_process_int(c->resampler, 0, zero, &in_count, output, &out_count) ||
                (!in_count && !out_count)) return LUAT_VOIP_PLAY_E_DECODE;
            if (converter_output(c, output, out_count)) return -1;
        }
    }
    if (c->used) {
        memset(c->frame + c->used, 0, (PLAY_FRAME - c->used) * sizeof(int16_t));
        if (play_enqueue(c->frame, c->used)) return -1;
        c->used = 0;
    }
    return c->output_samples ? 0 : LUAT_VOIP_PLAY_E_DECODE;
}
typedef struct {
    luat_audio_data_codec_t codec;
    play_converter_t *converter;
    int result;
} play_tts_t;
static int play_tts_output(void *data, uint32_t length, void *user_data)
{
    play_tts_t *tts = (play_tts_t *)user_data;
    if (!play_alive()) return -1;
    if (!data) {
        if (tts->codec.common_param.data_align != 2 || !tts->codec.common_param.is_signed)
            tts->result = LUAT_VOIP_PLAY_E_UNSUPPORTED;
        else tts->result = converter_config(tts->converter, tts->codec.common_param.sample_rate,
                                            tts->codec.common_param.channel_nums);
    } else tts->result = converter_pcm(tts->converter, data, length);
    return tts->result;
}
static int play_tts(play_converter_t *converter)
{
    const luat_audio_data_codec_opts_t *opts = luat_audio_data_codec_find(LUAT_AUDIO_DATA_CODEC_TYPE_TTS);
    play_tts_t tts;
    int result;
    if (!opts || !opts->tts_decode_sync) return LUAT_VOIP_PLAY_E_UNSUPPORTED;
    memset(&tts, 0, sizeof(tts));
    tts.converter = converter;
    if (luat_audio_data_codec_bind(&tts.codec, opts, &tts)) return LUAT_VOIP_PLAY_E_NO_MEMORY;
    result = opts->init(&tts.codec, 0);
    if (!result) {
        tts.codec.param.tts_output_callback = play_tts_output;
        result = opts->tts_decode_sync(&tts.codec, s_play.input, (uint32_t)s_play.input_len, &tts);
    }
    luat_audio_data_codec_unbind(&tts.codec);
    return tts.result ? tts.result : (result ? LUAT_VOIP_PLAY_E_DECODE : 0);
}
static uint16_t read_le16(const uint8_t *p) { return (uint16_t)((uint16_t)p[0] | ((uint16_t)p[1] << 8)); }
static uint32_t read_le32(const uint8_t *p) { return (uint32_t)p[0] | ((uint32_t)p[1] << 8) | ((uint32_t)p[2] << 16) | ((uint32_t)p[3] << 24); }
static int file_seek(FILE *file, uint32_t offset)
{
    if (offset > INT32_MAX) return -1;
    return luat_fs_fseek(file, (long)offset, SEEK_SET);
}
/* RIFF metadata is skipped in the file rather than accumulated in audio RAM. */
static int play_wav_info(FILE *file, uint32_t file_size, play_converter_t *converter, uint32_t *data_size)
{
    uint8_t header[16];
    uint32_t position = 12, riff_end;
    int have_format = 0, result;
    if (file_seek(file, 0) || luat_fs_fread(header, 1, 12, file) != 12 ||
        memcmp(header, "RIFF", 4) || memcmp(header + 8, "WAVE", 4)) return LUAT_VOIP_PLAY_E_DECODE;
    if ((uint64_t)read_le32(header + 4) + 8 > file_size) return LUAT_VOIP_PLAY_E_DECODE;
    riff_end = read_le32(header + 4) + 8;
    while ((uint64_t)position + 8 <= riff_end) {
        uint32_t length, body;
        if (!play_alive()) return -1;
        if (file_seek(file, position) || luat_fs_fread(header, 1, 8, file) != 8) return LUAT_VOIP_PLAY_E_DECODE;
        length = read_le32(header + 4);
        body = position + 8;
        if ((uint64_t)body + length > riff_end) return LUAT_VOIP_PLAY_E_DECODE;
        if (!memcmp(header, "fmt ", 4)) {
            if (length < 16 || luat_fs_fread(header, 1, 16, file) != 16) return LUAT_VOIP_PLAY_E_DECODE;
            if (read_le16(header) != 1 || read_le16(header + 14) != 16) return LUAT_VOIP_PLAY_E_UNSUPPORTED;
            if (read_le16(header + 2) > 2 || read_le16(header + 12) != 2u * read_le16(header + 2)) return LUAT_VOIP_PLAY_E_UNSUPPORTED;
            result = converter_config(converter, read_le32(header + 4), (uint8_t)read_le16(header + 2));
            if (result) return result;
            have_format = 1;
        } else if (!memcmp(header, "data", 4)) {
            if (!have_format || length % (2u * converter->channels)) return LUAT_VOIP_PLAY_E_DECODE;
            *data_size = length;
            return 0;
        }
        if ((uint64_t)body + length + (length & 1u) > riff_end) return LUAT_VOIP_PLAY_E_DECODE;
        position = body + length + (length & 1u);
    }
    return LUAT_VOIP_PLAY_E_DECODE;
}
static int play_pcm_file(FILE *file, uint32_t size, play_converter_t *converter)
{
    uint8_t input[1024];
    while (size) {
        uint32_t count = size > sizeof(input) ? sizeof(input) : size;
        int result;
        if (!play_alive()) return -1;
        if (luat_fs_fread(input, 1, count, file) != count) return LUAT_VOIP_PLAY_E_DECODE;
        result = converter_pcm(converter, input, count);
        if (result) return result;
        size -= count;
    }
    return 0;
}
static int play_mp3_file(FILE *file, uint32_t size, play_converter_t *converter)
{
    const luat_audio_data_codec_opts_t *opts = luat_audio_data_codec_find(LUAT_AUDIO_DATA_CODEC_TYPE_MP3);
    luat_audio_data_codec_t codec;
    luat_buffer_t probe;
    uint8_t *input = NULL, *output = NULL;
    uint32_t buffered = 0, remaining = size, need, jump, got, used, output_size;
    int result = LUAT_VOIP_PLAY_E_DECODE;
    if (!opts || !opts->decode || !opts->get_play_info || !opts->decode_min_input_len ||
        opts->decode_min_input_len > PLAY_INPUT_BYTES) return LUAT_VOIP_PLAY_E_UNSUPPORTED;
    memset(&codec, 0, sizeof(codec));
    memset(&probe, 0, sizeof(probe));
    input = luat_heap_malloc(PLAY_INPUT_BYTES);
    output = luat_heap_malloc(opts->decode_max_output_len);
    if (!input || !output || luat_audio_data_codec_bind(&codec, opts, NULL)) {
        result = LUAT_VOIP_PLAY_E_NO_MEMORY;
        goto done;
    }
    got = remaining > 10 ? 10 : remaining;
    if (luat_fs_fread(input, 1, got, file) != got) goto done;
    jump = 0;
    if (got == 10 && !memcmp(input, "ID3", 3)) {
        if ((input[6] | input[7] | input[8] | input[9]) & 0x80) goto done;
        jump = ((uint32_t)input[6] << 21) | ((uint32_t)input[7] << 14) | ((uint32_t)input[8] << 7) | input[9];
        jump += 10 + ((input[3] == 4 && (input[5] & 0x10)) ? 10 : 0);
        if (jump >= size) goto done;
    }
    if (file_seek(file, jump)) goto done;
    remaining = size - jump;
    got = remaining > PLAY_INPUT_BYTES ? PLAY_INPUT_BYTES : remaining;
    memset(input, 0, PLAY_INPUT_BYTES);
    if (luat_fs_fread(input, 1, got, file) != got) goto done;
    buffered = got;
    remaining -= got;
    probe.data = input;
    probe.pos = buffered < opts->decode_min_input_len ? opts->decode_min_input_len : buffered;
    probe.max_len = PLAY_INPUT_BYTES;
    jump = need = 0;
    if (opts->get_play_info(&codec, &probe, 0, &jump, &need, &codec.common_param) || need ||
        !codec.common_param.sample_rate || codec.common_param.data_align != 2 || !codec.common_param.is_signed) goto done;
    result = converter_config(converter, codec.common_param.sample_rate, codec.common_param.channel_nums);
    if (result) goto done;
    result = LUAT_VOIP_PLAY_E_DECODE;
    if (opts->init(&codec, 0)) goto done;
    while (buffered || remaining) {
        if (!play_alive()) { result = -1; goto done; }
        if (remaining && buffered < PLAY_INPUT_BYTES) {
            got = PLAY_INPUT_BYTES - buffered;
            if (got > remaining) got = remaining;
            if (luat_fs_fread(input + buffered, 1, got, file) != got) goto done;
            buffered += got;
            remaining -= got;
        }
        if (!remaining && buffered == 128 && !memcmp(input, "TAG", 3)) break;
        got = buffered > opts->decode_min_input_len ? opts->decode_min_input_len : buffered;
        used = output_size = 0;
        if (opts->decode(&codec, &codec.common_param, input, got, output, &output_size, &used) ||
            !used || used > got || output_size > opts->decode_max_output_len) goto done;
        if (output_size) {
            int converted = converter_pcm(converter, output, output_size);
            if (converted) { result = converted; goto done; }
        }
        buffered -= used;
        memmove(input, input + used, buffered);
    }
    result = 0;
done:
    if (codec.opts) luat_audio_data_codec_unbind(&codec);
    if (input) luat_heap_free(input);
    if (output) luat_heap_free(output);
    return result;
}
static int extension_is(const char *path, const char *extension)
{
    const char *dot = strrchr(path, '.');
    if (!dot) return 0;
    while (*dot && *extension) {
        char c = *dot++;
        if (c >= 'A' && c <= 'Z') c = (char)(c + ('a' - 'A'));
        if (c != *extension++) return 0;
    }
    return !*dot && !*extension;
}
static int play_file(play_converter_t *converter)
{
    FILE *file = luat_fs_fopen(s_play.input, "rb");
    int result, length;
    uint32_t size;
    if (!file) return LUAT_VOIP_PLAY_E_OPEN;
    if (luat_fs_fseek(file, 0, SEEK_END) || (length = luat_fs_ftell(file)) < 0 || file_seek(file, 0)) {
        result = LUAT_VOIP_PLAY_E_OPEN;
        goto done;
    }
    size = (uint32_t)length;
    if (extension_is(s_play.input, ".wav")) {
        result = play_wav_info(file, size, converter, &size);
        if (!result) result = play_pcm_file(file, size, converter);
    } else if (extension_is(s_play.input, ".pcm")) {
        result = converter_config(converter, s_play.options.sample_rate, s_play.options.channels);
        if (!result) result = play_pcm_file(file, size, converter);
    } else if (extension_is(s_play.input, ".mp3")) result = play_mp3_file(file, size, converter);
    else result = LUAT_VOIP_PLAY_E_UNSUPPORTED;
done:
    luat_fs_fclose(file);
    return result;
}
static void play_finish(int result)
{
    luat_voip_play_status_t snapshot;
    void (*notify)(const char *, const luat_voip_play_status_t *);
    const char *event;
    char *input;
    uint32_t key = luat_rtos_entry_critical();
    if (s_play.status.state == LUAT_VOIP_PLAY_STOPPING) event = s_play.failed ? "error" : "stopped";
    else {
        event = result ? "error" : "done";
        play_reason(s_play.status.reason, result ? luat_voip_play_error(result) : "done");
    }
    /* Keep admission busy until the worker has freed all job-owned storage.
     * Transport tokens stop being valid before the final source is released. */
    s_play.status.state = LUAT_VOIP_PLAY_STOPPING;
    snapshot = s_play.status;
    input = s_play.input;
    s_play.input = NULL;
    memset(s_play.queue, 0, sizeof(s_play.queue));
    luat_rtos_exit_critical(key);
    luat_heap_free(input);
    key = luat_rtos_entry_critical();
    snapshot.state = LUAT_VOIP_PLAY_IDLE;
    s_play.status = snapshot;
    s_play.admitted = 0;
    notify = s_notify;
    luat_rtos_exit_critical(key);
    voip_play_wakeup();
    if (notify) notify(event, &snapshot);
}
static void play_worker(void *unused)
{
    (void)unused;
    for (;;) {
        play_converter_t converter;
        uint32_t key;
        int result, ready;
        luat_rtos_semaphore_take(s_wake, LUAT_WAIT_FOREVER);
        key = luat_rtos_entry_critical();
        if (s_play.status.state == LUAT_VOIP_PLAY_IDLE || !s_play.input || !s_play.admitted) {
            luat_rtos_exit_critical(key);
            continue;
        }
        luat_rtos_exit_critical(key);
        memset(&converter, 0, sizeof(converter));
        result = play_alive() ? (s_play.is_tts ? play_tts(&converter) : play_file(&converter)) : -1;
        if (!result) result = converter_finish(&converter);
        if (converter.resampler) speex_resampler_destroy(converter.resampler);
        if (!result && play_alive()) {
            key = luat_rtos_entry_critical();
            s_play.eof = 1;
            ready = play_ready_locked();
            luat_rtos_exit_critical(key);
            if (ready) { play_notify("started"); voip_play_wakeup(); }
            while (play_alive()) {
                int pending;
                key = luat_rtos_entry_critical();
                pending = s_play.queue[0].count || s_play.queue[1].count;
                luat_rtos_exit_critical(key);
                if (!pending) break;
                luat_rtos_semaphore_take(s_wake, 100);
            }
        }
        play_finish(result);
    }
}
int luat_voip_play_init(void (*notify)(const char *, const luat_voip_play_status_t *))
{
    int result = 0;
    uint32_t key = luat_rtos_entry_critical();
    if (notify) s_notify = notify;
    if (s_task) {
        luat_rtos_exit_critical(key);
        return 0;
    }
    if (s_initializing) {
        luat_rtos_exit_critical(key);
        return LUAT_VOIP_PLAY_E_BUSY;
    }
    s_initializing = 1;
    luat_rtos_exit_critical(key);
    if (luat_rtos_semaphore_create(&s_wake, 0)) result = LUAT_VOIP_PLAY_E_NO_MEMORY;
    else if (luat_rtos_task_create(&s_task, 12 * 1024, 30, "voip_play", play_worker, NULL, 0)) {
        luat_rtos_semaphore_delete(s_wake);
        s_wake = NULL;
        result = LUAT_VOIP_PLAY_E_NO_MEMORY;
    }
    key = luat_rtos_entry_critical();
    s_initializing = 0;
    luat_rtos_exit_critical(key);
    return result;
}
static int play_start(const char *input, size_t length, uint8_t is_tts,
        const luat_voip_play_options_t *options, uint32_t *id)
{
    luat_voip_play_options_t opts = {8000, 32768, 16384, 1, LUAT_VOIP_PLAY_TARGET_SIP, LUAT_VOIP_PLAY_REPLACE};
    luat_voip_play_cc_media_t cc_media = {0};
    const luat_audio_data_codec_opts_t *tts;
    uint32_t session = 0, key, job_id;
    char *copy;
    int result;
    if (!input || !length || length >= UINT32_MAX || !id) return LUAT_VOIP_PLAY_E_INVALID;
    if (options) opts = *options;
    if (!opts.sample_rate) opts.sample_rate = 8000;
    if (!opts.channels) opts.channels = 1;
    if (opts.target < 1 || opts.target > 3 || opts.mode > LUAT_VOIP_PLAY_MIX ||
        opts.gain_q15 > 32768 || opts.speech_gain_q15 > 32768 ||
        opts.channels > 2 || opts.sample_rate < 8000 || opts.sample_rate > 48000) return LUAT_VOIP_PLAY_E_INVALID;
    key = luat_rtos_entry_critical();
    result = s_play.status.state != LUAT_VOIP_PLAY_IDLE ? LUAT_VOIP_PLAY_E_BUSY : 0;
    luat_rtos_exit_critical(key);
    if (result) return result;
    result = voip_play_media_snapshot(&session);
    if (result) return result;
    if ((opts.target & LUAT_VOIP_PLAY_TARGET_CC) && luat_voip_play_cc_snapshot(&cc_media))
        return LUAT_VOIP_PLAY_E_CC_NOT_READY;
    tts = is_tts ? luat_audio_data_codec_find(LUAT_AUDIO_DATA_CODEC_TYPE_TTS) : NULL;
    if (is_tts && (!tts || !tts->tts_decode_sync)) return LUAT_VOIP_PLAY_E_UNSUPPORTED;
    result = luat_voip_play_init(NULL);
    if (result) return result;
    copy = luat_heap_malloc(length + 1);
    if (!copy) return LUAT_VOIP_PLAY_E_NO_MEMORY;
    memcpy(copy, input, length);
    copy[length] = 0;
    key = luat_rtos_entry_critical();
    if (s_play.status.state != LUAT_VOIP_PLAY_IDLE) result = LUAT_VOIP_PLAY_E_BUSY;
    if (!result) {
        memset(&s_play, 0, sizeof(s_play));
        if (!++s_next_id) ++s_next_id;
        s_play.status.id = s_next_id;
        s_play.status.session = session;
        s_play.status.target = opts.target;
        s_play.status.mode = opts.mode;
        s_play.status.state = LUAT_VOIP_PLAY_LOADING;
        s_play.options = opts;
        s_play.cc_media = cc_media;
        s_play.input = copy;
        s_play.input_len = length;
        s_play.is_tts = is_tts;
        *id = s_next_id;
    }
    job_id = s_play.status.id;
    luat_rtos_exit_critical(key);
    if (result) {
        luat_heap_free(copy);
        return result;
    }
    /* Publish before the second snapshot so concurrent media invalidation can
     * cancel this exact job. Residual semaphore credits cannot run it early. */
    (void)play_alive();
    key = luat_rtos_entry_critical();
    if (s_play.status.id == job_id) s_play.admitted = 1;
    luat_rtos_exit_critical(key);
    luat_rtos_semaphore_release(s_wake);
    voip_play_wakeup();
    return 0;
}
int luat_voip_play_start_tts(const char *text, size_t len,
        const luat_voip_play_options_t *options, uint32_t *id)
{
    return play_start(text, len, 1, options, id);
}
int luat_voip_play_start_file(const char *path, const luat_voip_play_options_t *options, uint32_t *id)
{
    if (!path) return LUAT_VOIP_PLAY_E_INVALID;
    return play_start(path, strlen(path), 0, options, id);
}
#endif
