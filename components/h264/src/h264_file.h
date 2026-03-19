/*
 * h264_file.h — internal header shared by h264_file.c and h264_mp4.c.
 * Defines the H264FileDecoder struct and the allocator helper used by
 * the MP4 module to create a decoder without opening an Annex-B file.
 */
#ifndef H264_FILE_H
#define H264_FILE_H

#include <stdio.h>
#include <stdint.h>
#include "../include/h264_decoder.h"

#define H264_FILE_CHUNK_SIZE (64 * 1024)

struct H264FileDecoder {
    H264Decoder *dec;
    FILE        *fp;
    int          type;      /* 0 = annex-b, 1 = mp4 */

    /* Annex-B specific */
    uint8_t     *buf;
    int          buf_size;
    int          buf_len;
    int          buf_pos;
    int          eof;

    /* MP4 specific (set by h264_mp4.c) */
    void        *mp4_ctx;

    /* Virtual dispatch */
    int  (*read_next)(struct H264FileDecoder *self, H264Frame *frame);
    void (*cleanup)(struct H264FileDecoder *self);
};

/**
 * Allocate and zero-initialise an H264FileDecoder together with its inner
 * H264Decoder.  Used by h264_mp4.c.  Returns NULL on allocation failure.
 */
H264FileDecoder *h264_file_decoder_alloc(void);

#endif /* H264_FILE_H */
