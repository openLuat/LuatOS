#ifndef H264_DECODER_H
#define H264_DECODER_H

#include <stdint.h>
#include <stddef.h>

typedef struct H264Decoder H264Decoder;

typedef struct {
    uint8_t *y;
    uint8_t *cb;
    uint8_t *cr;
    int y_stride;
    int c_stride;
    int width;
    int height;
    int is_valid;
} H264Frame;

H264Decoder* h264_decoder_create(void);
void h264_decoder_destroy(H264Decoder *dec);
int h264_decode_nal(H264Decoder *dec, const uint8_t *nal_data, int nal_size, H264Frame *frame);
int h264_decode_stream(H264Decoder *dec, const uint8_t *data, int size, H264Frame *frame);
void h264_frame_free(H264Frame *frame);

#endif /* H264_DECODER_H */
