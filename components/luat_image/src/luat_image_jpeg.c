#include "luat_base.h"
#include "luat_lcd.h"
#include "luat_mem.h"

#include "luat_image.h"

#define LUAT_LOG_TAG "image"
#include "luat_log.h"

#ifdef LUAT_USE_TJPGD
#include "tjpgd.h"
#include "tjpgdcnf.h"

typedef struct {
    const uint8_t *data;
    size_t len;
    size_t pos;
} mem_reader_t;

static unsigned int decode_mem_in_func(JDEC* jd, uint8_t* buff, unsigned int nbyte) {
    luat_img_info_t *img_info = (luat_img_info_t*)jd->device;
    mem_reader_t *reader = (mem_reader_t*)img_info->userdata;
    size_t available = reader->len - reader->pos;
    if ((size_t)nbyte > available) nbyte = (unsigned int)available;
    if (buff) {
        memcpy(buff, reader->data + reader->pos, nbyte);
    }
    reader->pos += nbyte;
    return nbyte;
}

static int decode_out_func(JDEC* jd, void* bitmap, JRECT* rect) {
    luat_img_info_t *img_info = (luat_img_info_t*)jd->device;
    luat_color_t *tmp = (luat_color_t*)bitmap;
    luat_color_t *out = (luat_color_t*)img_info->data;
    uint16_t idx = 0;
    for (size_t y = rect->top; y <= rect->bottom; y++) {
        size_t offset = (size_t)y * img_info->width + rect->left;
        for (size_t x = rect->left; x <= rect->right; x++) {
            out[offset] = tmp[idx];
            offset++;
            idx++;
        }
    }
    return 1;
}

int luat_jpeg_decode_sw_default(const luat_img_conf_t *img_conf, uint8_t *in_buf, size_t in_len, luat_img_info_t* img_info) {
    JRESULT res;
    JDEC jdec;
    void *work = NULL;
#if JD_FASTDECODE == 2
    size_t sz_work = 3500 * 3;
#else
    size_t sz_work = 3500;
#endif
    (void)img_conf;
    if (in_buf == NULL || in_len == 0 || img_info == NULL) {
        return LUAT_IMG_ERR;
    }
    mem_reader_t reader = {in_buf, in_len, 0};
    img_info->userdata = &reader;
    work = luat_heap_malloc(sz_work);
    if (work == NULL) {
        LLOGE("out of memory when malloc jpeg decode workbuff");
        goto error;
    }
    res = luat_jd_prepare(&jdec, decode_mem_in_func, work, sz_work, img_info);
    if (res != JDR_OK) {
        LLOGW("luat_jd_prepare mem error %d", res);
        goto error;
    }
    img_info->width = jdec.width;
    img_info->height = jdec.height;
    img_info->size = (uint32_t)jdec.width * jdec.height * sizeof(luat_color_t);
    img_info->data = (uint8_t*)luat_heap_malloc(img_info->size);
    if (img_info->data == NULL) {
        LLOGE("out of memory when malloc jpeg image buff");
        goto error;
    }
    res = luat_jd_decomp(&jdec, decode_out_func, 0);
    if (res != JDR_OK) {
        LLOGW("luat_jd_decomp mem error %d", res);
        goto error;
    }
    luat_heap_free(work);
    return LUAT_IMG_OK;
error:
    if (work) luat_heap_free(work);
    if (img_info->data) {
        luat_heap_free(img_info->data);
        img_info->data = NULL;
    }
    return LUAT_IMG_ERR;
}

const luat_img_decoder_opts_t jpeg_sw_decoder_opts = {
    .decode = luat_jpeg_decode_sw_default,
};
#endif /* LUAT_USE_TJPGD */

#ifdef LUAT_USE_JPG
LUAT_WEAK int luat_jpeg_decode_hw(const luat_img_conf_t *img_conf, uint8_t *in_buf, size_t in_len, luat_img_info_t* img_info) {
    luat_lcd_conf_t *lcd_conf;
    luat_lcd_buff_info_t buff_info = {0};
    int ret;

    (void)in_buf;
    (void)in_len;

    if (img_conf == NULL || img_conf->source_path == NULL || img_info == NULL) {
        return LUAT_IMG_ERR;
    }

    lcd_conf = luat_lcd_get_default();
    if (lcd_conf == NULL || lcd_conf->acc_hw_jpeg == 0) {
        return LUAT_IMG_ERR;
    }

    ret = lcd_jpeg_decode(lcd_conf, img_conf->source_path, &buff_info);
    if (ret != 0 || buff_info.buff == NULL || buff_info.width == 0 || buff_info.height == 0) {
        if (buff_info.buff != NULL) {
            luat_heap_free(buff_info.buff);
        }
        return LUAT_IMG_ERR;
    }

    img_info->width = (uint16_t)buff_info.width;
    img_info->height = (uint16_t)buff_info.height;
    img_info->size = (uint32_t)buff_info.len;
    img_info->data = (uint8_t *)buff_info.buff;
    return LUAT_IMG_OK;
}

const luat_img_decoder_opts_t jpeg_hw_decoder_opts = {
    .decode = luat_jpeg_decode_hw,
};
#endif /* LUAT_USE_JPG */
