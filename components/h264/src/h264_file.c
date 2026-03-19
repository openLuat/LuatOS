/*
 * h264_file.c — Annex-B file reader for H.264.
 *
 * Reads a .h264 / .264 file using a 64 KB ring buffer and yields one decoded
 * frame per h264_read_frame() call.  Uses the existing h264_find_next_nal()
 * and h264_decode_nal() functions from the core library.
 */

#include <string.h>
#include <stdlib.h>
#include "h264_common.h"
#include "h264_file.h"

/* Memory allocation macros */
#ifdef LUAT_HEAP_MALLOC
#include "luat_malloc.h"
#define H264_MALLOC  luat_heap_malloc
#define H264_FREE    luat_heap_free
#define H264_REALLOC luat_heap_realloc
#else
#define H264_MALLOC  malloc
#define H264_FREE    free
#define H264_REALLOC realloc
#endif

/* ---- Debug logging ---- */
int g_h264_debug = 0;

#ifdef LUAT_BUILD
#define LUAT_LOG_TAG "h264"
#include "luat_log.h"
#define H264_DBGI(fmt, ...) do { if (g_h264_debug) { LLOGI(fmt, ##__VA_ARGS__); } } while(0)
#else
#include <stdio.h>
#define H264_DBGI(fmt, ...) do { if (g_h264_debug) { printf("[h264] " fmt "\n", ##__VA_ARGS__); } } while(0)
#endif

/* Forward declaration (defined in h264_nalu.c) */
int h264_find_next_nal(const uint8_t *data, int size,
                       int *nal_start, int *nal_size);

/* ---- Shared allocator (also used by h264_mp4.c) ---- */

H264FileDecoder *h264_file_decoder_alloc(void)
{
    H264FileDecoder *fctx =
        (H264FileDecoder *)H264_MALLOC(sizeof(H264FileDecoder));
    if (!fctx) return NULL;
    memset(fctx, 0, sizeof(*fctx));

    fctx->dec = h264_decoder_create();
    if (!fctx->dec) {
        H264_FREE(fctx);
        return NULL;
    }
    return fctx;
}

/* ---- Annex-B read loop ---- */

static int annexb_read_next(H264FileDecoder *fctx, H264Frame *frame)
{
    for (;;) {
        int remaining = fctx->buf_len - fctx->buf_pos;

        if (remaining > 0) {
            int nal_start, nal_size;
            int found = h264_find_next_nal(fctx->buf + fctx->buf_pos,
                                           remaining,
                                           &nal_start, &nal_size);
            if (found) {
                /* "bounded" ⟺ h264_find_next_nal found the *next* start code,
                 * meaning this NAL is fully contained in the buffer. */
                int bounded = (nal_start + nal_size < remaining);

                if (bounded || fctx->eof) {
                    H264Frame f;
                    memset(&f, 0, sizeof(f));
                    h264_decode_nal(fctx->dec,
                                    fctx->buf + fctx->buf_pos + nal_start,
                                    nal_size, &f);
                    fctx->buf_pos += nal_start + nal_size;

                    if (f.is_valid) {
                        *frame = f;
                        fctx->frame_count++;
                        H264_DBGI("annexb frame #%d: %dx%d",
                                  fctx->frame_count, f.width, f.height);
                        return H264_OK;
                    }
                    /* SPS / PPS / SEI — non-picture NAL; keep going */
                    continue;
                }
                /* Not bounded and not at EOF — need more data */
            } else if (fctx->eof) {
                return H264_ERR_EOF;
            }
            /* No start code found or NAL not bounded: fall through to refill */
        } else if (fctx->eof) {
            return H264_ERR_EOF;
        }

        /* --- Refill the buffer --- */
        {
            /* Compact: move unread bytes to front */
            int keep = fctx->buf_len - fctx->buf_pos;
            if (keep > 0 && fctx->buf_pos > 0)
                memmove(fctx->buf, fctx->buf + fctx->buf_pos, (size_t)keep);
            fctx->buf_len = keep;
            fctx->buf_pos = 0;

            int space = fctx->buf_size - fctx->buf_len;
            if (space <= 0) {
                /* Buffer full — NAL is larger than H264_FILE_CHUNK_SIZE */
                return H264_ERR_BITSTREAM;
            }

            int n = (int)fread(fctx->buf + fctx->buf_len, 1,
                               (size_t)space, fctx->fp);
            if (n > 0) {
                fctx->buf_len += n;
            } else {
                fctx->eof = 1;
                if (fctx->buf_len == 0)
                    return H264_ERR_EOF;
            }
        }
    }
}

static void annexb_cleanup(H264FileDecoder *fctx)
{
    if (fctx->buf) {
        H264_FREE(fctx->buf);
        fctx->buf = NULL;
    }
}

/* ---- Public API ---- */

H264FileDecoder *h264_open_file(const char *path)
{
    if (!path) return NULL;

    H264FileDecoder *fctx = h264_file_decoder_alloc();
    if (!fctx) return NULL;

    fctx->fp = fopen(path, "rb");
    if (!fctx->fp) {
        h264_decoder_destroy(fctx->dec);
        H264_FREE(fctx);
        return NULL;
    }

    fctx->buf = (uint8_t *)H264_MALLOC(H264_FILE_CHUNK_SIZE);
    if (!fctx->buf) {
        fclose(fctx->fp);
        h264_decoder_destroy(fctx->dec);
        H264_FREE(fctx);
        return NULL;
    }

    fctx->buf_size  = H264_FILE_CHUNK_SIZE;
    fctx->buf_len   = 0;
    fctx->buf_pos   = 0;
    fctx->eof       = 0;
    fctx->type      = 0;
    fctx->frame_count = 0;
    fctx->read_next = annexb_read_next;
    fctx->cleanup   = annexb_cleanup;
    H264_DBGI("opened annexb file: %s", path);
    return fctx;
}

int h264_read_frame(H264FileDecoder *fctx, H264Frame *frame)
{
    if (!fctx || !frame) return H264_ERR_PARAM;
    memset(frame, 0, sizeof(*frame));
    return fctx->read_next(fctx, frame);
}

void h264_close_file(H264FileDecoder *fctx)
{
    if (!fctx) return;
    if (fctx->cleanup) fctx->cleanup(fctx);
    if (fctx->fp)  { fclose(fctx->fp);             fctx->fp  = NULL; }
    if (fctx->dec) { h264_decoder_destroy(fctx->dec); fctx->dec = NULL; }
    H264_FREE(fctx);
}
