#include "luat_base.h"

#include "luat_lcd.h"
#include "luat_sdl2.h"
#include "luat_mem.h"

#include "lvgl.h"

static uint32_t* fb;

static inline uint32_t luat_color_565to8888(luat_color_t color);

static int sdl2_init(luat_lcd_conf_t* conf) {
    luat_sdl2_conf_t sdl2_conf = {
        .width = conf->w,
        .height = conf->h
    };
    luat_sdl2_init(&sdl2_conf);
    fb = luat_heap_malloc(sizeof(uint32_t) * conf->w * conf->h);
    luat_lcd_clear(conf, LCD_WHITE);
    // printf("ARGB8888 0xFFFF %08X\n", luat_color_565to8888(0xFFFF));
    // printf("ARGB8888 0X001F %08X\n", luat_color_565to8888(0X001F));
    // printf("ARGB8888 0xF800 %08X\n", luat_color_565to8888(0xF800));
    // printf("ARGB8888 0x0CE0 %08X\n", luat_color_565to8888(0x0CE0));
    return 0;
}

const luat_lcd_opts_t lcd_opts_sdl2 = {
    .name = "sdl2",
    .init = sdl2_init,
};

typedef struct luat_color_rgb565swap
{
    uint16_t blue : 5;
    uint16_t green : 6;
    uint16_t red : 5;
}luat_color_rgb565swap_t;

typedef struct luat_color_argb8888
{
    uint8_t blue;
    uint8_t green;
    uint8_t red;
    uint8_t alpha;
}luat_color_argb8888_t;


static inline uint32_t luat_color_565to8888(luat_color_t color) {
    luat_color_rgb565swap_t tmp;
    memcpy(&tmp, &color, sizeof(luat_color_rgb565swap_t));
    luat_color_argb8888_t dst = {
        .alpha = 0xFF,
        .red = (tmp.red * 263 + 7) >> 5,
        .green = (tmp.green * 259 + 3) >> 6,
        .blue = (tmp.blue *263  + 7) >> 5
    };
    uint32_t t;
    memcpy(&t, &dst, sizeof(luat_color_argb8888_t));
    //printf("ARGB8888 %08X\n", t);
    return t;
}

int luat_lcd_flush(luat_lcd_conf_t* conf) {
    if (!conf) {
        return 0;
    }
    if (conf->buff == NULL || conf->flush_y_max < conf->flush_y_min) {
        luat_sdl2_flush();
        return 0;
    }

    int16_t y_min = conf->flush_y_min < 0 ? 0 : conf->flush_y_min;
    int16_t y_max = conf->flush_y_max >= conf->h ? (conf->h - 1) : conf->flush_y_max;
    size_t width = conf->w;
    size_t height = y_max - y_min + 1;

    luat_color_t* src = conf->buff + y_min * conf->w;
    uint32_t* tmp = fb;
    for (size_t row = 0; row < height; row++) {
        for (size_t col = 0; col < width; col++) {
            tmp[row * width + col] = luat_color_565to8888(src[col]);
        }
        src += conf->w;
    }
    luat_sdl2_draw(0, y_min, conf->w - 1, y_max, fb);
    luat_sdl2_flush();

    conf->flush_y_max = 0;
    conf->flush_y_min = conf->h;
    return 0;
}

int luat_lcd_draw(luat_lcd_conf_t* conf, int16_t x1, int16_t y1, int16_t x2, int16_t y2, luat_color_t* color_p) {
    if (!conf) {
        return 0;
    }

    if (conf->buff) {
        int16_t src_w = x2 - x1 + 1;
        int16_t src_h = y2 - y1 + 1;
        if (src_w <= 0 || src_h <= 0) {
            return 0;
        }
        for (int16_t row = 0; row < src_h; row++) {
            int16_t dst_y = y1 + row;
            luat_color_t* src = color_p + row * src_w;
            if (dst_y < 0 || dst_y >= conf->h) {
                continue;
            }
            int16_t dst_x = x1;
            int16_t start_offset = 0;
            int16_t copy_len = src_w;
            if (dst_x < 0) {
                start_offset = -dst_x;
                copy_len -= start_offset;
                dst_x = 0;
            }
            if (dst_x + copy_len > conf->w) {
                copy_len = conf->w - dst_x;
            }
            if (copy_len <= 0) {
                continue;
            }
            luat_color_t* dst = conf->buff + dst_y * conf->w + dst_x;
            memcpy(dst, src + start_offset, copy_len * sizeof(luat_color_t));
        }
        if (y1 < conf->flush_y_min) {
            conf->flush_y_min = (y1 < 0) ? 0 : y1;
        }
        if (y2 > conf->flush_y_max) {
            conf->flush_y_max = (y2 >= conf->h) ? (conf->h - 1) : y2;
        }
        return 0;
    }

    size_t rw = x2 - x1 + 1;
    size_t rh = y2 - y1 + 1;

    uint32_t *tmp = fb;
    for (size_t i = 0; i < rh; i++)
    {
        for (size_t j = 0; j < rw; j++)
        {
            // 输入为 RGB565，SDL 纹理为 ARGB8888，这里做明确转换
            *tmp = luat_color_565to8888(*color_p);
            tmp ++;
            color_p ++;
        }
    }
    
    luat_sdl2_draw(x1, y1, x2, y2, fb);
    return 0;
}


