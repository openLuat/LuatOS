#include <stdio.h>
#include <string.h>
#include <stdint.h>

#include "../include/h264_decoder.h"
#include "../src/h264_common.h"
#include "test_utils.h"
#include "test_stream.h"

#define CHECK(cond, msg) do { \
    if (!(cond)) { fprintf(stderr, "FAIL: %s (line %d)\n", msg, __LINE__); return 1; } \
} while(0)

int test_integration(void) {
    /* ---- Build the stream ---- */
    static uint8_t stream[8192];
    int stream_size = 0;
    int ret = build_16x16_gray_stream(stream, sizeof(stream), &stream_size);
    CHECK(ret == 0, "stream build");
    CHECK(stream_size > 10, "stream has data");

    /* ---- Create decoder ---- */
    H264Decoder *dec = h264_decoder_create();
    CHECK(dec != NULL, "decoder create");

    /* ---- Decode stream ---- */
    H264Frame frame;
    memset(&frame, 0, sizeof(frame));

    ret = h264_decode_stream(dec, stream, stream_size, &frame);

    if (ret != H264_OK && ret != H264_ERR_BITSTREAM) {
        fprintf(stderr, "decode_stream returned %d\n", ret);
        h264_decoder_destroy(dec);
        return 1;
    }

    CHECK(frame.is_valid, "frame is valid");
    CHECK(frame.width  == 16, "frame width == 16");
    CHECK(frame.height == 16, "frame height == 16");
    CHECK(frame.y  != NULL, "luma plane not null");
    CHECK(frame.cb != NULL, "Cb plane not null");
    CHECK(frame.cr != NULL, "Cr plane not null");

    /* Verify I_PCM content (Y=128, Cb=128, Cr=128) */
    int all_y_ok = 1, all_c_ok = 1;
    int i;
    for (i = 0; i < 16; i++) {
        int j;
        for (j = 0; j < 16; j++) {
            if (frame.y[i * frame.y_stride + j] != 128) { all_y_ok = 0; }
        }
    }
    for (i = 0; i < 8; i++) {
        int j;
        for (j = 0; j < 8; j++) {
            if (frame.cb[i * frame.c_stride + j] != 128) { all_c_ok = 0; }
            if (frame.cr[i * frame.c_stride + j] != 128) { all_c_ok = 0; }
        }
    }
    CHECK(all_y_ok, "I_PCM luma = 128");
    CHECK(all_c_ok, "I_PCM chroma = 128");

    h264_decoder_destroy(dec);
    return 0;
}
