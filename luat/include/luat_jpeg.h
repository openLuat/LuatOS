#ifndef LUAT_JPEG_H
#define LUAT_JPEG_H

#include "luat_base.h"

typedef struct {
    uint8_t *data;
    uint16_t width;
    uint16_t height;
} luat_jpeg_frame_t;

typedef struct {
    uint16_t width;
    uint16_t height;
} luat_jpeg_info_t;

int luat_jpeg_hw_info(const uint8_t *data, size_t size, luat_jpeg_info_t *info);
int luat_jpeg_hw_init(void **ctx);
int luat_jpeg_hw_decode(void *ctx, const uint8_t *data, size_t size, void *frame);
void luat_jpeg_hw_deinit(void *ctx);

#endif /* LUAT_JPEG_H */
