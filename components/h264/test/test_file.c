/*
 * test_file.c — Annex-B .h264 file reader test.
 *
 * Steps:
 *   1. Build the 16×16 gray I-frame stream.
 *   2. Write it to /tmp/test_h264_annexb.h264.
 *   3. Open with h264_open_file().
 *   4. Read one frame; verify 16×16 and Y/Cb/Cr = 128.
 *   5. Read again; expect H264_ERR_EOF.
 *   6. Close.
 */

#include <stdio.h>
#include <string.h>
#include <stdint.h>

#include "../include/h264_decoder.h"
#include "../src/h264_common.h"
#include "test_utils.h"
#include "test_stream.h"

#define CHECK(cond, msg) do { \
    if (!(cond)) { \
        fprintf(stderr, "FAIL: %s (line %d)\n", msg, __LINE__); \
        return 1; \
    } \
} while(0)

#define ANNEXB_PATH "/tmp/test_h264_annexb.h264"

int test_file(void)
{
    /* ---- 1. Build stream ---- */
    static uint8_t stream[8192];
    int stream_size = 0;
    int ret = build_16x16_gray_stream(stream, sizeof(stream), &stream_size);
    CHECK(ret == 0,        "annexb: stream build ok");
    CHECK(stream_size > 10,"annexb: stream non-empty");

    /* ---- 2. Write to disk ---- */
    {
        FILE *fp = fopen(ANNEXB_PATH, "wb");
        CHECK(fp != NULL, "annexb: fopen for write");
        size_t written = fwrite(stream, 1, (size_t)stream_size, fp);
        fclose(fp);
        CHECK((int)written == stream_size, "annexb: fwrite");
    }

    /* ---- 3. Open with file decoder ---- */
    H264FileDecoder *fctx = h264_open_file(ANNEXB_PATH);
    CHECK(fctx != NULL, "annexb: h264_open_file");

    /* ---- 4. Read first frame ---- */
    H264Frame frame;
    memset(&frame, 0, sizeof(frame));
    ret = h264_read_frame(fctx, &frame);
    CHECK(ret == H264_OK,     "annexb: first read_frame ok");
    CHECK(frame.is_valid,     "annexb: frame is_valid");
    CHECK(frame.width  == 16, "annexb: frame width 16");
    CHECK(frame.height == 16, "annexb: frame height 16");
    CHECK(frame.y  != NULL,   "annexb: luma plane not null");
    CHECK(frame.cb != NULL,   "annexb: Cb plane not null");
    CHECK(frame.cr != NULL,   "annexb: Cr plane not null");

    /* Verify pixel values */
    {
        int all_y = 1, all_c = 1, i, j;
        for (i = 0; i < 16; i++)
            for (j = 0; j < 16; j++)
                if (frame.y[i * frame.y_stride + j] != 128) all_y = 0;
        for (i = 0; i < 8; i++)
            for (j = 0; j < 8; j++) {
                if (frame.cb[i * frame.c_stride + j] != 128) all_c = 0;
                if (frame.cr[i * frame.c_stride + j] != 128) all_c = 0;
            }
        CHECK(all_y, "annexb: Y = 128");
        CHECK(all_c, "annexb: Cb/Cr = 128");
    }

    /* ---- 5. Second read must return EOF ---- */
    memset(&frame, 0, sizeof(frame));
    ret = h264_read_frame(fctx, &frame);
    CHECK(ret == H264_ERR_EOF, "annexb: second read_frame is EOF");

    /* ---- 6. Close ---- */
    h264_close_file(fctx);
    return 0;
}
