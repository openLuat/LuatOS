/**
 * @file luat_airui_jpg_decoder_luatos.c
 * @summary LuatOS platform JPG decoder
 * @responsible Prefer HW decode when safe; risk-skip or fail → SW (tjpgd) / let hzjpeg claim
 */

#include "luat_conf_bsp.h"
#if defined(__BK72XX__)
    #include "luat_conf_bsp_air8101.h"
#endif

#if defined(LUAT_USE_AIRUI_LUATOS)

#include "luat_airui_platform_luatos.h"
#include "luat_image.h"
#include "luat_mem.h"
#include "luat_fs.h"
#include "lvgl9/src/draw/lv_draw_buf.h"
#include "lvgl9/src/draw/lv_image_decoder_private.h"
#include "lvgl9/src/misc/cache/instance/lv_image_cache.h"
#include <string.h>

#define LUAT_LOG_TAG "airui.jpg"
#include "luat_log.h"

/* COM/APPn payload larger than this is treated as HW-hostile (e.g. DHAV / fat COM). */
#ifndef AIRUI_JPG_APP_COM_MAX_LEN
#define AIRUI_JPG_APP_COM_MAX_LEN 512
#endif

static bool g_luatos_jpg_decoder_registered = false;

typedef struct {
    int risky;
    const char *reason;
    uint16_t width;
    uint16_t height;
} airui_jpg_risk_t;

static bool airui_luatos_is_jpg_path(const char *src)
{
    const char *dot;

    if (src == NULL) {
        return false;
    }

    dot = strrchr(src, '.');
    if (dot == NULL) {
        return false;
    }

    return (strcmp(dot, ".jpg") == 0) ||
           (strcmp(dot, ".JPG") == 0) ||
           (strcmp(dot, ".jpeg") == 0) ||
           (strcmp(dot, ".JPEG") == 0);
}

static int airui_jpg_memmem_dhav(const uint8_t *buf, size_t len)
{
    size_t i;
    if (buf == NULL || len < 4) {
        return 0;
    }
    for (i = 0; i + 3 < len; i++) {
        if (buf[i] == 'D' && buf[i + 1] == 'H' && buf[i + 2] == 'A' && buf[i + 3] == 'V') {
            return 1;
        }
    }
    return 0;
}

/**
 * Scan JPEG markers for HW-hostile patterns. Soft-parse only, no VPU.
 * @return 0 on parse complete (risky flag set in out), -1 on I/O/arg error
 */
static int airui_jpg_scan_mem(const uint8_t *data, size_t size, airui_jpg_risk_t *out)
{
    size_t pos = 0;
    int found_sof = 0;

    if (out == NULL) {
        return -1;
    }
    memset(out, 0, sizeof(*out));

    if (data == NULL || size < 4) {
        out->risky = 1;
        out->reason = "too small";
        return 0;
    }

    if (data[0] != 0xFF || data[1] != 0xD8) {
        out->risky = 1;
        out->reason = "bad SOI";
        return 0;
    }

    pos = 2;
    while (pos + 1 < size) {
        uint8_t marker;
        uint16_t seg_len;
        size_t payload_len;
        const uint8_t *payload;

        while (pos < size && data[pos] == 0xFF) {
            pos++;
        }
        if (pos >= size) {
            break;
        }

        marker = data[pos++];

        /* Standalone markers without length */
        if (marker == 0xD8) {
            continue;
        }
        if (marker == 0xD9) {
            break;
        }
        if (marker == 0x01 || (marker >= 0xD0 && marker <= 0xD7)) {
            continue;
        }
        if (marker == 0xDA) {
            break;
        }

        if (pos + 2 > size) {
            out->risky = 1;
            out->reason = "truncated segment";
            return 0;
        }

        seg_len = (uint16_t)(((uint16_t)data[pos] << 8) | data[pos + 1]);
        pos += 2;
        if (seg_len < 2 || pos + (size_t)(seg_len - 2) > size) {
            out->risky = 1;
            out->reason = "bad segment length";
            return 0;
        }

        payload = data + pos;
        payload_len = (size_t)(seg_len - 2);

        /* Progressive / unsupported SOF */
        if (marker == 0xC2 || marker == 0xC6 || marker == 0xCA || marker == 0xCE) {
            out->risky = 1;
            out->reason = "progressive";
            out->width = 0;
            out->height = 0;
            if (payload_len >= 5) {
                out->height = (uint16_t)(((uint16_t)payload[1] << 8) | payload[2]);
                out->width = (uint16_t)(((uint16_t)payload[3] << 8) | payload[4]);
            }
            return 0;
        }

        /* Baseline / extended SOF — take size, check 16-align */
        if ((marker >= 0xC0 && marker <= 0xC3) ||
            (marker >= 0xC5 && marker <= 0xC7) ||
            (marker >= 0xC9 && marker <= 0xCB) ||
            (marker >= 0xCD && marker <= 0xCF)) {
            if (payload_len < 5) {
                out->risky = 1;
                out->reason = "bad SOF";
                return 0;
            }
            out->height = (uint16_t)(((uint16_t)payload[1] << 8) | payload[2]);
            out->width = (uint16_t)(((uint16_t)payload[3] << 8) | payload[4]);
            found_sof = 1;
            if (out->width == 0 || out->height == 0) {
                out->risky = 1;
                out->reason = "zero size";
                return 0;
            }
            if ((out->width % 16) != 0 || (out->height % 16) != 0) {
                out->risky = 1;
                out->reason = "not 16-aligned";
                return 0;
            }
        }

        /* Fat COM / APPn — EC718HM HW often mishandles these */
        if (marker == 0xFE || (marker >= 0xE0 && marker <= 0xEF)) {
            if (payload_len > (size_t)AIRUI_JPG_APP_COM_MAX_LEN) {
                out->risky = 1;
                out->reason = "large COM/APP";
                return 0;
            }
            if (airui_jpg_memmem_dhav(payload, payload_len)) {
                out->risky = 1;
                out->reason = "DHAV";
                return 0;
            }
        }

        pos += payload_len;
    }

    if (!found_sof) {
        out->risky = 1;
        out->reason = "no SOF";
        return 0;
    }

    return 0;
}

static int airui_jpg_scan_path(const char *path, airui_jpg_risk_t *out)
{
    FILE *fd = NULL;
    long fsize = 0;
    uint8_t *buf = NULL;
    int ret = -1;

    if (path == NULL || out == NULL) {
        return -1;
    }
    memset(out, 0, sizeof(*out));

    fd = luat_fs_fopen(path, "rb");
    if (fd == NULL) {
        out->risky = 1;
        out->reason = "open fail";
        return 0;
    }

    luat_fs_fseek(fd, 0, SEEK_END);
    fsize = luat_fs_ftell(fd);
    luat_fs_fseek(fd, 0, SEEK_SET);
    if (fsize <= 0) {
        out->risky = 1;
        out->reason = "empty file";
        luat_fs_fclose(fd);
        return 0;
    }

    buf = (uint8_t *)luat_heap_malloc((size_t)fsize);
    if (buf == NULL) {
        out->risky = 1;
        out->reason = "oom scan";
        luat_fs_fclose(fd);
        return 0;
    }

    if (luat_fs_fread(buf, 1, (size_t)fsize, fd) != (size_t)fsize) {
        out->risky = 1;
        out->reason = "read fail";
        luat_heap_free(buf);
        luat_fs_fclose(fd);
        return 0;
    }
    luat_fs_fclose(fd);

    ret = airui_jpg_scan_mem(buf, (size_t)fsize, out);
    luat_heap_free(buf);
    return ret;
}

static lv_result_t airui_luatos_jpg_finish_decoded(lv_image_decoder_t *decoder, lv_image_decoder_dsc_t *dsc,
                                                    luat_img_info_t *img_info)
{
    lv_draw_buf_t *decoded = NULL;
    lv_draw_buf_t *adjusted = NULL;

    decoded = lv_malloc_zeroed(sizeof(lv_draw_buf_t));
    if (decoded == NULL) {
        luat_heap_free(img_info->data);
        img_info->data = NULL;
        return LV_RESULT_INVALID;
    }

    if (lv_draw_buf_init(decoded, img_info->width, img_info->height, LV_COLOR_FORMAT_RGB565,
                         img_info->width * sizeof(luat_color_t), img_info->data, img_info->size) != LV_RESULT_OK) {
        lv_free(decoded);
        luat_heap_free(img_info->data);
        img_info->data = NULL;
        return LV_RESULT_INVALID;
    }

    /* Ownership of pixel buffer moves into draw_buf */
    img_info->data = NULL;

    decoded->handlers = lv_draw_buf_get_image_handlers();
    lv_draw_buf_set_flag(decoded, LV_IMAGE_FLAGS_MODIFIABLE);
    lv_draw_buf_set_flag(decoded, LV_IMAGE_FLAGS_ALLOCATED);

    dsc->header.cf = LV_COLOR_FORMAT_RGB565;
    dsc->header.w = img_info->width;
    dsc->header.h = img_info->height;
    dsc->header.stride = decoded->header.stride;

    adjusted = lv_image_decoder_post_process(dsc, decoded);
    if (adjusted == NULL) {
        lv_draw_buf_destroy(decoded);
        return LV_RESULT_INVALID;
    }

    if (adjusted != decoded) {
        lv_draw_buf_destroy(decoded);
        decoded = adjusted;
    }

    dsc->decoded = decoded;

    if (dsc->args.no_cache || !lv_image_cache_is_enabled()) {
        return LV_RESULT_OK;
    }

    {
        lv_image_cache_data_t search_key;
        memset(&search_key, 0, sizeof(search_key));
        search_key.src_type = dsc->src_type;
        search_key.src = dsc->src;
        search_key.slot.size = decoded->data_size;

        dsc->cache_entry = lv_image_decoder_add_to_cache(decoder, &search_key, decoded, NULL);
        if (dsc->cache_entry == NULL) {
            lv_draw_buf_destroy(decoded);
            dsc->decoded = NULL;
            return LV_RESULT_INVALID;
        }
    }

    return LV_RESULT_OK;
}

static int airui_luatos_jpg_decode_mode(const char *path, luat_img_decode_mode_t mode, luat_img_info_t *img_info)
{
    luat_img_conf_t img_conf;

    memset(&img_conf, 0, sizeof(img_conf));
    img_conf.format = LUAT_IMG_FMT_JPG;
    img_conf.decode_mode = mode;
    img_conf.source_path = path;

    memset(img_info, 0, sizeof(*img_info));
    return luat_image_decode(&img_conf, NULL, 0, img_info);
}

static lv_result_t airui_luatos_jpg_decoder_info(lv_image_decoder_t *decoder, lv_image_decoder_dsc_t *dsc,
                                                  lv_image_header_t *header)
{
    luat_img_conf_t img_conf;
    luat_img_info_t img_info;
    airui_jpg_risk_t risk;
    int ret;
    const char *src;

    LV_UNUSED(decoder);

    if (dsc == NULL || header == NULL || dsc->src_type != LV_IMAGE_SRC_FILE) {
        return LV_RESULT_INVALID;
    }

    src = (const char *)dsc->src;
    if (!airui_luatos_is_jpg_path(src)) {
        return LV_RESULT_INVALID;
    }

    if (airui_jpg_scan_path(src, &risk) != 0) {
        return LV_RESULT_INVALID;
    }
    if (risk.risky) {
        /* Let hzjpeg (or other SW decoder) claim this file — avoid HW crash/hang. */
        LLOGI("skip HW, risky jpeg: %s src=%s", risk.reason ? risk.reason : "?", src);
        return LV_RESULT_INVALID;
    }

    memset(&img_conf, 0, sizeof(img_conf));
    img_conf.format = LUAT_IMG_FMT_JPG;
    img_conf.decode_mode = LUAT_IMG_DECODE_HW;
    img_conf.source_path = src;

    memset(&img_info, 0, sizeof(img_info));
    ret = luat_image_probe(&img_conf, NULL, 0, &img_info);
    if (ret != LUAT_IMG_OK || img_info.width == 0 || img_info.height == 0) {
        return LV_RESULT_INVALID;
    }

    header->cf = LV_COLOR_FORMAT_RGB565;
    header->w = img_info.width;
    header->h = img_info.height;
    header->stride = img_info.width * sizeof(luat_color_t);
    return LV_RESULT_OK;
}

static lv_result_t airui_luatos_jpg_decoder_open(lv_image_decoder_t *decoder, lv_image_decoder_dsc_t *dsc)
{
    luat_img_info_t img_info;
    airui_jpg_risk_t risk;
    int ret;
    int use_sw = 0;
    const char *src;

    if (dsc == NULL || dsc->src_type != LV_IMAGE_SRC_FILE) {
        return LV_RESULT_INVALID;
    }

    src = (const char *)dsc->src;
    if (!airui_luatos_is_jpg_path(src)) {
        return LV_RESULT_INVALID;
    }

    if (airui_jpg_scan_path(src, &risk) != 0) {
        return LV_RESULT_INVALID;
    }

    if (risk.risky) {
        /* Defensive: if we still own the file, decode via SW instead of HW. */
        LLOGI("skip HW, risky jpeg: %s src=%s", risk.reason ? risk.reason : "?", src);
        use_sw = 1;
    }

    memset(&img_info, 0, sizeof(img_info));

    if (!use_sw) {
        LLOGI("use hardware jpeg decode: %s", src);
        ret = airui_luatos_jpg_decode_mode(src, LUAT_IMG_DECODE_HW, &img_info);
        if (ret != LUAT_IMG_OK || img_info.data == NULL || img_info.width == 0 || img_info.height == 0) {
            LLOGW("HW failed ret=%d, fallback to SW src=%s", ret, src);
            if (img_info.data != NULL) {
                luat_heap_free(img_info.data);
                img_info.data = NULL;
            }
            use_sw = 1;
        }
    }

    if (use_sw) {
#ifdef LUAT_USE_TJPGD
        LLOGI("use SW jpeg decode: %s", src);
        ret = airui_luatos_jpg_decode_mode(src, LUAT_IMG_DECODE_SW, &img_info);
        if (ret != LUAT_IMG_OK || img_info.data == NULL || img_info.width == 0 || img_info.height == 0) {
            if (img_info.data != NULL) {
                luat_heap_free(img_info.data);
            }
            return LV_RESULT_INVALID;
        }
#else
        LLOGW("SW jpeg decode unavailable (no TJPGD), src=%s", src);
        return LV_RESULT_INVALID;
#endif
    }

    return airui_luatos_jpg_finish_decoded(decoder, dsc, &img_info);
}

static void airui_luatos_jpg_decoder_close(lv_image_decoder_t *decoder, lv_image_decoder_dsc_t *dsc)
{
    LV_UNUSED(decoder);

    if (dsc == NULL || dsc->decoded == NULL) {
        return;
    }

    if (dsc->args.no_cache || !lv_image_cache_is_enabled()) {
        lv_draw_buf_destroy((lv_draw_buf_t *)dsc->decoded);
    }
}

int airui_platform_luatos_register_jpg_decoder(void)
{
    lv_image_decoder_t *decoder;

    if (g_luatos_jpg_decoder_registered) {
        return AIRUI_OK;
    }

    decoder = lv_image_decoder_create();
    if (decoder == NULL) {
        return AIRUI_ERR_NO_MEM;
    }

    lv_image_decoder_set_info_cb(decoder, airui_luatos_jpg_decoder_info);
    lv_image_decoder_set_open_cb(decoder, airui_luatos_jpg_decoder_open);
    lv_image_decoder_set_close_cb(decoder, airui_luatos_jpg_decoder_close);
    decoder->name = "airui_luatos_jpg";

    g_luatos_jpg_decoder_registered = true;
    return AIRUI_OK;
}

#endif /* LUAT_USE_AIRUI_LUATOS */
