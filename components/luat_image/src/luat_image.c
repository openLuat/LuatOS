#include "luat_base.h"
#include "luat_lcd.h"
#include "luat_mem.h"
#include "luat_image.h"

#define LUAT_LOG_TAG "image"
#include "luat_log.h"

/* jpeg decode */

#ifdef LUAT_USE_TJPGD
#include "tjpgd.h"
#include "tjpgdcnf.h"

#define N_BPP (3 - JD_FORMAT)

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

static int decode_out_func(JDEC* jd, void* bitmap, JRECT* rect){
    luat_img_info_t *img_info = (luat_img_info_t*)jd->device;
    uint16_t* tmp = (uint16_t*)bitmap;

    uint16_t idx = 0;
	for (size_t y = rect->top; y <= rect->bottom; y++){
        // 防止大图时 y*width 溢出 16bit，改用 size_t 计算偏移
        size_t offset = (size_t)y * img_info->width + rect->left;
		for (size_t x = rect->left; x <= rect->right; x++){
            img_info->data[offset] = tmp[idx];
			offset++;idx++;
		}
	}
	
    // LLOGD("jpeg seg %dx%d %dx%d", rect->left, rect->top, rect->right, rect->bottom);
    // LLOGD("jpeg seg size %d %d %d", rect->right - rect->left + 1, rect->bottom - rect->top + 1, (rect->right - rect->left + 1) * (rect->bottom - rect->top + 1));
    return 1;    /* Continue to decompress */
}

int luat_jpeg_decode_sw_default(uint8_t *in_buf, size_t in_len, luat_img_info_t* img_info){
    JRESULT res;
    JDEC jdec;
    void *work = NULL;
#if JD_FASTDECODE == 2
    size_t sz_work = 3500 * 3;
#else
    size_t sz_work = 3500;
#endif
    if (in_buf == NULL || in_len == 0 || img_info == NULL) {
        return -1;
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
    img_info->size = jdec.width * jdec.height * sizeof(luat_color_t);
    img_info->data = luat_heap_malloc(img_info->size);
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
    return 0;
error:
    if (work) {
        luat_heap_free(work);
    }
    if (img_info->data) {
        luat_heap_free(img_info->data);
        img_info->data = NULL;
    }
    return LUAT_IMG_ERR;
}
#else
int luat_jpeg_decode_sw_default(uint8_t *in_buf, size_t in_len, luat_img_info_t* img_info){
    return LUAT_IMG_ERR;
}
#endif

LUAT_WEAK int luat_jpeg_decode_sw(uint8_t *in_buf, size_t in_len, luat_img_info_t* img_info){
    return luat_jpeg_decode_sw_default(in_buf, in_len, img_info);
}

LUAT_WEAK int luat_jpeg_decode_hw(uint8_t *in_buf, size_t in_len, luat_img_info_t* img_info){
    return LUAT_IMG_ERR;
}

LUAT_WEAK int luat_image_decode(luat_img_conf_t* img_conf, uint8_t *in_buf, size_t size, luat_img_info_t* img_info){
    if (img_conf == NULL || in_buf == NULL || size == 0 || img_info == NULL) {
        return LUAT_IMG_ERR;
    }
    switch (img_conf->format){
    case LUAT_IMG_FMT_JPG:
        switch (img_conf->decode_mode) {
        case LUAT_IMG_DECODE_SW:
            return luat_jpeg_decode_sw(in_buf, size, img_info);
        case LUAT_IMG_DECODE_HW:
            return luat_jpeg_decode_hw(in_buf, size, img_info);
        }
        break;
    default:
        LLOGW("unsupported image format %d", img_conf->format);
        return LUAT_IMG_ERR;
    }
    return LUAT_IMG_ERR;
}
