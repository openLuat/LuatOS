#include "luat_base.h"
#include "luat_mem.h"

#include "luat_image.h"
#include "luat_image_common.h"

#define LUAT_LOG_TAG "image"
#include "luat_log.h"

#ifdef LUAT_USE_WEBP
#include "webp/decode.h"

int luat_webp_decode_sw_default(const luat_img_conf_t *img_conf, uint8_t *in_buf, size_t in_len, luat_img_info_t* img_info) {
    (void)img_conf;
    int w = 0;
    int h = 0;
    uint8_t *rgba = WebPDecodeRGBA(in_buf, in_len, &w, &h);
    if (!rgba) {
        LLOGE("WebPDecodeRGBA failed");
        return LUAT_IMG_ERR;
    }
    if (luat_image_prepare_output(img_info, (uint16_t)w, (uint16_t)h) != LUAT_IMG_OK) {
        LLOGE("out of memory for webp decode buffer");
        WebPFree(rgba);
        return LUAT_IMG_ERR;
    }

    luat_image_rgba_to_color_buffer(rgba, (uint32_t)w * h, (luat_color_t*)img_info->data);
    WebPFree(rgba);
    return LUAT_IMG_OK;
}

LUAT_WEAK int luat_webp_decode_hw(const luat_img_conf_t *img_conf, uint8_t *in_buf, size_t in_len, luat_img_info_t* img_info) {
    (void)img_conf;
    (void)in_buf;
    (void)in_len;
    (void)img_info;
    return LUAT_IMG_ERR;
}

const luat_img_decoder_opts_t webp_sw_decoder_opts = {
    .decode = luat_webp_decode_sw_default,
};

const luat_img_decoder_opts_t webp_hw_decoder_opts = {
    .decode = luat_webp_decode_hw,
};
#endif /* LUAT_USE_WEBP */
