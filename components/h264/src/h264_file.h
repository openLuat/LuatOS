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

/* File I/O abstraction macros */
#ifdef __LUATOS__
#include "luat_fs.h"
#define H264_FOPEN   luat_fs_fopen
#define H264_FCLOSE  luat_fs_fclose
#define H264_FREAD   luat_fs_fread
#define H264_FSEEK   luat_fs_fseek
#define H264_FTELL   luat_fs_ftell
#define H264_FEOF    luat_fs_feof
#define H264_FERROR  luat_fs_ferror
#define H264_FGETC   luat_fs_getc
#else
#define H264_FOPEN   fopen
#define H264_FCLOSE  fclose
#define H264_FREAD   fread
#define H264_FSEEK   fseek
#define H264_FTELL   ftell
#define H264_FEOF    feof
#define H264_FERROR  ferror
#define H264_FGETC   fgetc
#endif

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

    /* Frame counter (used by debug logging) */
    int          frame_count;

    /* Virtual dispatch */
    int  (*read_next)(struct H264FileDecoder *self, H264Frame *frame);
    void (*cleanup)(struct H264FileDecoder *self);
};

/**
 * Global debug level (0 = off, 1 = on).
 * Set via h264.debug() from Lua or by writing directly in C.
 * Defined in h264_file.c.
 */
extern int g_h264_debug;

/**
 * Allocate and zero-initialise an H264FileDecoder together with its inner
 * H264Decoder.  Used by h264_mp4.c.  Returns NULL on allocation failure.
 */
H264FileDecoder *h264_file_decoder_alloc(void);

#endif /* H264_FILE_H */
