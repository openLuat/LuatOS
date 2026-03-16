/**
 * @file luat_airui_jpg_decoder_luatos.c
 * @summary LuatOS 平台 JPG 解码器
 * @responsible 优先复用 LCD JPG 解码能力并接入 LVGL 图片缓存
 */

#include "luat_conf_bsp.h"
#if defined(__BK72XX__)
    #include "luat_conf_bsp_air8101.h"
#endif

#if defined(LUAT_USE_AIRUI_LUATOS)

#include "luat_airui_platform_luatos.h"
#include "luat_mem.h"
#include "lvgl9/src/draw/lv_draw_buf.h"
#include "lvgl9/src/draw/lv_image_decoder_private.h"
#include "lvgl9/src/misc/cache/instance/lv_image_cache.h"
#include <string.h>

#define LUAT_LOG_TAG "airui.jpg"
#include "luat_log.h"

static bool g_luatos_jpg_decoder_registered = false;

// 判断是否是 JPG 图片路径
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

// 获取 JPG 图片信息
static lv_result_t airui_luatos_jpg_decoder_info(lv_image_decoder_t *decoder, lv_image_decoder_dsc_t *dsc,
                                                  lv_image_header_t *header)
{
    luat_lcd_conf_t *lcd_conf;
    uint16_t width = 0;
    uint16_t height = 0;
    int ret;

    LV_UNUSED(decoder);

    if (dsc == NULL || header == NULL || dsc->src_type != LV_IMAGE_SRC_FILE) {
        return LV_RESULT_INVALID;
    }

    if (!airui_luatos_is_jpg_path((const char *)dsc->src)) {
        return LV_RESULT_INVALID;
    }

    lcd_conf = luat_lcd_get_default();
    if (lcd_conf == NULL || lcd_conf->acc_hw_jpeg == 0) {
        return LV_RESULT_INVALID;
    }

    ret = lcd_jpeg_info(lcd_conf, (const char *)dsc->src, &width, &height);
    if (ret != 0 || width == 0 || height == 0) {
        return LV_RESULT_INVALID;
    }

    header->cf = LV_COLOR_FORMAT_RGB565;
    header->w = width;
    header->h = height;
    header->stride = width * sizeof(luat_color_t);
    return LV_RESULT_OK;
}

// 打开 JPG 图片
static lv_result_t airui_luatos_jpg_decoder_open(lv_image_decoder_t *decoder, lv_image_decoder_dsc_t *dsc)
{
    luat_lcd_conf_t *lcd_conf;
    luat_lcd_buff_info_t buff_info = {0};
    lv_draw_buf_t *decoded = NULL;
    lv_draw_buf_t *adjusted = NULL;
    int ret;

    LV_UNUSED(decoder);

    if (dsc == NULL || dsc->src_type != LV_IMAGE_SRC_FILE) {
        return LV_RESULT_INVALID;
    }

    if (!airui_luatos_is_jpg_path((const char *)dsc->src)) {
        return LV_RESULT_INVALID;
    }

    lcd_conf = luat_lcd_get_default();
    if (lcd_conf == NULL || lcd_conf->acc_hw_jpeg == 0) {
        return LV_RESULT_INVALID;
    }

    LLOGI("use hardware jpeg decode: %s", (const char *)dsc->src);

    ret = lcd_jpeg_decode(lcd_conf, (const char *)dsc->src, &buff_info);
    if (ret != 0 || buff_info.buff == NULL || buff_info.width == 0 || buff_info.height == 0) {
        if (buff_info.buff != NULL) {
            luat_heap_free(buff_info.buff);
        }
        return LV_RESULT_INVALID;
    }

    decoded = lv_malloc_zeroed(sizeof(lv_draw_buf_t));
    if (decoded == NULL) {
        luat_heap_free(buff_info.buff);
        return LV_RESULT_INVALID;
    }

    if (lv_draw_buf_init(decoded, buff_info.width, buff_info.height, LV_COLOR_FORMAT_RGB565,
                         buff_info.width * sizeof(luat_color_t), buff_info.buff, buff_info.len) != LV_RESULT_OK) {
        lv_free(decoded);
        luat_heap_free(buff_info.buff);
        return LV_RESULT_INVALID;
    }

    decoded->handlers = lv_draw_buf_get_image_handlers();
    lv_draw_buf_set_flag(decoded, LV_IMAGE_FLAGS_MODIFIABLE);
    lv_draw_buf_set_flag(decoded, LV_IMAGE_FLAGS_ALLOCATED);

    dsc->header.cf = LV_COLOR_FORMAT_RGB565;
    dsc->header.w = buff_info.width;
    dsc->header.h = buff_info.height;
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

    return LV_RESULT_OK;
}

// 关闭 JPG 图片
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

// 注册 LuatOS 平台 JPG 解码器
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
