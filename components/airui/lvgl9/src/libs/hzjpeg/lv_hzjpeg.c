/**
 * @file lv_hzjpeg.c
 *
 */

/*********************
 *      INCLUDES
 *********************/

#include "../../draw/lv_image_decoder_private.h"
#include "../../../lvgl.h"
#if LV_USE_HZJPEG

#include "hz_tjpgd.h"
#include "lv_hzjpeg.h"
#include "../../core/lv_global.h"
#include "../../misc/lv_fs_private.h"

#ifdef __LUATOS__
#define LUAT_LOG_TAG "airui.jpg"
#include "luat_log.h"
#include "luat_image.h"
#include "luat_mcu.h"
#include "../../misc/cache/lv_cache.h"

static const char * airui_jpg_err_name(JRESULT rc)
{
    switch(rc) {
        case JDR_OK:   return "JDR_OK";
        case JDR_INTR: return "JDR_INTR";
        case JDR_INP:  return "JDR_INP";
        case JDR_MEM1: return "JDR_MEM1";
        case JDR_MEM2: return "JDR_MEM2";
        case JDR_PAR:  return "JDR_PAR";
        case JDR_FMT1: return "JDR_FMT1";
        case JDR_FMT2: return "JDR_FMT2";
        case JDR_FMT3: return "JDR_FMT3";
        default:       return "JDR_UNKNOWN";
    }
}

/** 将 tjpgd 错误码转为便于排查的中文说明 */
static const char * airui_jpg_err_hint(JRESULT rc)
{
    switch(rc) {
        case JDR_MEM1:
            return "解码内存池不足(检查 PSRAM/LVGL 堆剩余)";
        case JDR_MEM2:
            return "输入流缓冲不足(工作缓冲仅 4096 字节)";
        case JDR_INP:
            return "文件读取失败或 JPEG 数据流异常终止";
        case JDR_FMT1:
            return "JPEG 数据格式错误(文件可能已损坏)";
        case JDR_FMT2:
            return "JPEG 格式正确但不受当前解码器支持";
        case JDR_FMT3:
            return "不支持 Progressive JPEG，请转换为 Baseline JPEG";
        case JDR_PAR:
            return "解码参数错误";
        case JDR_INTR:
            return "输出回调中断解码";
        default:
            return "未知 JPEG 解码错误";
    }
}

static const char * airui_jpg_src_path(const lv_image_decoder_dsc_t * dsc)
{
    if(dsc != NULL && dsc->src_type == LV_IMAGE_SRC_FILE && dsc->src != NULL) {
        return (const char *)dsc->src;
    }
    return "<mem>";
}

static uint32_t airui_jpg_cache_max_bytes(void)
{
    lv_cache_t * cache = LV_GLOBAL_DEFAULT()->img_cache;
    if(cache == NULL) return 0;
    return (uint32_t)lv_cache_get_max_size(cache, NULL);
}

static uint32_t airui_jpg_rgb888_buf_size(uint32_t w, uint32_t h)
{
    return (uint32_t)w * h * 3U;
}
#endif

/*********************
 *      DEFINES
 *********************/

#define DECODER_NAME "HZJPEG"
#define HZJPEG_WORKBUFF_SIZE 4096
#define HZJPEG_SIGNATURE 0xFFD8FF
#define IS_JPEG_SIGNATURE(x) (((x) & 0x00FFFFFF) == HZJPEG_SIGNATURE)

#define image_cache_draw_buf_handlers &(LV_GLOBAL_DEFAULT()->image_cache_draw_buf_handlers)

/**********************
 *      TYPEDEFS
 **********************/

typedef struct {
    lv_fs_file_t * file;
    JDEC * jd;
    uint8_t * workbuf;
    lv_draw_buf_t * decoded;
    uint32_t orientation;
} hzjpeg_session_t;

/**********************
 *  STATIC PROTOTYPES
 **********************/

static lv_result_t decoder_info(lv_image_decoder_t * decoder, lv_image_decoder_dsc_t * dsc, lv_image_header_t * header);
static lv_result_t decoder_open(lv_image_decoder_t * decoder, lv_image_decoder_dsc_t * dsc);
static void decoder_close(lv_image_decoder_t * decoder, lv_image_decoder_dsc_t * dsc);
static size_t input_func(JDEC * jd, uint8_t * buff, size_t ndata);
static int output_func(JDEC * jd, void * bitmap, JRECT * rect);
static bool get_jpeg_head_info(lv_fs_file_t * file, uint32_t * width, uint32_t * height, uint32_t * orientation);
static bool get_jpeg_size(lv_fs_file_t * file, uint32_t * width, uint32_t * height);
static bool get_jpeg_direction(lv_fs_file_t * file, uint32_t * orientation);
static bool is_jpeg_file(lv_fs_file_t * file);
static void copy_block(hzjpeg_session_t * session, const uint8_t * src, const JRECT * rect);

/**********************
 *  STATIC VARIABLES
 **********************/

static const uint32_t jpeg_exif = 0x45786966;
static const uint16_t jpeg_big_endian_tag = 0x4d4d;
static const uint16_t jpeg_little_endian_tag = 0x4949;

/**********************
 *      MACROS
 **********************/

#define TRANS_32_VALUE(big_endian, data) big_endian ? \
    ((*(data) << 24) | (*((data) + 1) << 16) | (*((data) + 2) << 8) | *((data) + 3)) : \
    (*(data) | (*((data) + 1) << 8) | (*((data) + 2) << 16) | (*((data) + 3) << 24))

#define TRANS_16_VALUE(big_endian, data) big_endian ? \
    ((*(data) << 8) | *((data) + 1)) : (*(data) | (*((data) + 1) << 8))

/**********************
 *   GLOBAL FUNCTIONS
 **********************/

void lv_hzjpeg_init(void)
{
    lv_image_decoder_t * dec = lv_image_decoder_create();
    lv_image_decoder_set_info_cb(dec, decoder_info);
    lv_image_decoder_set_open_cb(dec, decoder_open);
    lv_image_decoder_set_close_cb(dec, decoder_close);

    dec->name = DECODER_NAME;
}

void lv_hzjpeg_deinit(void)
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

static lv_result_t decoder_info(lv_image_decoder_t * decoder, lv_image_decoder_dsc_t * dsc, lv_image_header_t * header)
{
    LV_UNUSED(decoder);

    if(dsc->src_type != LV_IMAGE_SRC_FILE) {
#ifdef __LUATOS__
        LLOGE("probe fail: 仅支持文件路径 JPG, type=%d", (int)dsc->src_type);
#endif
        return LV_RESULT_INVALID;
    }

    const char * src = dsc->src;
    const char * ext = lv_fs_get_ext(src);
    bool is_jpeg_ext = (lv_strcmp(ext, "jpg") == 0) || (lv_strcmp(ext, "jpeg") == 0);
    if(!is_jpeg_ext) {
#ifdef __LUATOS__
        LLOGE("probe fail: 扩展名不是 jpg/jpeg src=%s ext=%s", src, ext ? ext : "?");
#endif
        return LV_RESULT_INVALID;
    }

    if(!is_jpeg_file(&dsc->file)) {
#ifdef __LUATOS__
        LLOGE("probe fail: 非 JPEG 文件(魔数不匹配) src=%s", src);
#endif
        return LV_RESULT_INVALID;
    }

    uint32_t width = 0;
    uint32_t height = 0;
    uint32_t orientation = 0;
    if(!get_jpeg_head_info(&dsc->file, &width, &height, &orientation)) {
#ifdef __LUATOS__
        LLOGE("probe fail: 无法解析 JPEG 头信息 src=%s", src);
#endif
        return LV_RESULT_INVALID;
    }

    header->cf = LV_COLOR_FORMAT_RGB888;
    header->w = (orientation % 180U) ? height : width;
    header->h = (orientation % 180U) ? width : height;
    header->stride = lv_draw_buf_width_to_stride(header->w, header->cf);

    return LV_RESULT_OK;
}

static lv_result_t decoder_open(lv_image_decoder_t * decoder, lv_image_decoder_dsc_t * dsc)
{
    LV_UNUSED(decoder);

    if(dsc->src_type != LV_IMAGE_SRC_FILE) {
#ifdef __LUATOS__
        LLOGE("open fail: 仅支持文件路径 JPG, type=%d", (int)dsc->src_type);
#endif
        return LV_RESULT_INVALID;
    }

    const char * fn = dsc->src;
    lv_fs_file_t * file = lv_malloc(sizeof(lv_fs_file_t));
    hzjpeg_session_t * session = lv_malloc_zeroed(sizeof(hzjpeg_session_t));
    JDEC * jd = lv_malloc(sizeof(JDEC));
    uint8_t * workbuf = lv_malloc(HZJPEG_WORKBUFF_SIZE);
    lv_draw_buf_t * decoded = NULL;
    lv_draw_buf_t * adjusted = NULL;
    bool file_opened = false;
    JRESULT rc = JDR_OK;
    uint32_t out_w = 0;
    uint32_t out_h = 0;

    if(file == NULL || session == NULL || jd == NULL || workbuf == NULL) {
#ifdef __LUATOS__
        LLOGE("open fail: 会话资源分配失败 src=%s file=%p session=%p jd=%p workbuf=%p",
              fn, (void *)file, (void *)session, (void *)jd, (void *)workbuf);
#endif
        goto failed;
    }

    if(lv_fs_open(file, fn, LV_FS_MODE_RD) != LV_FS_RES_OK) {
#ifdef __LUATOS__
        LLOGE("open fail: 无法打开 JPG 文件 src=%s", fn);
#endif
        goto failed;
    }
    file_opened = true;

    session->file = file;
    session->jd = jd;
    session->workbuf = workbuf;

    if(!get_jpeg_direction(file, &session->orientation)) {
        session->orientation = 0;
    }

    if(lv_fs_seek(file, 0, LV_FS_SEEK_SET) != LV_FS_RES_OK) {
#ifdef __LUATOS__
        LLOGE("open fail: 文件 seek 失败 src=%s", fn);
#endif
        goto failed;
    }

    rc = jd_prepare(jd, input_func, workbuf, HZJPEG_WORKBUFF_SIZE, session);
    if(rc != JDR_OK) {
#ifdef __LUATOS__
        LLOGE("open fail: jd_prepare err=%d (%s) hint=%s src=%s",
              (int)rc, airui_jpg_err_name(rc), airui_jpg_err_hint(rc), fn);
#endif
        if(rc == JDR_FMT3) {
            LV_LOG_WARN("progressive JPEG is not supported: %s", fn);
        }
        goto failed;
    }

    out_w = (session->orientation % 180U) ? jd->height : jd->width;
    out_h = (session->orientation % 180U) ? jd->width : jd->height;
    decoded = lv_draw_buf_create_ex(image_cache_draw_buf_handlers, out_w, out_h, LV_COLOR_FORMAT_RGB888, LV_STRIDE_AUTO);
    if(decoded == NULL) {
#ifdef __LUATOS__
        LLOGE("open fail: 像素缓冲分配失败 src=%s %ux%u need_buf=%u (RGB888, w*h*3)",
              fn, (unsigned)out_w, (unsigned)out_h, airui_jpg_rgb888_buf_size(out_w, out_h));
#endif
        goto failed;
    }

    session->decoded = decoded;

#ifdef __LUATOS__
    uint64_t _airui_dbg_t0 = 0;
    if (luat_image_get_debug()) {
        _airui_dbg_t0 = luat_mcu_tick64();
    }
#endif

    rc = jd_decomp(jd, output_func, 0);

#ifdef __LUATOS__
    if (luat_image_get_debug()) {
        uint64_t _elapsed = luat_mcu_tick64() - _airui_dbg_t0;
        int _period = luat_mcu_us_period();
        uint32_t _elapsed_us = (_period > 0) ? (uint32_t)(_elapsed / (uint64_t)_period) : (uint32_t)(_elapsed / 1000ULL);
        LLOGI("decode %dx%d cost=%u.%03ums src=%s",
              jd->width, jd->height,
              _elapsed_us / 1000U, _elapsed_us % 1000U,
              fn);
    }
#endif
    if(rc != JDR_OK) {
#ifdef __LUATOS__
        LLOGE("decode fail: jd_decomp err=%d (%s) hint=%s src=%s raw=%ux%u out=%ux%u",
              (int)rc, airui_jpg_err_name(rc), airui_jpg_err_hint(rc), fn,
              (unsigned)jd->width, (unsigned)jd->height, (unsigned)out_w, (unsigned)out_h);
#endif
        goto failed;
    }

    adjusted = lv_image_decoder_post_process(dsc, decoded);
    if(adjusted == NULL) {
#ifdef __LUATOS__
        LLOGE("open fail: 解码后处理失败(步幅对齐/预乘 alpha 可能 OOM) src=%s %ux%u data_size=%u",
              fn, (unsigned)out_w, (unsigned)out_h, (unsigned)decoded->data_size);
#endif
        goto failed;
    }

    if(adjusted != decoded) {
        lv_draw_buf_destroy(decoded);
        decoded = adjusted;
        session->decoded = decoded;
    }

    dsc->decoded = decoded;
    dsc->header = decoded->header;
    dsc->user_data = session;

    if(dsc->args.no_cache) {
        return LV_RESULT_OK;
    }

    if(!lv_image_cache_is_enabled()) {
        return LV_RESULT_OK;
    }

    lv_image_cache_data_t search_key;
    search_key.src_type = dsc->src_type;
    search_key.src = dsc->src;
    search_key.slot.size = decoded->data_size;

    lv_cache_entry_t * entry = lv_image_decoder_add_to_cache(decoder, &search_key, decoded, NULL);
    if(entry == NULL) {
#ifdef __LUATOS__
        LLOGE("open fail: 写入图片缓存失败 src=%s data_size=%u cache_max=%u "
              "(解码结果大于缓存上限时会被拒绝，或缓存驱逐失败)",
              fn, (unsigned)decoded->data_size, airui_jpg_cache_max_bytes());
#endif
        goto failed;
    }

    dsc->cache_entry = entry;
    return LV_RESULT_OK;

failed:
    if(adjusted != NULL && adjusted != decoded) {
        lv_draw_buf_destroy(adjusted);
    }
    if(decoded != NULL) {
        lv_draw_buf_destroy(decoded);
    }
    if(file_opened && file != NULL) {
        lv_fs_close(file);
    }
    lv_free(file);
    lv_free(workbuf);
    lv_free(jd);
    lv_free(session);
    return LV_RESULT_INVALID;
}

static void decoder_close(lv_image_decoder_t * decoder, lv_image_decoder_dsc_t * dsc)
{
    LV_UNUSED(decoder);

    hzjpeg_session_t * session = dsc->user_data;
    if(session == NULL) {
        return;
    }

    if(session->file != NULL) {
        lv_fs_close(session->file);
        lv_free(session->file);
    }

    lv_free(session->workbuf);
    lv_free(session->jd);
    lv_free(session);

    if(dsc->args.no_cache || !lv_image_cache_is_enabled()) {
        lv_draw_buf_destroy((lv_draw_buf_t *)dsc->decoded);
    }
}

static size_t input_func(JDEC * jd, uint8_t * buff, size_t ndata)
{
    hzjpeg_session_t * session = jd->device;
    if(session == NULL || session->file == NULL) {
        return 0;
    }

    if(buff != NULL) {
        uint32_t rn = 0;
        lv_fs_read(session->file, buff, (uint32_t)ndata, &rn);
        return rn;
    }

    uint32_t pos = 0;
    lv_fs_tell(session->file, &pos);
    if(lv_fs_seek(session->file, (uint32_t)(pos + ndata), LV_FS_SEEK_SET) != LV_FS_RES_OK) {
        return 0;
    }

    return ndata;
}

static int output_func(JDEC * jd, void * bitmap, JRECT * rect)
{
    hzjpeg_session_t * session = jd->device;
    if(session == NULL || bitmap == NULL || rect == NULL) {
        return 0;
    }

    copy_block(session, bitmap, rect);
    return 1;
}

static bool get_jpeg_head_info(lv_fs_file_t * file, uint32_t * width, uint32_t * height, uint32_t * orientation)
{
    if(!get_jpeg_size(file, width, height)) {
        return false;
    }

    if(!get_jpeg_direction(file, orientation)) {
        *orientation = 0;
    }

    if(lv_fs_seek(file, 0, LV_FS_SEEK_SET) != LV_FS_RES_OK) {
        return false;
    }

    return true;
}

static bool get_jpeg_size(lv_fs_file_t * file, uint32_t * width, uint32_t * height)
{
    uint8_t workbuf[HZJPEG_WORKBUFF_SIZE];
    JDEC jd;
    hzjpeg_session_t session;

    lv_memzero(&session, sizeof(session));
    session.file = file;

    if(lv_fs_seek(file, 0, LV_FS_SEEK_SET) != LV_FS_RES_OK) {
        return false;
    }

    if(jd_prepare(&jd, input_func, workbuf, sizeof(workbuf), &session) != JDR_OK) {
        return false;
    }

    *width = jd.width;
    *height = jd.height;
    return true;
}

static bool get_jpeg_direction(lv_fs_file_t * file, uint32_t * orientation)
{
    uint8_t marker_buf[2];
    uint8_t length_buf[2];

    *orientation = 0;

    if(lv_fs_seek(file, 0, LV_FS_SEEK_SET) != LV_FS_RES_OK) {
        return false;
    }

    uint32_t rn = 0;
    if(lv_fs_read(file, marker_buf, 2, &rn) != LV_FS_RES_OK || rn != 2) {
        return false;
    }

    if(marker_buf[0] != 0xFF || marker_buf[1] != 0xD8) {
        return false;
    }

    while(true) {
        if(lv_fs_read(file, marker_buf, 2, &rn) != LV_FS_RES_OK || rn != 2) {
            return false;
        }

        while(marker_buf[0] == 0xFF && marker_buf[1] == 0xFF) {
            marker_buf[0] = marker_buf[1];
            if(lv_fs_read(file, &marker_buf[1], 1, &rn) != LV_FS_RES_OK || rn != 1) {
                return false;
            }
        }

        if(marker_buf[0] != 0xFF) {
            return false;
        }

        if(marker_buf[1] == 0xDA || marker_buf[1] == 0xD9) {
            break;
        }

        if(lv_fs_read(file, length_buf, 2, &rn) != LV_FS_RES_OK || rn != 2) {
            return false;
        }

        uint32_t seg_len = ((uint32_t)length_buf[0] << 8) | length_buf[1];
        if(seg_len < 2) {
            return false;
        }
        seg_len -= 2;

        if(marker_buf[1] == 0xE1) {
            uint8_t * app1 = lv_malloc(seg_len);
            if(app1 == NULL) {
                return false;
            }

            bool ok = false;
            if(lv_fs_read(file, app1, seg_len, &rn) == LV_FS_RES_OK && rn == seg_len) {
                if(seg_len >= 14 && TRANS_32_VALUE(true, app1) == jpeg_exif) {
                    uint16_t endian_tag = TRANS_16_VALUE(true, app1 + 6);
                    bool is_big_endian = (endian_tag == jpeg_big_endian_tag);
                    if(is_big_endian || endian_tag == jpeg_little_endian_tag) {
                        uint32_t offset = TRANS_32_VALUE(is_big_endian, app1 + 10);
                        while(offset != 0) {
                            uint32_t entry_offset = 6 + offset + 2;
                            if(entry_offset > seg_len) {
                                break;
                            }
                            uint8_t * ifd = app1 + entry_offset;
                            uint16_t num_entries = TRANS_16_VALUE(is_big_endian, ifd - 2);
                            if(entry_offset + num_entries * 12 > seg_len) {
                                break;
                            }

                            for(uint16_t i = 0; i < num_entries; i++) {
                                uint16_t tag = TRANS_16_VALUE(is_big_endian, ifd);
                                if(tag == 0x0112) {
                                    uint16_t dir = TRANS_16_VALUE(is_big_endian, ifd + 8);
                                    switch(dir) {
                                        case 3:
                                            *orientation = 180;
                                            break;
                                        case 6:
                                            *orientation = 90;
                                            break;
                                        case 8:
                                            *orientation = 270;
                                            break;
                                        default:
                                            *orientation = 0;
                                            break;
                                    }
                                    ok = true;
                                    break;
                                }
                                ifd += 12;
                            }

                            if(ok) {
                                break;
                            }

                            if(entry_offset + num_entries * 12 + 4 > seg_len) {
                                break;
                            }
                            offset = TRANS_32_VALUE(is_big_endian, ifd);
                        }
                    }
                }
            }

            lv_free(app1);
            if(ok) {
                break;
            }
        }
        else if(lv_fs_seek(file, seg_len, LV_FS_SEEK_CUR) != LV_FS_RES_OK) {
            return false;
        }
    }

    if(lv_fs_seek(file, 0, LV_FS_SEEK_SET) != LV_FS_RES_OK) {
        return false;
    }

    return true;
}

static bool is_jpeg_file(lv_fs_file_t * file)
{
    uint32_t signature = 0;
    uint32_t rn = 0;
    if(lv_fs_seek(file, 0, LV_FS_SEEK_SET) != LV_FS_RES_OK) {
        return false;
    }

    if(lv_fs_read(file, &signature, sizeof(signature), &rn) != LV_FS_RES_OK || rn != sizeof(signature)) {
        return false;
    }

    return IS_JPEG_SIGNATURE(signature);
}

static void copy_block(hzjpeg_session_t * session, const uint8_t * src, const JRECT * rect)
{
    lv_draw_buf_t * decoded = session->decoded;
    uint8_t * dst_buf = decoded->data;
    uint32_t block_w = rect->right - rect->left + 1U;
    uint32_t block_h = rect->bottom - rect->top + 1U;
    uint32_t src_stride = block_w * 3U;

    for(uint32_t y = 0; y < block_h; y++) {
        for(uint32_t x = 0; x < block_w; x++) {
            uint32_t src_index = y * src_stride + x * 3U;
            uint32_t dst_x;
            uint32_t dst_y;

            switch(session->orientation) {
                case 90:
                    dst_x = decoded->header.w - (rect->top + y) - 1U;
                    dst_y = rect->left + x;
                    break;
                case 180:
                    dst_x = decoded->header.w - (rect->left + x) - 1U;
                    dst_y = decoded->header.h - (rect->top + y) - 1U;
                    break;
                case 270:
                    dst_x = rect->top + y;
                    dst_y = decoded->header.h - (rect->left + x) - 1U;
                    break;
                default:
                    dst_x = rect->left + x;
                    dst_y = rect->top + y;
                    break;
            }

            uint32_t dst_index = dst_y * decoded->header.stride + dst_x * 3U;
            dst_buf[dst_index + 0] = src[src_index + 0];
            dst_buf[dst_index + 1] = src[src_index + 1];
            dst_buf[dst_index + 2] = src[src_index + 2];
        }
    }
}

#endif /*LV_USE_HZJPEG*/
