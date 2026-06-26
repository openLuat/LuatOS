/**
 * @file lv_lodepng.c
 *
 */

/*********************
 *      INCLUDES
 *********************/
#include "../../draw/lv_image_decoder_private.h"
#include "../../../lvgl.h"
#include "../../core/lv_global.h"
#if LV_USE_LODEPNG

#include "lv_lodepng.h"
#include "lodepng.h"
#include <stdlib.h>

#ifdef __LUATOS__
#define LUAT_LOG_TAG "airui.png"
#include "luat_log.h"
#include "luat_image.h"
#include "luat_mcu.h"
#include "../../misc/cache/lv_cache.h"

/** 将 lodepng 错误码转为便于排查的中文说明 */
static const char * airui_lodepng_err_hint(unsigned error, unsigned w, unsigned h)
{
    switch(error) {
        case 83:
            return "解码像素缓冲分配失败(需 w*h*4 字节 ARGB8888，检查 PSRAM/LVGL 堆剩余)";
        case 48:
            return "PNG 文件不完整或已损坏";
        case 49:
            return "PNG 头 IHDR 块无效";
        case 89:
            return "PNG 文件格式无效";
        case 91:
            return "zlib 解压后数据长度与预期不符";
        default:
            break;
    }
    (void)w;
    (void)h;
    return lodepng_error_text(error);
}

static const char * airui_png_src_path(const lv_image_decoder_dsc_t * dsc)
{
    if(dsc != NULL && dsc->src_type == LV_IMAGE_SRC_FILE && dsc->src != NULL) {
        return (const char *)dsc->src;
    }
    return "<mem>";
}

static uint32_t airui_png_cache_max_bytes(void)
{
    lv_cache_t * cache = LV_GLOBAL_DEFAULT()->img_cache;
    if(cache == NULL) return 0;
    return (uint32_t)lv_cache_get_max_size(cache, NULL);
}
#endif

/*********************
 *      DEFINES
 *********************/

#define DECODER_NAME    "LODEPNG"

#define image_cache_draw_buf_handlers &(LV_GLOBAL_DEFAULT()->image_cache_draw_buf_handlers)

/**********************
 *      TYPEDEFS
 **********************/

/**********************
 *  STATIC PROTOTYPES
 **********************/
static lv_result_t decoder_info(lv_image_decoder_t * decoder, lv_image_decoder_dsc_t * src, lv_image_header_t * header);
static lv_result_t decoder_open(lv_image_decoder_t * decoder, lv_image_decoder_dsc_t * dsc);
static void decoder_close(lv_image_decoder_t * dec, lv_image_decoder_dsc_t * dsc);
static void convert_color_depth(uint8_t * img_p, uint32_t px_cnt);
static lv_draw_buf_t * decode_png_data(const void * png_data, size_t png_data_size);
/**********************
 *  STATIC VARIABLES
 **********************/

/**********************
 *      MACROS
 **********************/

/**********************
 *   GLOBAL FUNCTIONS
 **********************/

/**
 * Register the PNG decoder functions in LVGL
 */
void lv_lodepng_init(void)
{
    lv_image_decoder_t * dec = lv_image_decoder_create();
    lv_image_decoder_set_info_cb(dec, decoder_info);
    lv_image_decoder_set_open_cb(dec, decoder_open);
    lv_image_decoder_set_close_cb(dec, decoder_close);

    dec->name = DECODER_NAME;
}

void lv_lodepng_deinit(void)
{
    lv_image_decoder_t * dec = NULL;
    while((dec = lv_image_decoder_get_next(dec)) != NULL) {
        if(dec->info_cb == decoder_info) {
            lv_image_decoder_delete(dec);
            break;
        }
    }
}

/**********************
 *   STATIC FUNCTIONS
 **********************/

/**
 * Get info about a PNG image
 * @param decoder   pointer to the decoder where this function belongs
 * @param dsc       image descriptor containing the source and type of the image and other info.
 * @param header    image information is set in header parameter
 * @return          LV_RESULT_OK: no error; LV_RESULT_INVALID: can't get the info
 */
static lv_result_t decoder_info(lv_image_decoder_t * decoder, lv_image_decoder_dsc_t * dsc, lv_image_header_t * header)
{
    LV_UNUSED(decoder); /*Unused*/

    lv_image_src_t src_type = dsc->src_type;          /*Get the source type*/

    if(src_type == LV_IMAGE_SRC_FILE || src_type == LV_IMAGE_SRC_VARIABLE) {
        uint32_t * size;
        static const uint8_t magic[] = {0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a};
        uint8_t buf[24];

        /*If it's a PNG file...*/
        if(src_type == LV_IMAGE_SRC_FILE) {
            /* Read the width and height from the file. They have a constant location:
            * [16..19]: width
            * [20..23]: height
            */
            uint32_t rn;
            lv_fs_read(&dsc->file, buf, sizeof(buf), &rn);

            if(rn != sizeof(buf)) {
#ifdef __LUATOS__
                LLOGE("probe fail: 读取 PNG 头失败, read=%u need=%u src=%s",
                      (unsigned)rn, (unsigned)sizeof(buf), airui_png_src_path(dsc));
#endif
                return LV_RESULT_INVALID;
            }

            if(lv_memcmp(buf, magic, sizeof(magic)) != 0) {
#ifdef __LUATOS__
                LLOGE("probe fail: 非 PNG 文件(魔数不匹配) src=%s", airui_png_src_path(dsc));
#endif
                return LV_RESULT_INVALID;
            }

            size = (uint32_t *)&buf[16];
        }
        /*If it's a PNG file in a  C array...*/
        else {
            const lv_image_dsc_t * img_dsc = dsc->src;
            const uint32_t data_size = img_dsc->data_size;
            size = ((uint32_t *)img_dsc->data) + 4;

            if(data_size < sizeof(magic)) {
#ifdef __LUATOS__
                LLOGE("probe fail: 内存 PNG 数据过短 size=%u", (unsigned)data_size);
#endif
                return LV_RESULT_INVALID;
            }
            if(lv_memcmp(img_dsc->data, magic, sizeof(magic)) != 0) {
#ifdef __LUATOS__
                LLOGE("probe fail: 内存 PNG 魔数不匹配 size=%u", (unsigned)data_size);
#endif
                return LV_RESULT_INVALID;
            }
        }

        /*Save the data in the header*/
        header->cf = LV_COLOR_FORMAT_ARGB8888;
        /*The width and height are stored in Big endian format so convert them to little endian*/
        header->w = (int32_t)((size[0] & 0xff000000) >> 24) + ((size[0] & 0x00ff0000) >> 8);
        header->h = (int32_t)((size[1] & 0xff000000) >> 24) + ((size[1] & 0x00ff0000) >> 8);

        return LV_RESULT_OK;
    }

#ifdef __LUATOS__
    LLOGE("probe fail: 不支持的图片源类型 type=%d", (int)src_type);
#endif
    return LV_RESULT_INVALID;         /*If didn't succeeded earlier then it's an error*/
}

/**
 * Open a PNG image and decode it into dsc.decoded
 * @param decoder   pointer to the decoder where this function belongs
 * @param dsc       decoded image descriptor
 * @return          LV_RESULT_OK: no error; LV_RESULT_INVALID: can't open the image
 */
static lv_result_t decoder_open(lv_image_decoder_t * decoder, lv_image_decoder_dsc_t * dsc)
{
    LV_UNUSED(decoder);
    LV_PROFILER_DECODER_BEGIN_TAG("lv_lodepng_decoder_open");

    const uint8_t * png_data = NULL;
    size_t png_data_size = 0;
    if(dsc->src_type == LV_IMAGE_SRC_FILE) {
        const char * fn = dsc->src;

        /*Load the file*/
        unsigned error = lodepng_load_file((void *)&png_data, &png_data_size, fn);
        if(error) {
            if(png_data != NULL) {
                lv_free((void *)png_data);
            }
#ifdef __LUATOS__
            LLOGE("load fail: 无法加载 PNG 文件 src=%s err=%u (%s) hint=%s",
                  fn, error, lodepng_error_text(error), airui_lodepng_err_hint(error, 0, 0));
#endif
            LV_LOG_WARN("error %u: %s\n", error, lodepng_error_text(error));
            LV_PROFILER_DECODER_END_TAG("lv_lodepng_decoder_open");
            return LV_RESULT_INVALID;
        }
    }
    else if(dsc->src_type == LV_IMAGE_SRC_VARIABLE) {
        const lv_image_dsc_t * img_dsc = dsc->src;
        png_data = img_dsc->data;
        png_data_size = img_dsc->data_size;
    }
    else {
#ifdef __LUATOS__
        LLOGE("open fail: 不支持的图片源类型 type=%d", (int)dsc->src_type);
#endif
        LV_PROFILER_DECODER_END_TAG("lv_lodepng_decoder_open");
        return LV_RESULT_INVALID;
    }

#ifdef __LUATOS__
    uint64_t _airui_dbg_t0 = 0;
    if (luat_image_get_debug()) {
        _airui_dbg_t0 = luat_mcu_tick64();
    }
#endif

    lv_draw_buf_t * decoded = decode_png_data(png_data, png_data_size);

#ifdef __LUATOS__
    if (luat_image_get_debug()) {
        uint64_t _elapsed = luat_mcu_tick64() - _airui_dbg_t0;
        int _period = luat_mcu_us_period();
        uint32_t _elapsed_us = (_period > 0) ? (uint32_t)(_elapsed / (uint64_t)_period) : (uint32_t)(_elapsed / 1000ULL);
        LLOGI("decode %dx%d cost=%u.%03ums src=%s",
              decoded ? (int)dsc->header.w : 0,
              decoded ? (int)dsc->header.h : 0,
              _elapsed_us / 1000U, _elapsed_us % 1000U,
              dsc->src_type == LV_IMAGE_SRC_FILE ? (const char *)dsc->src : "<mem>");
    }
#endif

    if(dsc->src_type == LV_IMAGE_SRC_FILE) lv_free((void *)png_data);

    if(!decoded) {
#ifdef __LUATOS__
        LLOGE("open fail: PNG 解码失败 src=%s insize=%u expect=%dx%d (详见上方 lodepng_decode32 日志)",
              airui_png_src_path(dsc), (unsigned)png_data_size,
              (int)dsc->header.w, (int)dsc->header.h);
#endif
        LV_LOG_WARN("Error decoding PNG");
        LV_PROFILER_DECODER_END_TAG("lv_lodepng_decoder_open");
        return LV_RESULT_INVALID;
    }

    lv_draw_buf_t * adjusted = lv_image_decoder_post_process(dsc, decoded);
    if(adjusted == NULL) {
#ifdef __LUATOS__
        LLOGE("open fail: 解码后处理失败(步幅对齐/预乘 alpha 可能 OOM) src=%s %dx%d data_size=%u",
              airui_png_src_path(dsc), (int)dsc->header.w, (int)dsc->header.h,
              (unsigned)decoded->data_size);
#endif
        lv_draw_buf_destroy(decoded);
        LV_PROFILER_DECODER_END_TAG("lv_lodepng_decoder_open");
        return LV_RESULT_INVALID;
    }

    /*The adjusted draw buffer is newly allocated.*/
    if(adjusted != decoded) {
        lv_draw_buf_destroy(decoded);
        decoded = adjusted;
    }

    dsc->decoded = decoded;

    if(dsc->args.no_cache) {
        LV_PROFILER_DECODER_END_TAG("lv_lodepng_decoder_open");
        return LV_RESULT_OK;
    }

    /*If the image cache is disabled, just return the decoded image*/
    if(!lv_image_cache_is_enabled()) {
        LV_PROFILER_DECODER_END_TAG("lv_lodepng_decoder_open");
        return LV_RESULT_OK;
    }

    /*Add the decoded image to the cache*/
    lv_image_cache_data_t search_key;
    search_key.src_type = dsc->src_type;
    search_key.src = dsc->src;
    search_key.slot.size = decoded->data_size;

    lv_cache_entry_t * entry = lv_image_decoder_add_to_cache(decoder, &search_key, decoded, NULL);

    if(entry == NULL) {
#ifdef __LUATOS__
        LLOGE("open fail: 写入图片缓存失败 src=%s data_size=%u cache_max=%u "
              "(解码结果大于缓存上限时会被拒绝，或缓存驱逐失败)",
              airui_png_src_path(dsc), (unsigned)decoded->data_size, airui_png_cache_max_bytes());
#endif
        LV_PROFILER_DECODER_END_TAG("lv_lodepng_decoder_open");
        return LV_RESULT_INVALID;
    }
    dsc->cache_entry = entry;

    LV_PROFILER_DECODER_END_TAG("lv_lodepng_decoder_open");
    return LV_RESULT_OK;    /*If not returned earlier then it failed*/
}

/**
 * Close PNG image and free data
 * @param decoder   pointer to the decoder where this function belongs
 * @param dsc       decoded image descriptor
 * @return          LV_RESULT_OK: no error; LV_RESULT_INVALID: can't open the image
 */
static void decoder_close(lv_image_decoder_t * decoder, lv_image_decoder_dsc_t * dsc)
{
    LV_UNUSED(decoder);

    if(dsc->args.no_cache ||
       !lv_image_cache_is_enabled()) lv_draw_buf_destroy((lv_draw_buf_t *)dsc->decoded);
}

static lv_draw_buf_t * decode_png_data(const void * png_data, size_t png_data_size)
{
    unsigned png_width;             /*Not used, just required by the decoder*/
    unsigned png_height;            /*Not used, just required by the decoder*/
    lv_draw_buf_t * decoded = NULL;

    /*Decode the image in ARGB8888 */
    unsigned error = lodepng_decode32((unsigned char **)&decoded, &png_width, &png_height, png_data, png_data_size);
    if(error) {
        if(decoded != NULL)  lv_draw_buf_destroy(decoded);
#ifdef __LUATOS__
        LLOGE("decode fail: lodepng_decode32 err=%u (%s) hint=%s insize=%u %ux%u need_buf=%u",
              error, lodepng_error_text(error), airui_lodepng_err_hint(error, png_width, png_height),
              (unsigned)png_data_size, png_width, png_height,
              (unsigned)((uint32_t)png_width * png_height * 4U));
#endif
        return NULL;
    }

    /*Convert the image to the system's color depth*/
    convert_color_depth(decoded->data,  png_width * png_height);

    return decoded;
}

/**
 * If the display is not in 32 bit format (ARGB888) then convert the image to the current color depth
 * @param img the ARGB888 image
 * @param px_cnt number of pixels in `img`
 */
static void convert_color_depth(uint8_t * img_p, uint32_t px_cnt)
{
    lv_color32_t * img_argb = (lv_color32_t *)img_p;
    uint32_t i;
    for(i = 0; i < px_cnt; i++) {
        uint8_t blue = img_argb[i].blue;
        img_argb[i].blue = img_argb[i].red;
        img_argb[i].red = blue;
    }
}

#endif /*LV_USE_LODEPNG*/
