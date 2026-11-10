/** @file luat_plcui_image_luatos.c
 * LuatOS image decoder: safe hardware paths and explicit LVGL software fallback.
 */
#include "luat_conf_bsp.h"

#if defined(LUAT_USE_PLCUI_LUATOS)

#include "luat_plcui.h"
#include "luat_fs.h"
#include "luat_image.h"
#include "luat_mem.h"
#include "lvgl9/src/draw/lv_image_decoder_private.h"
#include "lvgl9/src/misc/cache/instance/lv_image_cache.h"
#include "lvgl9/src/libs/lodepng/lodepng.h"
#include <stdio.h>
#include <string.h>

#define LUAT_LOG_TAG "plcui.image"
#include "luat_log.h"

static struct {
    lv_image_decoder_t *decoder;
    lv_image_decoder_t *jpg_sw;
    lv_image_decoder_t *png_sw;
    uint32_t hardware_count;
    uint32_t software_count;
} image_state;

static uint32_t be32(const uint8_t *p)
{
    return ((uint32_t)p[0] << 24) | ((uint32_t)p[1] << 16)
        | ((uint32_t)p[2] << 8) | p[3];
}

static int image_format(const char *path)
{
    const char *ext = path ? strrchr(path, '.') : NULL;
    if (!ext) return -1;
    if (!strcmp(ext, ".png") || !strcmp(ext, ".PNG")) return LUAT_IMG_FMT_PNG;
    if (!strcmp(ext, ".jpg") || !strcmp(ext, ".jpeg")
        || !strcmp(ext, ".JPG") || !strcmp(ext, ".JPEG")) return LUAT_IMG_FMT_JPG;
    return -1;
}

static lv_image_decoder_t *software_decoder(int format)
{
    return format == LUAT_IMG_FMT_PNG ? image_state.png_sw : image_state.jpg_sw;
}

static int read_aligned(const char *path, uint8_t **data, size_t *size)
{
    FILE *file = luat_fs_fopen(path, "rb");
    if (!file) return LUAT_IMG_ERR;
    /* Avoid another filename lookup/f_stat after fopen on FAT/LFN volumes. */
    if (luat_fs_fseek(file, 0, SEEK_END) != 0) {
        luat_fs_fclose(file);
        return LUAT_IMG_ERR;
    }
    long file_size = luat_fs_ftell(file);
    if (file_size <= 0 || (uint64_t)file_size > PLCUI_MAX_IMAGE_BYTES
        || luat_fs_fseek(file, 0, SEEK_SET) != 0) {
        luat_fs_fclose(file);
        return LUAT_IMG_ERR;
    }
    size_t length = (size_t)file_size;
    uint8_t *input = luat_heap_memalign(8, length);
    if (!input) {
        luat_fs_fclose(file);
        return LUAT_IMG_ERR_NOMEM;
    }
    size_t actual = luat_fs_fread(input, 1, length, file);
    int failed = luat_fs_ferror(file);
    luat_fs_fclose(file);
    if (actual != length || failed) {
        luat_heap_free(input);
        return LUAT_IMG_ERR;
    }
    *data = input;
    *size = length;
    return LUAT_IMG_OK;
}

/* Return -1 for malformed input, 0 for a software-only file, 1 for safe HW.
 * CRCs and complete chunk bounds are checked before exposing the HW parser.
 * All valid software-only PNGs retain alpha through LVGL's LodePNG adapter.
 */
static int png_hardware_safe(const uint8_t *data, size_t size, uint32_t width, uint32_t height)
{
    static const uint8_t signature[] = {137, 80, 78, 71, 13, 10, 26, 10};
    if (size < 33 || memcmp(data, signature, sizeof(signature))) return -1;
    size_t offset = 8;
    unsigned idat_count = 0;
    bool ihdr = false, iend = false, hardware = true;
    while (size - offset >= 12U) {
        uint32_t length = be32(data + offset);
        const uint8_t *type = data + offset + 4U;
        if ((size_t)length > size - offset - 12U) return -1;
        const uint8_t *payload = type + 4U;
        if (lodepng_crc32(type, (size_t)length + 4U) != be32(payload + length)) return -1;
        if (!memcmp(type, "IHDR", 4)) {
            if (ihdr || offset != 8U || length != 13U
                || be32(payload) != width || be32(payload + 4) != height) return -1;
            ihdr = true;
            /* Keep uncommon bit depths, indexed/greyscale and Adam7 in SW. */
            hardware = payload[8] == 8U && (payload[9] == 2U || payload[9] == 6U)
                && payload[10] == 0U && payload[11] == 0U && payload[12] == 0U;
        } else if (!memcmp(type, "IDAT", 4)) {
            if (!ihdr) return -1;
            idat_count++;
        } else if (!memcmp(type, "IEND", 4)) {
            if (length || !ihdr || !idat_count) return -1;
            iend = true;
            break;
        } else if (!memcmp(type, "tRNS", 4)) {
            /* A true-colour transparency key also needs software alpha. */
            hardware = false;
        }
        offset += (size_t)length + 12U;
    }
    if (!ihdr || !iend) return -1;
    return hardware && idat_count == 1U ? 1 : 0;
}

static bool contains_dhav(const uint8_t *data, size_t size)
{
    for (size_t i = 0; i + 4U <= size; ++i)
        if (!memcmp(data + i, "DHAV", 4)) return true;
    return false;
}

/* Match the AIRUI safety policy without keeping an AIRUI runtime context.
 * Baseline browser exports are the HW fast path. EXIF uses software so that
 * its orientation and the dimensions returned by HZJPEG stay consistent.
 */
static int jpg_hardware_safe(const uint8_t *data, size_t size, uint32_t width, uint32_t height)
{
    if (size < 4 || data[0] != 0xff || data[1] != 0xd8) return -1;
    bool baseline = false, hardware = true;
    size_t offset = 2;
    while (offset < size) {
        if (data[offset] != 0xff) return -1;
        while (offset < size && data[offset] == 0xff) offset++;
        if (offset >= size) return -1;
        uint8_t marker = data[offset++];
        if (marker == 0xda) return baseline ? (hardware ? 1 : 0) : 0;
        if (marker == 0xd9) return -1;
        if (marker == 0x01 || (marker >= 0xd0 && marker <= 0xd8)) continue;
        if (size - offset < 2U) return -1;
        size_t length = ((size_t)data[offset] << 8) | data[offset + 1U];
        if (length < 2U || length > size - offset) return -1;
        const uint8_t *payload = data + offset + 2U;
        size_t payload_size = length - 2U;
        if (marker == 0xc0) {
            if (payload_size < 6U || payload[0] != 8U) return -1;
            uint32_t h = ((uint32_t)payload[1] << 8) | payload[2];
            uint32_t w = ((uint32_t)payload[3] << 8) | payload[4];
            if (!w || !h) return -1;
            if (w != width || h != height) hardware = false;
            if (payload[5] != 1U && payload[5] != 3U) hardware = false;
#if !defined(LUAT_USE_PLCUI_JPG_HW_ANY_SIZE)
            if (w % 16U || h % 16U) hardware = false;
#endif
            baseline = true;
        } else if ((marker >= 0xc1 && marker <= 0xcf)
                   && marker != 0xc4 && marker != 0xc8 && marker != 0xcc) {
            hardware = false;
        }
        if (marker == 0xfe || (marker >= 0xe0 && marker <= 0xef)) {
            if (payload_size > 512U || contains_dhav(payload, payload_size)) hardware = false;
            if (marker == 0xe1 && payload_size >= 6U && !memcmp(payload, "Exif\0\0", 6U))
                hardware = false;
        }
        offset += length;
    }
    return -1;
}

static void make_room(lv_image_decoder_dsc_t *dsc, uint32_t bytes)
{
    if (dsc->args.no_cache || !dsc->cache || !lv_image_cache_is_enabled()) return;
    size_t maximum = lv_cache_get_max_size(dsc->cache, NULL);
    if (bytes > maximum) return;
    for (unsigned i = 0; i < 64U; ++i) {
        size_t used = lv_cache_get_size(dsc->cache, NULL);
        if (used <= maximum && bytes <= maximum - used) break;
        if (!lv_cache_evict_one(dsc->cache, NULL)) break;
    }
}

static lv_result_t finish_hardware(lv_image_decoder_t *decoder, lv_image_decoder_dsc_t *dsc,
                                   luat_img_info_t *image, lv_color_format_t format)
{
    uint32_t stride = (uint32_t)image->width * lv_color_format_get_size(format);
    lv_draw_buf_t *decoded = lv_malloc_zeroed(sizeof(*decoded));
    if (!decoded) {
        luat_heap_free(image->data);
        image->data = NULL;
        return LV_RESULT_INVALID;
    }
    if (lv_draw_buf_init(decoded, image->width, image->height, format,
                         stride, image->data, image->size) != LV_RESULT_OK) {
        lv_free(decoded);
        luat_heap_free(image->data);
        image->data = NULL;
        return LV_RESULT_INVALID;
    }
    image->data = NULL;
    decoded->handlers = lv_draw_buf_get_image_handlers();
    lv_draw_buf_set_flag(decoded, LV_IMAGE_FLAGS_ALLOCATED | LV_IMAGE_FLAGS_MODIFIABLE);
    dsc->header = decoded->header;
    lv_draw_buf_t *adjusted = lv_image_decoder_post_process(dsc, decoded);
    if (!adjusted) {
        lv_draw_buf_destroy(decoded);
        return LV_RESULT_INVALID;
    }
    if (adjusted != decoded) {
        lv_draw_buf_destroy(decoded);
        decoded = adjusted;
    }
    dsc->header = decoded->header;
    dsc->decoded = decoded;
    if (dsc->args.no_cache || !lv_image_cache_is_enabled()) return LV_RESULT_OK;
    lv_image_cache_data_t key;
    memset(&key, 0, sizeof(key));
    key.src_type = dsc->src_type;
    key.src = dsc->src;
    key.slot.size = decoded->data_size;
    dsc->cache_entry = lv_image_decoder_add_to_cache(decoder, &key, decoded, NULL);
    if (!dsc->cache_entry) {
        lv_draw_buf_destroy(decoded);
        dsc->decoded = NULL;
        return LV_RESULT_INVALID;
    }
    return LV_RESULT_OK;
}

static lv_result_t plcui_decoder_info(lv_image_decoder_t *decoder, lv_image_decoder_dsc_t *dsc,
                                     lv_image_header_t *header)
{
    (void)decoder;
    if (dsc->src_type != LV_IMAGE_SRC_FILE) return LV_RESULT_INVALID;
    int format = image_format(dsc->src);
    if (format < 0) return LV_RESULT_INVALID;
    lv_image_decoder_t *sw = software_decoder(format);
    if (!sw || !sw->info_cb || sw->info_cb(sw, dsc, header) != LV_RESULT_OK) return LV_RESULT_INVALID;
    uint64_t bytes = (uint64_t)header->w * header->h * 4U;
    if (!header->w || !header->h || bytes > PLCUI_MAX_IMAGE_BYTES || bytes > LV_CACHE_DEF_SIZE)
        return LV_RESULT_INVALID;
    return LV_RESULT_OK;
}

static lv_result_t software_open(lv_image_decoder_dsc_t *dsc, int format)
{
    lv_image_decoder_t *sw = software_decoder(format);
    if (!sw || !sw->open_cb) return LV_RESULT_INVALID;
    /* Invoke the registered codec directly, never the global open dispatcher.
     * Its cache entry and close callback then retain their native ownership.
     */
    dsc->decoder = sw;
    lv_result_t result = sw->open_cb(sw, dsc);
    if (result == LV_RESULT_OK) {
        image_state.software_count++;
        LLOGI("SW %s %ux%u src=%s", format == LUAT_IMG_FMT_PNG ? "PNG" : "JPG",
              (unsigned)dsc->header.w, (unsigned)dsc->header.h, (const char *)dsc->src);
    }
    return result;
}

static lv_result_t plcui_decoder_open(lv_image_decoder_t *decoder, lv_image_decoder_dsc_t *dsc)
{
    int format = dsc->src_type == LV_IMAGE_SRC_FILE ? image_format(dsc->src) : -1;
    if (format < 0) return LV_RESULT_INVALID;
    uint64_t pixel_bytes = (uint64_t)dsc->header.w * dsc->header.h
        * (format == LUAT_IMG_FMT_PNG ? 4U : 2U);
    if (!pixel_bytes || pixel_bytes > UINT32_MAX || pixel_bytes > LV_CACHE_DEF_SIZE)
        return LV_RESULT_INVALID;
    make_room(dsc, (uint32_t)pixel_bytes);
    uint8_t *input = NULL;
    size_t input_size = 0;
    int result = read_aligned(dsc->src, &input, &input_size);
    if (result != LUAT_IMG_OK) {
        LLOGE("input failed ret=%d src=%s", result, (const char *)dsc->src);
        return LV_RESULT_INVALID;
    }
    int safe = format == LUAT_IMG_FMT_PNG
        ? png_hardware_safe(input, input_size, dsc->header.w, dsc->header.h)
        : jpg_hardware_safe(input, input_size, dsc->header.w, dsc->header.h);
    if (safe <= 0) {
        luat_heap_free(input);
        if (safe < 0) {
            LLOGE("malformed image src=%s", (const char *)dsc->src);
            return LV_RESULT_INVALID;
        }
        return software_open(dsc, format);
    }
    luat_img_conf_t config;
    memset(&config, 0, sizeof(config));
    config.format = (luat_img_format_t)format;
    config.decode_mode = LUAT_IMG_DECODE_HW;
    config.source_path = dsc->src;
    luat_img_info_t image;
    memset(&image, 0, sizeof(image));
    result = luat_image_decode(&config, input, input_size, &image);
    /* Only unreferenced cache entries may be evicted, never during preflight. */
    for (unsigned retry = 0; result == LUAT_IMG_ERR_NOMEM && retry < 16U
         && !dsc->args.no_cache && dsc->cache && lv_image_cache_is_enabled(); ++retry) {
        if (!lv_cache_evict_one(dsc->cache, NULL)) break;
        result = luat_image_decode(&config, input, input_size, &image);
    }
    luat_heap_free(input);
    if (result != LUAT_IMG_OK || !image.data) {
        if (image.data) luat_heap_free(image.data);
        LLOGW("HW failed ret=%d src=%s", result, (const char *)dsc->src);
        /* PNG's generic HW error can mean OOM on older SDKs. Only the known
         * unsupported formats above are routed to SW; unknown PNG failures
         * stay failures. JPEG has a distinct NOMEM result and may fallback.
         */
        if (format == LUAT_IMG_FMT_JPG && result != LUAT_IMG_ERR_NOMEM)
            return software_open(dsc, format);
        return LV_RESULT_INVALID;
    }
    if (image.width != dsc->header.w || image.height != dsc->header.h
        || image.size != pixel_bytes) {
        luat_heap_free(image.data);
        return LV_RESULT_INVALID;
    }
    lv_color_format_t color = format == LUAT_IMG_FMT_PNG ? LV_COLOR_FORMAT_ARGB8888 : LV_COLOR_FORMAT_RGB565;
    lv_result_t opened = finish_hardware(decoder, dsc, &image, color);
    if (opened == LV_RESULT_OK) {
        image_state.hardware_count++;
        LLOGI("HW %s %ux%u cf=%d src=%s", format == LUAT_IMG_FMT_PNG ? "PNG" : "JPG",
              (unsigned)dsc->header.w, (unsigned)dsc->header.h, color, (const char *)dsc->src);
    }
    return opened;
}

static void plcui_decoder_close(lv_image_decoder_t *decoder, lv_image_decoder_dsc_t *dsc)
{
    (void)decoder;
    if (dsc->decoded && (dsc->args.no_cache || !lv_image_cache_is_enabled()))
        lv_draw_buf_destroy((lv_draw_buf_t *)dsc->decoded);
}

void plcui_platform_image_deinit(void)
{
    if (lv_is_initialized()) {
        lv_image_decoder_t *current = NULL;
        while ((current = lv_image_decoder_get_next(current)) != NULL) {
            if (current->info_cb == plcui_decoder_info) {
                /* No live PLCUI objects/decoder sessions remain at shutdown. */
                lv_image_cache_drop(NULL);
                lv_image_decoder_delete(current);
                break;
            }
        }
    }
    memset(&image_state, 0, sizeof(image_state));
}

int plcui_platform_image_init(void)
{
    if (!lv_is_initialized()) return -1;
    plcui_platform_image_deinit();
    lv_image_decoder_t *current = NULL;
    while ((current = lv_image_decoder_get_next(current)) != NULL) {
        if (current->name && !strcmp(current->name, "HZJPEG")) image_state.jpg_sw = current;
        if (current->name && !strcmp(current->name, "LODEPNG")) image_state.png_sw = current;
    }
    if (!image_state.jpg_sw || !image_state.png_sw) return -1;
    image_state.decoder = lv_image_decoder_create();
    if (!image_state.decoder) return -1;
    lv_image_decoder_set_info_cb(image_state.decoder, plcui_decoder_info);
    lv_image_decoder_set_open_cb(image_state.decoder, plcui_decoder_open);
    lv_image_decoder_set_close_cb(image_state.decoder, plcui_decoder_close);
    image_state.decoder->name = "PLCUI_LUATOS";
    return 0;
}

uint32_t plcui_platform_image_hw_count(void) { return image_state.hardware_count; }
uint32_t plcui_platform_image_sw_count(void) { return image_state.software_count; }

#endif
