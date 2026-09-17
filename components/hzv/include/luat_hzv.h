#ifndef LUAT_HZV_H
#define LUAT_HZV_H

#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

#define LUAT_HZV_OK             0
#define LUAT_HZV_EOF            1
#define LUAT_HZV_ERR_PARAM     (-1)
#define LUAT_HZV_ERR_IO        (-2)
#define LUAT_HZV_ERR_FORMAT    (-3)
#define LUAT_HZV_ERR_VERSION   (-4)
#define LUAT_HZV_ERR_CRC       (-5)
#define LUAT_HZV_ERR_NOMEM     (-6)
#define LUAT_HZV_ERR_CODEC     (-7)

#define LUAT_HZV_FLAG_HAS_VIDEO          (1u << 0)
#define LUAT_HZV_FLAG_HAS_AUDIO          (1u << 1)
#define LUAT_HZV_FLAG_HAS_INDEX          (1u << 2)
#define LUAT_HZV_FLAG_PACKET_CRC32       (1u << 3)
#define LUAT_HZV_FLAG_FIXED_VIDEO_FPS    (1u << 4)
#define LUAT_HZV_FLAG_AUDIO_MASTER_CLOCK (1u << 5)
#define LUAT_HZV_FLAG_LOOP_HINT          (1u << 6)

#define LUAT_HZV_STREAM_VIDEO 0u
#define LUAT_HZV_STREAM_AUDIO 1u

#define LUAT_HZV_VIDEO_NONE   0u
#define LUAT_HZV_VIDEO_MJPEG  1u
#define LUAT_HZV_AUDIO_NONE   0u
#define LUAT_HZV_AUDIO_MP3    1u
#define LUAT_HZV_AUDIO_PCM_S16LE 2u

typedef struct {
    uint16_t version_major;
    uint16_t version_minor;
    uint32_t flags;
    uint32_t timescale;
    uint32_t stream_count;
    uint64_t duration;
    uint32_t packet_count;
    uint32_t video_frame_count;
    uint32_t video_codec;
    uint16_t video_width;
    uint16_t video_height;
    uint32_t video_fps_num;
    uint32_t video_fps_den;
    uint32_t video_output_format;
    uint32_t audio_codec;
    uint32_t audio_sample_rate;
    uint16_t audio_channels;
    uint16_t audio_bits;
    uint32_t audio_frame_samples;
    uint32_t max_video_packet;
    uint32_t max_audio_packet;
} luat_hzv_info_t;

typedef struct {
    uint8_t stream_id;
    uint8_t flags;
    uint64_t pts;
    uint32_t duration;
    uint32_t sequence;
    const uint8_t *data;
    size_t size;
} luat_hzv_packet_t;

typedef struct luat_hzv_reader luat_hzv_reader_t;

/** Open and validate an HZV v1 file. */
luat_hzv_reader_t *luat_hzv_open(const char *path);

/** Close a reader. Packet data borrowed from it becomes invalid. */
void luat_hzv_close(luat_hzv_reader_t *reader);

/** Return immutable stream metadata parsed from the fixed header. */
const luat_hzv_info_t *luat_hzv_get_info(const luat_hzv_reader_t *reader);

/**
 * Read the next video packet while transparently skipping interleaved audio.
 * packet->data is owned by the reader and remains valid until the next read,
 * rewind or close operation.
 */
int luat_hzv_read_video(luat_hzv_reader_t *reader, luat_hzv_packet_t *packet);

/** Skip one video packet without loading or decoding its JPEG payload. */
int luat_hzv_skip_video(luat_hzv_reader_t *reader);

/** Peek timing of the next video packet without consuming it. */
int luat_hzv_peek_video(luat_hzv_reader_t *reader, uint64_t *pts, uint32_t *duration);

/** Rewind packet iteration to the first media packet. */
int luat_hzv_rewind(luat_hzv_reader_t *reader);

/** Extract the complete interleaved audio track into one contiguous buffer. */
int luat_hzv_extract_audio(luat_hzv_reader_t *reader, uint8_t **data, size_t *size);

/** Free a buffer returned by luat_hzv_extract_audio(). */
void luat_hzv_free_buffer(void *data);

#ifdef __cplusplus
}
#endif

#endif
