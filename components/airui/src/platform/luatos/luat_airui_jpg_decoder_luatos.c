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
#include "luat_image.h"
#include "luat_fs.h"
#include "lvgl9/src/draw/lv_draw_buf.h"
#include "lvgl9/src/draw/lv_image_decoder_private.h"
#include "lvgl9/src/misc/cache/instance/lv_image_cache.h"
#include <string.h>

#define LUAT_LOG_TAG "airui.jpg"
#include "luat_log.h"

static bool g_luatos_jpg_decoder_registered = false;

static int read_file_to_buf(const char *path, uint8_t **out_buf, size_t *out_len)
{
    FILE *fd = NULL;
    uint8_t *buf = NULL;
    long fsize = 0;
    int ret = -1;

    fd = luat_fs_fopen(path, "rb");
    if (fd == NULL) {
        LLOGW("no such file %s", path);
        return -1;
    }

    luat_fs_fseek(fd, 0, SEEK_END);
    fsize = luat_fs_ftell(fd);
    luat_fs_fseek(fd, 0, SEEK_SET);
    if (fsize <= 0) {
        LLOGE("bad file size %s", path);
        goto cleanup;
    }

    buf = (uint8_t *)luat_heap_memalign(8, (size_t)fsize);
    if (buf == NULL) {
        LLOGE("oom: file_buf %ld bytes", fsize);
        goto cleanup;
    }

    if (luat_fs_fread(buf, 1, (size_t)fsize, fd) != (size_t)fsize) {
        LLOGE("read file error %s", path);
        luat_heap_free(buf);
        buf = NULL;
        goto cleanup;
    }

    *out_buf = buf;
    *out_len = (size_t)fsize;
    ret = 0;

cleanup:
    luat_fs_fclose(fd);
    return ret;
}

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
    luat_img_conf_t img_conf;
    luat_img_info_t img_info;
    uint8_t *file_buf = NULL;
    size_t file_len = 0;
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

    ret = read_file_to_buf((const char *)dsc->src, &file_buf, &file_len);
    if (ret != 0) {
        return LV_RESULT_INVALID;
    }

    memset(&img_conf, 0, sizeof(img_conf));
    img_conf.format = LUAT_IMG_FMT_JPG;
    img_conf.decode_mode = LUAT_IMG_DECODE_SW;
    img_conf.source_path = (const char *)dsc->src;

    if (luat_lcd_get_default() != NULL && luat_lcd_get_default()->acc_hw_jpeg) {
        img_conf.decode_mode = LUAT_IMG_DECODE_HW;
    }

    memset(&img_info, 0, sizeof(img_info));
    ret = luat_image_decode(&img_conf, file_buf, file_len, &img_info);
    if (ret != LUAT_IMG_OK && img_conf.decode_mode == LUAT_IMG_DECODE_HW) {
        memset(&img_info, 0, sizeof(img_info));
        img_conf.decode_mode = LUAT_IMG_DECODE_SW;
        ret = luat_image_decode(&img_conf, file_buf, file_len, &img_info);
    }
    luat_heap_free(file_buf);

    if (ret != LUAT_IMG_OK || img_info.data == NULL || img_info.width == 0 || img_info.height == 0) {
        return LV_RESULT_INVALID;
    }

    decoded = lv_malloc_zeroed(sizeof(lv_draw_buf_t));
    if (decoded == NULL) {
        luat_heap_free(img_info.data);
        return LV_RESULT_INVALID;
    }

    if (lv_draw_buf_init(decoded, img_info.width, img_info.height, LV_COLOR_FORMAT_RGB565,
                         img_info.width * sizeof(luat_color_t), img_info.data, img_info.size) != LV_RESULT_OK) {
        lv_free(decoded);
        luat_heap_free(img_info.data);
        return LV_RESULT_INVALID;
    }

    decoded->handlers = lv_draw_buf_get_image_handlers();
    lv_draw_buf_set_flag(decoded, LV_IMAGE_FLAGS_MODIFIABLE);
    lv_draw_buf_set_flag(decoded, LV_IMAGE_FLAGS_ALLOCATED);

    dsc->header.cf = LV_COLOR_FORMAT_RGB565;
    dsc->header.w = img_info.width;
    dsc->header.h = img_info.height;
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
