
/*
@module  lcd
@summary lcd驱动模块
@version 1.0
@date    2021.06.16
@demo lcd
@tag LUAT_USE_LCD
*/
#include "luat_base.h"
#include "luat_lcd.h"
#include "luat_mem.h"
#include "luat_zbuff.h"
#include "luat_fs.h"
#include "luat_gpio.h"

#define LUAT_LOG_TAG "lcd"
#include "luat_log.h"

#include "u8g2.h"
#include "u8g2_luat_fonts.h"
#include "luat_u8g2.h"

#include "qrcodegen.h"

extern luat_color_t BACK_COLOR , FORE_COLOR ;

extern luat_lcd_conf_t *lcd_dft_conf;
extern void lcd_auto_flush(luat_lcd_conf_t *conf);

#ifdef LUAT_USE_TJPGD
#include "tjpgd.h"
#include "tjpgdcnf.h"

#define N_BPP (3 - JD_FORMAT)

/* Session identifier for input/output functions (name, members and usage are as user defined) */
typedef struct {
    FILE *fp;               /* Input stream */
    int x;
    int y;
    // int width;
    // int height;
    uint16_t buff[16*16];
} IODEV;

static unsigned int file_in_func (JDEC* jd, uint8_t* buff, unsigned int nbyte){
    IODEV *dev = (IODEV*)jd->device;   /* Device identifier for the session (5th argument of jd_prepare function) */
    if (buff) {
        /* Read bytes from input stream */
        return luat_fs_fread(buff, 1, nbyte, dev->fp);
    } else {
        /* Remove bytes from input stream */
        return luat_fs_fseek(dev->fp, nbyte, SEEK_CUR) ? 0 : nbyte;
    }
}

static int lcd_out_func (JDEC* jd, void* bitmap, JRECT* rect){
    IODEV *dev = (IODEV*)jd->device;
    uint16_t* tmp = (uint16_t*)bitmap;

    // rgb高低位swap
    uint16_t count = (rect->right - rect->left + 1) * (rect->bottom - rect->top + 1);
    for (size_t i = 0; i < count; i++){
        if (lcd_dft_conf->endianness_swap)
            dev->buff[i] = ((tmp[i] >> 8) & 0xFF)+ ((tmp[i] << 8) & 0xFF00);
        else
            dev->buff[i] = tmp[i];
    }
    
    // LLOGD("jpeg seg %dx%d %dx%d", rect->left, rect->top, rect->right, rect->bottom);
    // LLOGD("jpeg seg size %d %d %d", rect->right - rect->left + 1, rect->bottom - rect->top + 1, (rect->right - rect->left + 1) * (rect->bottom - rect->top + 1));
    luat_lcd_draw(lcd_dft_conf, dev->x + rect->left, dev->y + rect->top,
                                dev->x + rect->right, dev->y + rect->bottom,
                                dev->buff);
    return 1;    /* Continue to decompress */
}

int lcd_draw_jpeg_default(luat_lcd_conf_t* conf, const char* path, int16_t x, int16_t y){
    JRESULT res;      /* Result code of TJpgDec API */
    JDEC jdec;        /* Decompression object */
    void *work;       /* Pointer to the decompressor work area */
#if JD_FASTDECODE == 2
    size_t sz_work = 3500 * 3; /* Size of work area */
#else
    size_t sz_work = 3500; /* Size of work area */
#endif
    IODEV devid;      /* User defined device identifier */

    FILE* fd = luat_fs_fopen(path, "rb");
    if (fd == NULL) {
        LLOGW("no such file %s", path);
    return -1;
    }

    devid.fp = fd;
    work = luat_heap_malloc(sz_work);
    if (work == NULL) {
        LLOGE("out of memory when malloc jpeg decode workbuff");
        return -3;
    }
    res = jd_prepare(&jdec, file_in_func, work, sz_work, &devid);
    if (res != JDR_OK) {
        luat_heap_free(work);
        luat_fs_fclose(fd);
        LLOGW("jd_prepare file %s error %d", path, res);
        return -2;
    }
    devid.x = x;
    devid.y = y;
    // devid.width = jdec.width;
    // devid.height = jdec.height;
    res = jd_decomp(&jdec, lcd_out_func, 0);
    luat_heap_free(work);
    luat_fs_fclose(fd);
    if (res != JDR_OK) {
        LLOGW("jd_decomp file %s error %d", path, res);
        return -2;
    }else {
        lcd_auto_flush(lcd_dft_conf);
        return 0;
    }
}

static unsigned int decode_file_in_func (JDEC* jd, uint8_t* buff, unsigned int nbyte){
    luat_lcd_buff_info_t *buff_info = (luat_lcd_buff_info_t*)jd->device;   /* Device identifier for the session (5th argument of jd_prepare function) */
    if (buff) {
        /* Read bytes from input stream */
        return luat_fs_fread(buff, 1, nbyte, (FILE*)(buff_info->userdata));
    } else {
        /* Remove bytes from input stream */
        return luat_fs_fseek((FILE*)(buff_info->userdata), nbyte, SEEK_CUR) ? 0 : nbyte;
    }
}

static int decode_out_func (JDEC* jd, void* bitmap, JRECT* rect){
    luat_lcd_buff_info_t *buff_info = (luat_lcd_buff_info_t*)jd->device;
    uint16_t* tmp = (uint16_t*)bitmap;

    // rgb高低位swap
	uint16_t idx = 0;
	for (size_t y = rect->top; y <= rect->bottom; y++){
		uint16_t offset = y*buff_info->width + rect->left;
		for (size_t x = rect->left; x <= rect->right; x++){
			if (lcd_dft_conf->endianness_swap)
				buff_info->buff[offset] = ((tmp[idx] >> 8) & 0xFF)+ ((tmp[idx] << 8) & 0xFF00);
			else
				buff_info->buff[offset] = tmp[idx];
			offset++;idx++;
		}
	}
	
    // LLOGD("jpeg seg %dx%d %dx%d", rect->left, rect->top, rect->right, rect->bottom);
    // LLOGD("jpeg seg size %d %d %d", rect->right - rect->left + 1, rect->bottom - rect->top + 1, (rect->right - rect->left + 1) * (rect->bottom - rect->top + 1));
    return 1;    /* Continue to decompress */
}
int lcd_jpeg_decode_default(luat_lcd_conf_t* conf, const char* path, luat_lcd_buff_info_t* buff_info){
    JRESULT res;      /* Result code of TJpgDec API */
    JDEC jdec;        /* Decompression object */
    void *work = NULL;       /* Pointer to the decompressor work area */
#if JD_FASTDECODE == 2
    size_t sz_work = 3500 * 3; /* Size of work area */
#else
    size_t sz_work = 3500; /* Size of work area */
#endif
    FILE* fd = luat_fs_fopen(path, "rb");
    if (fd == NULL) {
        LLOGW("no such file %s", path);
		goto error;
    }
	buff_info->userdata = fd;
	work = luat_heap_malloc(sz_work);
	if (work == NULL) {
		LLOGE("out of memory when malloc jpeg decode workbuff");
		goto error;
	}
    res = jd_prepare(&jdec, decode_file_in_func, work, sz_work, buff_info);
    if (res != JDR_OK) {
        LLOGW("jd_prepare file %s error %d", path, res);
        goto error;
    }
    buff_info->width = jdec.width;
    buff_info->height = jdec.height;
	buff_info->len = jdec.width*jdec.height*sizeof(luat_color_t);
	buff_info->buff = luat_heap_malloc(buff_info->len);
    res = jd_decomp(&jdec, decode_out_func, 0);
    if (res != JDR_OK) {
        LLOGW("jd_decomp file %s error %d", path, res);
        goto error;
    }
    luat_heap_free(work);
    luat_fs_fclose(fd);
	return 0;
error:
	if (work){
		luat_heap_free(work);
	}
	if (fd){
		luat_fs_fclose(fd);
	}
	return -1;
}

LUAT_WEAK int lcd_draw_jpeg(luat_lcd_conf_t* conf, const char* path, int16_t x, int16_t y){
    return lcd_draw_jpeg_default(conf, path, x, y);
}

LUAT_WEAK int lcd_jpeg_decode(luat_lcd_conf_t* conf, const char* path, luat_lcd_buff_info_t* buff_info){
    return lcd_jpeg_decode_default(conf, path, buff_info);
}

#endif
