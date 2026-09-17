#include "luat_hzmp4.h"

#ifdef __LUATOS__
#include "luat_fs.h"
#include "luat_malloc.h"
#define HZ_FOPEN  luat_fs_fopen
#define HZ_FCLOSE luat_fs_fclose
#define HZ_FREAD  luat_fs_fread
#define HZ_FSEEK  luat_fs_fseek
#define HZ_FTELL  luat_fs_ftell
#define HZ_MALLOC luat_heap_malloc
#define HZ_FREE   luat_heap_free
#else
#include <stdio.h>
#include <stdlib.h>
#define HZ_FOPEN  fopen
#define HZ_FCLOSE fclose
#define HZ_FREAD  fread
#define HZ_FSEEK  fseek
#define HZ_FTELL  ftell
#define HZ_MALLOC malloc
#define HZ_FREE   free
#endif

#include <limits.h>
#include <string.h>

#define HZMP4_HEADER_SIZE        128u
#define HZMP4_PACKET_HEADER_SIZE 32u
#define HZMP4_MAX_PACKET_SIZE    (8u * 1024u * 1024u)

struct luat_hzmp4_reader {
    void *fp;
    luat_hzmp4_info_t info;
    uint64_t file_size;
    uint64_t packet_data_offset;
    uint64_t packet_end_offset;
    uint64_t next_packet_offset;
    uint32_t packets_seen;
    uint8_t *payload;
    size_t payload_capacity;
};

static uint16_t hz_le16(const uint8_t *p)
{
    return (uint16_t)((uint16_t)p[0] | ((uint16_t)p[1] << 8));
}

static uint32_t hz_le32(const uint8_t *p)
{
    return (uint32_t)p[0] |
           ((uint32_t)p[1] << 8) |
           ((uint32_t)p[2] << 16) |
           ((uint32_t)p[3] << 24);
}

static uint64_t hz_le64(const uint8_t *p)
{
    return (uint64_t)hz_le32(p) | ((uint64_t)hz_le32(p + 4) << 32);
}

static uint32_t hz_crc32(const uint8_t *data, size_t size)
{
    uint32_t crc = 0xffffffffu;
    size_t i;
    for (i = 0; i < size; i++) {
        uint32_t value = (crc ^ data[i]) & 0xffu;
        unsigned bit;
        for (bit = 0; bit < 8; bit++) {
            value = (value >> 1) ^ (0xedb88320u & (uint32_t)-(int32_t)(value & 1u));
        }
        crc = (crc >> 8) ^ value;
    }
    return crc ^ 0xffffffffu;
}

static int hz_seek(luat_hzmp4_reader_t *reader, uint64_t offset)
{
    if (reader == NULL || reader->fp == NULL || offset > (uint64_t)LONG_MAX) {
        return LUAT_HZMP4_ERR_IO;
    }
    return HZ_FSEEK(reader->fp, (long)offset, SEEK_SET) == 0 ? LUAT_HZMP4_OK : LUAT_HZMP4_ERR_IO;
}

static int hz_read_exact(void *fp, void *buf, size_t size)
{
    return HZ_FREAD(buf, 1, size, fp) == size ? LUAT_HZMP4_OK : LUAT_HZMP4_ERR_IO;
}

static int hz_ensure_payload(luat_hzmp4_reader_t *reader, size_t size)
{
    size_t capacity;
    uint8_t *payload;

    if (size <= reader->payload_capacity) {
        return LUAT_HZMP4_OK;
    }
    if (size == 0 || size > HZMP4_MAX_PACKET_SIZE) {
        return LUAT_HZMP4_ERR_FORMAT;
    }
    capacity = reader->payload_capacity ? reader->payload_capacity : 4096u;
    while (capacity < size) {
        if (capacity > HZMP4_MAX_PACKET_SIZE / 2u) {
            capacity = HZMP4_MAX_PACKET_SIZE;
            break;
        }
        capacity *= 2u;
    }
    payload = (uint8_t *)HZ_MALLOC(capacity);
    if (payload == NULL) {
        return LUAT_HZMP4_ERR_NOMEM;
    }
    if (reader->payload != NULL) {
        HZ_FREE(reader->payload);
    }
    reader->payload = payload;
    reader->payload_capacity = capacity;
    return LUAT_HZMP4_OK;
}

static int hz_read_video_internal(luat_hzmp4_reader_t *reader,
                                  luat_hzmp4_packet_t *packet,
                                  int load_payload)
{
    uint8_t header[HZMP4_PACKET_HEADER_SIZE];

    if (reader == NULL || (load_payload && packet == NULL)) {
        return LUAT_HZMP4_ERR_PARAM;
    }

    while (reader->next_packet_offset < reader->packet_end_offset &&
           reader->packets_seen < reader->info.packet_count) {
        uint64_t packet_offset = reader->next_packet_offset;
        uint64_t next_offset;
        uint64_t pts;
        uint32_t duration;
        uint32_t payload_size;
        uint32_t payload_crc;
        uint32_t sequence;
        uint8_t stream_id;
        uint8_t flags;
        int ret;

        if (packet_offset + HZMP4_PACKET_HEADER_SIZE > reader->packet_end_offset) {
            return LUAT_HZMP4_ERR_FORMAT;
        }
        ret = hz_seek(reader, packet_offset);
        if (ret != LUAT_HZMP4_OK || hz_read_exact(reader->fp, header, sizeof(header)) != LUAT_HZMP4_OK) {
            return LUAT_HZMP4_ERR_IO;
        }
        if (memcmp(header, "HZPK", 4) != 0 || hz_le16(header + 4) != HZMP4_PACKET_HEADER_SIZE) {
            return LUAT_HZMP4_ERR_FORMAT;
        }

        stream_id = header[6];
        flags = header[7];
        pts = hz_le64(header + 8);
        duration = hz_le32(header + 16);
        payload_size = hz_le32(header + 20);
        payload_crc = hz_le32(header + 24);
        sequence = hz_le32(header + 28);
        next_offset = packet_offset + HZMP4_PACKET_HEADER_SIZE +
                      (((uint64_t)payload_size + 3u) & ~(uint64_t)3u);
        if (payload_size == 0 || payload_size > HZMP4_MAX_PACKET_SIZE ||
            next_offset > reader->packet_end_offset || next_offset <= packet_offset) {
            return LUAT_HZMP4_ERR_FORMAT;
        }

        reader->next_packet_offset = next_offset;
        reader->packets_seen++;
        if (stream_id != LUAT_HZMP4_STREAM_VIDEO) {
            continue;
        }

        if (!load_payload) {
            return LUAT_HZMP4_OK;
        }
        ret = hz_ensure_payload(reader, payload_size);
        if (ret != LUAT_HZMP4_OK) {
            return ret;
        }
        if (hz_read_exact(reader->fp, reader->payload, payload_size) != LUAT_HZMP4_OK) {
            return LUAT_HZMP4_ERR_IO;
        }
        if ((reader->info.flags & LUAT_HZMP4_FLAG_PACKET_CRC32) != 0u &&
            hz_crc32(reader->payload, payload_size) != payload_crc) {
            return LUAT_HZMP4_ERR_CRC;
        }
        if (payload_size < 4u || reader->payload[0] != 0xffu || reader->payload[1] != 0xd8u ||
            reader->payload[payload_size - 2u] != 0xffu || reader->payload[payload_size - 1u] != 0xd9u) {
            return LUAT_HZMP4_ERR_FORMAT;
        }

        packet->stream_id = stream_id;
        packet->flags = flags;
        packet->pts = pts;
        packet->duration = duration;
        packet->sequence = sequence;
        packet->data = reader->payload;
        packet->size = payload_size;
        return LUAT_HZMP4_OK;
    }
    return LUAT_HZMP4_EOF;
}

luat_hzmp4_reader_t *luat_hzmp4_open(const char *path)
{
    uint8_t header[HZMP4_HEADER_SIZE];
    uint8_t crc_header[HZMP4_HEADER_SIZE];
    uint32_t header_crc;
    uint32_t header_size;
    uint64_t index_offset;
    uint64_t index_size;
    long file_size;
    luat_hzmp4_reader_t *reader;
    void *fp;

    if (path == NULL) {
        return NULL;
    }
    fp = HZ_FOPEN(path, "rb");
    if (fp == NULL) {
        return NULL;
    }
    if (HZ_FSEEK(fp, 0, SEEK_END) != 0 || (file_size = HZ_FTELL(fp)) < (long)HZMP4_HEADER_SIZE ||
        HZ_FSEEK(fp, 0, SEEK_SET) != 0 || hz_read_exact(fp, header, sizeof(header)) != LUAT_HZMP4_OK) {
        HZ_FCLOSE(fp);
        return NULL;
    }
    if (memcmp(header, "HZM4", 4) != 0 || hz_le16(header + 4) != 1u) {
        HZ_FCLOSE(fp);
        return NULL;
    }
    header_size = hz_le32(header + 8);
    if (header_size != HZMP4_HEADER_SIZE || hz_le32(header + 16) == 0u) {
        HZ_FCLOSE(fp);
        return NULL;
    }
    header_crc = hz_le32(header + 108);
    memcpy(crc_header, header, sizeof(header));
    memset(crc_header + 108, 0, 4);
    if (hz_crc32(crc_header, sizeof(crc_header)) != header_crc) {
        HZ_FCLOSE(fp);
        return NULL;
    }

    reader = (luat_hzmp4_reader_t *)HZ_MALLOC(sizeof(luat_hzmp4_reader_t));
    if (reader == NULL) {
        HZ_FCLOSE(fp);
        return NULL;
    }
    memset(reader, 0, sizeof(*reader));
    reader->fp = fp;
    reader->file_size = (uint64_t)file_size;
    reader->packet_data_offset = hz_le64(header + 32);
    index_offset = hz_le64(header + 40);
    index_size = hz_le64(header + 48);
    reader->packet_end_offset = index_offset ? index_offset : reader->file_size;
    reader->next_packet_offset = reader->packet_data_offset;

    reader->info.version_major = hz_le16(header + 4);
    reader->info.version_minor = hz_le16(header + 6);
    reader->info.flags = hz_le32(header + 12);
    reader->info.timescale = hz_le32(header + 16);
    reader->info.stream_count = hz_le32(header + 20);
    reader->info.duration = hz_le64(header + 24);
    reader->info.packet_count = hz_le32(header + 56);
    reader->info.video_frame_count = hz_le32(header + 60);
    reader->info.video_codec = hz_le32(header + 64);
    reader->info.video_width = hz_le16(header + 68);
    reader->info.video_height = hz_le16(header + 70);
    reader->info.video_fps_num = hz_le32(header + 72);
    reader->info.video_fps_den = hz_le32(header + 76);
    reader->info.video_output_format = hz_le32(header + 80);
    reader->info.audio_codec = hz_le32(header + 84);
    reader->info.audio_sample_rate = hz_le32(header + 88);
    reader->info.audio_channels = hz_le16(header + 92);
    reader->info.audio_bits = hz_le16(header + 94);
    reader->info.audio_frame_samples = hz_le32(header + 96);
    reader->info.max_video_packet = hz_le32(header + 100);
    reader->info.max_audio_packet = hz_le32(header + 104);

    if (reader->packet_data_offset < HZMP4_HEADER_SIZE ||
        reader->packet_data_offset >= reader->packet_end_offset ||
        reader->packet_end_offset > reader->file_size ||
        (index_offset != 0u && (index_offset + index_size > reader->file_size || index_offset + index_size < index_offset)) ||
        reader->info.packet_count == 0u || reader->info.video_frame_count == 0u ||
        reader->info.video_codec != LUAT_HZMP4_VIDEO_MJPEG ||
        reader->info.video_width == 0u || reader->info.video_height == 0u) {
        luat_hzmp4_close(reader);
        return NULL;
    }
    return reader;
}

void luat_hzmp4_close(luat_hzmp4_reader_t *reader)
{
    if (reader == NULL) {
        return;
    }
    if (reader->fp != NULL) {
        HZ_FCLOSE(reader->fp);
    }
    if (reader->payload != NULL) {
        HZ_FREE(reader->payload);
    }
    HZ_FREE(reader);
}

const luat_hzmp4_info_t *luat_hzmp4_get_info(const luat_hzmp4_reader_t *reader)
{
    return reader ? &reader->info : NULL;
}

int luat_hzmp4_read_video(luat_hzmp4_reader_t *reader, luat_hzmp4_packet_t *packet)
{
    if (packet != NULL) {
        memset(packet, 0, sizeof(*packet));
    }
    return hz_read_video_internal(reader, packet, 1);
}

int luat_hzmp4_skip_video(luat_hzmp4_reader_t *reader)
{
    return hz_read_video_internal(reader, NULL, 0);
}

int luat_hzmp4_rewind(luat_hzmp4_reader_t *reader)
{
    if (reader == NULL) {
        return LUAT_HZMP4_ERR_PARAM;
    }
    reader->next_packet_offset = reader->packet_data_offset;
    reader->packets_seen = 0;
    return hz_seek(reader, reader->packet_data_offset);
}
