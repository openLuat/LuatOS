
/*
@module  lcd
@summary lcd驱动模块 - WebP解码支持
@version 1.0
@date    2024.04.16
@tag LUAT_USE_WEBP
*/
#include "luat_base.h"
#include "luat_lcd.h"
#include "luat_mem.h"
#include "luat_fs.h"

#define LUAT_LOG_TAG "lcd.webp"
#include "luat_log.h"

extern luat_lcd_conf_t *lcd_dft_conf;
extern void lcd_auto_flush(luat_lcd_conf_t *conf);

#ifdef LUAT_USE_WEBP
#include "webp/decode.h"

/* Convert a single RGB888 pixel to RGB565 with optional byte-swap. */
static luat_color_t rgb888_to_color(luat_lcd_conf_t *conf,
                                    uint8_t r, uint8_t g, uint8_t b) {
    luat_color_t px = ((luat_color_t)(r >> 3) << 11)
                    | ((luat_color_t)(g >> 2) << 5)
                    | ((luat_color_t)(b >> 3));
    if (conf->endianness_swap)
        px = (luat_color_t)(((px >> 8) & 0xFF) | ((px << 8) & 0xFF00));
    return px;
}

int lcd_draw_webp_default(luat_lcd_conf_t *conf, const char *path,
                          int16_t x, int16_t y) {
    int ret = -1;
    FILE *fd = NULL;
    uint8_t *file_buf = NULL;
    uint8_t *rgb_buf = NULL;
    luat_color_t *row_buf = NULL;

    fd = luat_fs_fopen(path, "rb");
    if (fd == NULL) {
        LLOGW("no such file %s", path);
        goto cleanup;
    }

    /* Get file size */
    luat_fs_fseek(fd, 0, SEEK_END);
    long fsize = luat_fs_ftell(fd);
    luat_fs_fseek(fd, 0, SEEK_SET);
    if (fsize <= 0) {
        LLOGE("bad file size %s", path);
        goto cleanup;
    }

    file_buf = (uint8_t *)luat_heap_malloc((size_t)fsize);
    if (file_buf == NULL) {
        LLOGE("oom: file_buf %ld bytes", fsize);
        goto cleanup;
    }

    if ((long)luat_fs_fread(file_buf, 1, (size_t)fsize, fd) != fsize) {
        LLOGE("read error %s", path);
        goto cleanup;
    }
    luat_fs_fclose(fd);
    fd = NULL;

    /* Decode WebP → RGB888 */
    int out_w = 0, out_h = 0;
    rgb_buf = WebPDecodeRGB(file_buf, (size_t)fsize, &out_w, &out_h);
    luat_heap_free(file_buf);
    file_buf = NULL;

    if (rgb_buf == NULL || out_w <= 0 || out_h <= 0) {
        LLOGE("WebPDecodeRGB failed for %s", path);
        goto cleanup;
    }

    /* Allocate a single row of RGB565 pixels */
    row_buf = (luat_color_t *)luat_heap_malloc((size_t)out_w * sizeof(luat_color_t));
    if (row_buf == NULL) {
        LLOGE("oom: row_buf %d pixels", out_w);
        goto cleanup;
    }

    /* Convert and draw row by row to keep stack usage minimal */
    const uint8_t *src = rgb_buf;
    for (int row = 0; row < out_h; row++) {
        for (int col = 0; col < out_w; col++) {
            row_buf[col] = rgb888_to_color(conf, src[0], src[1], src[2]);
            src += 3;
        }
        luat_lcd_draw(conf,
                      (int16_t)(x + 0),    (int16_t)(y + row),
                      (int16_t)(x + out_w - 1), (int16_t)(y + row),
                      row_buf);
    }
    lcd_auto_flush(conf);
    ret = 0;

cleanup:
    if (fd)       luat_fs_fclose(fd);
    if (file_buf) luat_heap_free(file_buf);
    if (rgb_buf)  WebPFree(rgb_buf);
    if (row_buf)  luat_heap_free(row_buf);
    return ret;
}

int lcd_webp_info_default(luat_lcd_conf_t *conf, const char *path,
                          uint16_t *width, uint16_t *height) {
    (void)conf;
    int ret = -1;
    FILE *fd = NULL;
    /* WebPGetInfo only needs the file header, 32 bytes is plenty */
    uint8_t header[32];

    if (path == NULL || width == NULL || height == NULL)
        return -1;

    fd = luat_fs_fopen(path, "rb");
    if (fd == NULL) {
        LLOGW("no such file %s", path);
        return -1;
    }
    size_t n = luat_fs_fread(header, 1, sizeof(header), fd);
    luat_fs_fclose(fd);

    int w = 0, h = 0;
    if (WebPGetInfo(header, n, &w, &h) && w > 0 && h > 0) {
        *width  = (uint16_t)w;
        *height = (uint16_t)h;
        ret = 0;
    } else {
        LLOGW("WebPGetInfo failed for %s", path);
    }
    return ret;
}

int lcd_webp_decode_default(luat_lcd_conf_t *conf, const char *path,
                            luat_lcd_buff_info_t *buff_info) {
    int ret = -1;
    FILE *fd = NULL;
    uint8_t *file_buf = NULL;
    uint8_t *rgb_buf = NULL;

    fd = luat_fs_fopen(path, "rb");
    if (fd == NULL) {
        LLOGW("no such file %s", path);
        goto cleanup;
    }

    luat_fs_fseek(fd, 0, SEEK_END);
    long fsize = luat_fs_ftell(fd);
    luat_fs_fseek(fd, 0, SEEK_SET);
    if (fsize <= 0) {
        LLOGE("bad file size %s", path);
        goto cleanup;
    }

    file_buf = (uint8_t *)luat_heap_malloc((size_t)fsize);
    if (file_buf == NULL) {
        LLOGE("oom: file_buf %ld bytes", fsize);
        goto cleanup;
    }
    if ((long)luat_fs_fread(file_buf, 1, (size_t)fsize, fd) != fsize) {
        LLOGE("read error %s", path);
        goto cleanup;
    }
    luat_fs_fclose(fd);
    fd = NULL;

    int out_w = 0, out_h = 0;
    rgb_buf = WebPDecodeRGB(file_buf, (size_t)fsize, &out_w, &out_h);
    luat_heap_free(file_buf);
    file_buf = NULL;

    if (rgb_buf == NULL || out_w <= 0 || out_h <= 0) {
        LLOGE("WebPDecodeRGB failed for %s", path);
        goto cleanup;
    }

    buff_info->width  = (uint16_t)out_w;
    buff_info->height = (uint16_t)out_h;
    buff_info->len    = (size_t)out_w * (size_t)out_h * sizeof(luat_color_t);
    buff_info->buff   = (luat_color_t *)luat_heap_malloc(buff_info->len);
    if (buff_info->buff == NULL) {
        LLOGE("oom: image buff %u bytes", (unsigned)buff_info->len);
        goto cleanup;
    }

    /* Convert RGB888 → RGB565 into output buffer */
    const uint8_t *src = rgb_buf;
    luat_color_t  *dst = buff_info->buff;
    size_t npix = (size_t)out_w * (size_t)out_h;
    for (size_t i = 0; i < npix; i++) {
        *dst++ = rgb888_to_color(conf, src[0], src[1], src[2]);
        src += 3;
    }
    ret = 0;

cleanup:
    if (fd)       luat_fs_fclose(fd);
    if (file_buf) luat_heap_free(file_buf);
    if (rgb_buf)  WebPFree(rgb_buf);
    if (ret != 0 && buff_info->buff) {
        luat_heap_free(buff_info->buff);
        buff_info->buff = NULL;
    }
    return ret;
}

#else /* !LUAT_USE_WEBP */

int lcd_draw_webp_default(luat_lcd_conf_t *conf, const char *path,
                          int16_t x, int16_t y) {
    (void)conf; (void)path; (void)x; (void)y;
    return -1;
}

int lcd_webp_info_default(luat_lcd_conf_t *conf, const char *path,
                          uint16_t *width, uint16_t *height) {
    (void)conf; (void)path; (void)width; (void)height;
    return -1;
}

int lcd_webp_decode_default(luat_lcd_conf_t *conf, const char *path,
                            luat_lcd_buff_info_t *buff_info) {
    (void)conf; (void)path; (void)buff_info;
    return -1;
}

#endif /* LUAT_USE_WEBP */

LUAT_WEAK int lcd_draw_webp(luat_lcd_conf_t *conf, const char *path,
                            int16_t x, int16_t y) {
    return lcd_draw_webp_default(conf, path, x, y);
}

LUAT_WEAK int lcd_webp_info(luat_lcd_conf_t *conf, const char *path,
                            uint16_t *width, uint16_t *height) {
    return lcd_webp_info_default(conf, path, width, height);
}

LUAT_WEAK int lcd_webp_decode(luat_lcd_conf_t *conf, const char *path,
                              luat_lcd_buff_info_t *buff_info) {
    return lcd_webp_decode_default(conf, path, buff_info);
}
