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

/* ---- File-based decoding ---- */

/**
 * File decoder handle for frame-by-frame decoding from disk.
 * Supports Annex-B .h264 files and .mp4 files.
 */
typedef struct H264FileDecoder H264FileDecoder;

/** End of file/stream reached */
#define H264_ERR_EOF  (-5)

/**
 * Open an Annex-B H.264 file (.h264, .264) for frame-by-frame decoding.
 * Returns NULL on failure.
 */
H264FileDecoder* h264_open_file(const char *path);

/**
 * Open an MP4 file for frame-by-frame H.264 decoding.
 * Returns NULL on failure (file not found, no H264 track, etc.)
 */
H264FileDecoder* h264_open_mp4(const char *path);

/**
 * Decode the next frame from the file.
 * Returns H264_OK (0) and fills *frame on success.
 * Returns H264_ERR_EOF (-5) when all frames have been decoded.
 * Returns other negative codes on error.
 * The frame's y/cb/cr pointers are valid until the next call to
 * h264_read_frame() or h264_close_file().
 */
int h264_read_frame(H264FileDecoder *fctx, H264Frame *frame);

/**
 * Close the file decoder and free all resources.
 */
void h264_close_file(H264FileDecoder *fctx);

#endif /* H264_DECODER_H */
