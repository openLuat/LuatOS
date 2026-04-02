#ifndef LUAT_JPEG_H
#define LUAT_JPEG_H

#include "luat_base.h"

int luat_jpeg_hw_init(void **ctx);
int luat_jpeg_hw_decode(void *ctx, const uint8_t *data, size_t size, void *frame);
void luat_jpeg_hw_deinit(void *ctx);

#endif /* LUAT_JPEG_H */