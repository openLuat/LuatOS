#include "luat_base.h"
#include "luat_mem.h"

#include "luat_image.h"
#include "luat_image_common.h"

#define LUAT_LOG_TAG "image"
#include "luat_log.h"

#ifdef LUAT_USE_LODEPNG
#include "lodepng.h"

int luat_png_decode_sw_default(const luat_img_conf_t *img_conf, uint8_t *in_buf, size_t in_len, luat_img_info_t* img_info) {
    (void)img_conf;
    unsigned char *rgba = NULL;
    unsigned w = 0;
    unsigned h = 0;
    unsigned err = lodepng_decode32(&rgba, &w, &h, in_buf, in_len);
    if (err) {
        LLOGE("lodepng decode error %u", err);
        return LUAT_IMG_ERR;
    }
    if (luat_image_prepare_output(img_info, (uint16_t)w, (uint16_t)h) != LUAT_IMG_OK) {
        LLOGE("out of memory for png decode buffer");
        luat_heap_free(rgba);
        return LUAT_IMG_ERR;
    }

    luat_image_rgba_to_color_buffer(rgba, (uint32_t)w * h, (luat_color_t*)img_info->data);
    luat_heap_free(rgba);
    return LUAT_IMG_OK;
}

const luat_img_decoder_opts_t png_sw_decoder_opts = {
    .decode = luat_png_decode_sw_default,
};
#endif /* LUAT_USE_LODEPNG */

#ifdef LUAT_USE_PNG
LUAT_WEAK int luat_png_decode_hw(const luat_img_conf_t *img_conf, uint8_t *in_buf, size_t in_len, luat_img_info_t* img_info) {
    (void)img_conf;
    (void)in_buf;
    (void)in_len;
    (void)img_info;
    return LUAT_IMG_ERR;
}

const luat_img_decoder_opts_t png_hw_decoder_opts = {
    .decode = luat_png_decode_hw,
};
#endif /* LUAT_USE_PNG */
