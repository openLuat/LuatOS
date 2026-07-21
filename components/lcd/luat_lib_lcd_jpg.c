
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
#include "luat_image.h"

#define LUAT_LOG_TAG "lcd"
#include "luat_log.h"

extern luat_lcd_conf_t *lcd_dft_conf;
extern void lcd_auto_flush(luat_lcd_conf_t *conf);

/* 把 conf->acc_hw (位域联合体，bit0 = acc_hw_jpeg，0xFF = LUAT_LCD_ACC_HW_ALL)
 * 映射为 luat_image 的解码模式。
 * 与 l_lcd_set_acc_hw (luat_lib_lcd.c) 保持一致语义。 */
static luat_img_decode_mode_t jpeg_pick_mode(luat_lcd_conf_t *conf) {
    if (conf == NULL) return LUAT_IMG_DECODE_SW;
    if (conf->acc_hw == LUAT_LCD_ACC_HW_ALL) return LUAT_IMG_DECODE_HW;
    if (conf->acc_hw_jpeg)                   return LUAT_IMG_DECODE_HW;
    return LUAT_IMG_DECODE_SW;
}

/* 单行像素按 lcd_dft_conf->endianness_swap 做字节交换。
 * luat_image 输出的 luat_color_t 大端排列 (RGB565 BE)，
 * 与原 lcd_out_func 中按 lcd_dft_conf->endianness_swap 交换的语义一致。 */
static inline luat_color_t jpeg_pixel_swap(luat_color_t px, uint8_t swap) {
    if (!swap) return px;
#if (LUAT_LCD_COLOR_DEPTH == 16)
    return (luat_color_t)(((px >> 8) & 0xFF) | ((px << 8) & 0xFF00));
#else
    return px;
#endif
}

// 获取 JPG 图片信息
int lcd_jpeg_info_default(luat_lcd_conf_t* conf, const char* path, uint16_t *width, uint16_t *height){
    luat_img_conf_t img_conf;
    luat_img_info_t img_info;
    int ret;

    if (path == NULL || width == NULL || height == NULL) {
        return -1;
    }

    memset(&img_conf, 0, sizeof(img_conf));
    img_conf.format = LUAT_IMG_FMT_JPG;
    img_conf.decode_mode = jpeg_pick_mode(conf);
    img_conf.source_path = path;

    memset(&img_info, 0, sizeof(img_info));
    ret = luat_image_probe(&img_conf, NULL, 0, &img_info);
    if (ret != LUAT_IMG_OK || img_info.width == 0 || img_info.height == 0) {
        LLOGW("luat_image_probe file %s error %d", path, ret);
        return -1;
    }

    *width  = img_info.width;
    *height = img_info.height;
    return 0;
}

int lcd_draw_jpeg_default(luat_lcd_conf_t* conf, const char* path, int16_t x, int16_t y){
    luat_img_conf_t img_conf;
    luat_img_info_t img_info;
    int ret;
    luat_color_t *row_buf = NULL;
    uint8_t swap;

    memset(&img_conf, 0, sizeof(img_conf));
    img_conf.format = LUAT_IMG_FMT_JPG;
    img_conf.decode_mode = jpeg_pick_mode(conf);
    img_conf.source_path = path;

    memset(&img_info, 0, sizeof(img_info));
    ret = luat_image_decode(&img_conf, NULL, 0, &img_info);
    if (ret != LUAT_IMG_OK || img_info.data == NULL ||
        img_info.width == 0 || img_info.height == 0) {
        LLOGW("luat_image_decode file %s error %d", path, ret);
        if (img_info.data) luat_heap_free(img_info.data);
        return -2;
    }

    /* 行缓冲：16 行一带，匹配原 TJpgD 16x16 MCU 块的刷新粒度。 */
    row_buf = (luat_color_t *)luat_heap_malloc(
        (size_t)img_info.width * 16 * sizeof(luat_color_t));
    if (row_buf == NULL) {
        LLOGE("out of memory when malloc jpeg row buff");
        luat_heap_free(img_info.data);
        return -3;
    }

    swap = lcd_dft_conf ? lcd_dft_conf->endianness_swap : 0;
    {
        uint16_t w = img_info.width;
        uint16_t h = img_info.height;
        const luat_color_t *src = (const luat_color_t *)img_info.data;
        for (uint16_t row = 0; row < h; row += 16) {
            uint16_t band = (h - row) > 16 ? 16 : (uint16_t)(h - row);
            for (uint16_t r = 0; r < band; r++) {
                luat_color_t *dst = row_buf + (size_t)r * w;
                const luat_color_t *srow = src + (size_t)(row + r) * w;
                for (uint16_t c = 0; c < w; c++) {
                    dst[c] = jpeg_pixel_swap(srow[c], swap);
                }
            }
            luat_lcd_draw(conf, x, (int16_t)(y + row),
                              (int16_t)(x + w - 1), (int16_t)(y + row + band - 1),
                              row_buf);
        }
    }
    luat_heap_free(row_buf);
    luat_heap_free(img_info.data);
    lcd_auto_flush(conf);
    return 0;
}

int lcd_jpeg_decode_default(luat_lcd_conf_t* conf, const char* path, luat_lcd_buff_info_t* buff_info){
    luat_img_conf_t img_conf;
    luat_img_info_t img_info;
    int ret;

    if (buff_info == NULL) {
        return -1;
    }
    memset(buff_info, 0, sizeof(*buff_info));

    memset(&img_conf, 0, sizeof(img_conf));
    img_conf.format = LUAT_IMG_FMT_JPG;
    img_conf.decode_mode = jpeg_pick_mode(conf);
    img_conf.source_path = path;

    memset(&img_info, 0, sizeof(img_info));
    ret = luat_image_decode(&img_conf, NULL, 0, &img_info);
    if (ret != LUAT_IMG_OK || img_info.data == NULL ||
        img_info.width == 0 || img_info.height == 0) {
        LLOGW("luat_image_decode file %s error %d", path, ret);
        if (img_info.data) luat_heap_free(img_info.data);
        return -1;
    }

    /* 把所有权转交给 buff_info。lcd.image2raw 会把它装进 zbuff userdata，
     * 后续由 Lua 端按 zbuff 生命周期负责释放。 */
    buff_info->buff   = (luat_color_t *)img_info.data;
    buff_info->width  = img_info.width;
    buff_info->height = img_info.height;
    buff_info->len    = img_info.size;
    return 0;
}



LUAT_WEAK int lcd_draw_jpeg(luat_lcd_conf_t* conf, const char* path, int16_t x, int16_t y){
    return lcd_draw_jpeg_default(conf, path, x, y);
}

LUAT_WEAK int lcd_jpeg_info(luat_lcd_conf_t* conf, const char* path, uint16_t *width, uint16_t *height){
    return lcd_jpeg_info_default(conf, path, width, height);
}

LUAT_WEAK int lcd_jpeg_decode(luat_lcd_conf_t* conf, const char* path, luat_lcd_buff_info_t* buff_info){
    return lcd_jpeg_decode_default(conf, path, buff_info);
}


