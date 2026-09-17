#ifndef LUAT_HZMP4_H
#define LUAT_HZMP4_H

#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

#define LUAT_HZMP4_OK             0
#define LUAT_HZMP4_EOF            1
#define LUAT_HZMP4_ERR_PARAM     (-1)
#define LUAT_HZMP4_ERR_IO        (-2)
#define LUAT_HZMP4_ERR_FORMAT    (-3)
#define LUAT_HZMP4_ERR_VERSION   (-4)
#define LUAT_HZMP4_ERR_CRC       (-5)
#define LUAT_HZMP4_ERR_NOMEM     (-6)
#define LUAT_HZMP4_ERR_CODEC     (-7)

#define LUAT_HZMP4_FLAG_HAS_VIDEO          (1u << 0)
#define LUAT_HZMP4_FLAG_HAS_AUDIO          (1u << 1)
#define LUAT_HZMP4_FLAG_HAS_INDEX          (1u << 2)
#define LUAT_HZMP4_FLAG_PACKET_CRC32       (1u << 3)
#define LUAT_HZMP4_FLAG_FIXED_VIDEO_FPS    (1u << 4)
#define LUAT_HZMP4_FLAG_AUDIO_MASTER_CLOCK (1u << 5)
#define LUAT_HZMP4_FLAG_LOOP_HINT          (1u << 6)

#define LUAT_HZMP4_STREAM_VIDEO 0u
#define LUAT_HZMP4_STREAM_AUDIO 1u

#define LUAT_HZMP4_VIDEO_NONE   0u
#define LUAT_HZMP4_VIDEO_MJPEG  1u
#define LUAT_HZMP4_AUDIO_NONE   0u
#define LUAT_HZMP4_AUDIO_MP3    1u
#define LUAT_HZMP4_AUDIO_PCM_S16LE 2u

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
} luat_hzmp4_info_t;

typedef struct {
    uint8_t stream_id;
    uint8_t flags;
    uint64_t pts;
    uint32_t duration;
    uint32_t sequence;
    const uint8_t *data;
    size_t size;
} luat_hzmp4_packet_t;

typedef struct luat_hzmp4_reader luat_hzmp4_reader_t;

/** Open and validate an HZMP4 v1 file. */
luat_hzmp4_reader_t *luat_hzmp4_open(const char *path);

/** Close a reader. Packet data borrowed from it becomes invalid. */
void luat_hzmp4_close(luat_hzmp4_reader_t *reader);

/** Return immutable stream metadata parsed from the fixed header. */
const luat_hzmp4_info_t *luat_hzmp4_get_info(const luat_hzmp4_reader_t *reader);

/**
 * Read the next video packet while transparently skipping interleaved audio.
 * packet->data is owned by the reader and remains valid until the next read,
 * rewind or close operation.
 */
int luat_hzmp4_read_video(luat_hzmp4_reader_t *reader, luat_hzmp4_packet_t *packet);

/** Skip one video packet without loading or decoding its JPEG payload. */
int luat_hzmp4_skip_video(luat_hzmp4_reader_t *reader);

/** Rewind packet iteration to the first media packet. */
int luat_hzmp4_rewind(luat_hzmp4_reader_t *reader);

#ifdef __cplusplus
}
#endif

#endif
