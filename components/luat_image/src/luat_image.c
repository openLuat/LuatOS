#include "luat_base.h"
#include "luat_image.h"
#include "luat_image_decoders_internal.h"
#include "luat_mcu.h"

#define LUAT_LOG_TAG "image"
#include "luat_log.h"

static int g_luat_image_debug_enabled = 0;

static const luat_img_decoder_opts_t* const decoder_opts_table[] = {
#ifdef LUAT_USE_JPG
#ifdef LUAT_USE_TJPGD
    [LUAT_IMG_DECODER_KEY(LUAT_IMG_FMT_JPG, LUAT_IMG_DECODE_SW)] = &jpeg_sw_decoder_opts,
#endif
#ifdef LUAT_USE_JPG_HW
    [LUAT_IMG_DECODER_KEY(LUAT_IMG_FMT_JPG, LUAT_IMG_DECODE_HW)] = &jpeg_hw_decoder_opts,
#endif /* LUAT_USE_JPG_HW */
#endif /* LUAT_USE_JPG */
#ifdef LUAT_USE_PNG
#ifdef LUAT_USE_LODEPNG
    [LUAT_IMG_DECODER_KEY(LUAT_IMG_FMT_PNG, LUAT_IMG_DECODE_SW)] = &png_sw_decoder_opts,
#endif 
#ifdef LUAT_USE_PNG_HW
    [LUAT_IMG_DECODER_KEY(LUAT_IMG_FMT_PNG, LUAT_IMG_DECODE_HW)] = &png_hw_decoder_opts,
#endif /* LUAT_USE_PNG_HW */
#endif /* LUAT_USE_PNG */
#ifdef LUAT_USE_WEBP
    [LUAT_IMG_DECODER_KEY(LUAT_IMG_FMT_WEBP, LUAT_IMG_DECODE_SW)] = &webp_sw_decoder_opts,
    [LUAT_IMG_DECODER_KEY(LUAT_IMG_FMT_WEBP, LUAT_IMG_DECODE_HW)] = &webp_hw_decoder_opts,
#endif
};

#define DECODER_OPTS_TABLE_SIZE (sizeof(decoder_opts_table) / sizeof(decoder_opts_table[0]))

const luat_img_decoder_opts_t* luat_image_get_decoder_opts(luat_img_format_t fmt, luat_img_decode_mode_t mode) {
    int key = LUAT_IMG_DECODER_KEY(fmt, mode);
    if (key < 0 || (size_t)key >= DECODER_OPTS_TABLE_SIZE) {
        return NULL;
    }
    return decoder_opts_table[key];
}

void luat_image_set_debug(int enable) {
    g_luat_image_debug_enabled = enable ? 1 : 0;
}

int luat_image_get_debug(void) {
    return g_luat_image_debug_enabled;
}

static uint64_t luat_image_now_us(void) {
    int period = luat_mcu_us_period();
    if (period <= 0) {
        return luat_mcu_tick64_ms() * 1000ULL;
    }
    return luat_mcu_tick64() / (uint64_t)period;
}

static const char* luat_image_format_name(luat_img_format_t fmt) {
    switch (fmt) {
    case LUAT_IMG_FMT_JPG:
        return "jpg";
    case LUAT_IMG_FMT_PNG:
        return "png";
    case LUAT_IMG_FMT_WEBP:
        return "webp";
    default:
        return "unknown";
    }
}

static const char* luat_image_mode_name(luat_img_decode_mode_t mode) {
    switch (mode) {
    case LUAT_IMG_DECODE_SW:
        return "sw";
    case LUAT_IMG_DECODE_HW:
        return "hw";
    default:
        return "unknown";
    }
}

int luat_image_decode(luat_img_conf_t* img_conf, uint8_t *in_buf, size_t size, luat_img_info_t* img_info) {
    uint64_t start_us = 0;
    uint64_t elapsed_us = 0;
    int ret = LUAT_IMG_ERR;

    if (img_conf == NULL || in_buf == NULL || size == 0 || img_info == NULL) {
        return LUAT_IMG_ERR;
    }

    if (g_luat_image_debug_enabled) {
        start_us = luat_image_now_us();
    }

    const luat_img_decoder_opts_t* opts = luat_image_get_decoder_opts(img_conf->format, img_conf->decode_mode);
    if (!opts || !opts->decode) {
        LLOGW("no decoder available for format=%d mode=%d", img_conf->format, img_conf->decode_mode);
        return LUAT_IMG_ERR;
    }

    ret = opts->decode(img_conf, in_buf, size, img_info);

    if (g_luat_image_debug_enabled) {
        elapsed_us = luat_image_now_us();
        if (elapsed_us > start_us) {
            elapsed_us -= start_us;
        } else {
            elapsed_us = 0;
        }

        LLOGI("[decode] fmt=%s mode=%s input=%uB output=%ux%u buf=%uB cost=%.3fms ret=%d src=%s",
              luat_image_format_name(img_conf->format),
              luat_image_mode_name(img_conf->decode_mode),
              (unsigned int)size,
              (unsigned int)img_info->width,
              (unsigned int)img_info->height,
              (unsigned int)img_info->size,
              (double)elapsed_us / 1000.0,
              ret,
              img_conf->source_path ? img_conf->source_path : "<memory>");
    }

    return ret;
}
