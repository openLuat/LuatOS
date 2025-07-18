#include "luat_lvgl_fonts.h"

#ifdef LUAT_USE_GTFONT

#include "luat_gtfont.h"

#define LUAT_LOG_TAG "lvgl_gtfont"
#include "luat_log.h"

typedef struct{
    uint8_t sty_zh;
    uint8_t sty_en;
    uint16_t size;
    uint16_t bpp;
    uint16_t thickness;
    uint16_t code;
    uint32_t dot;
    unsigned char buf[0];
} gt_font_param_t;

static void gt_font_get(gt_font_param_t *param, uint16_t code) {
    if (param->code == code) return;

    uint8_t sty = param->sty_zh;
    if (code >= 0x20 && code <= 0x7e)
        sty = param->sty_en;

    memset(param->buf, 0, param->size * param->bpp * param->size * param->bpp);

    uint32_t dot = get_font(param->buf, sty, code, param->size * param->bpp, param->size * param->bpp, param->thickness);

    param->code = code;
    param->dot = dot / param->bpp;

    Gray_Process(param->buf, param->dot, param->size, param->bpp);
    // LLOGD("dot:%d param->dot:%d aram->size:%d param->bpp:%d",dot,param->dot,param->size, param->bpp);
}

static int get_font_adv_w(uint8_t *buf, int width, int height, int bpp) {
    uint8_t *p = buf;
    uint16_t w = width, h = height;
    uint32_t i = 0, j = 0, x = 0, y = 0;
    uint8_t c, c_bits;
    uint32_t t = (w + 7) / 8 * bpp;
    uint32_t adv_w = 0;
    uint32_t cur_w = 0;

    for (i = 0; i < (t * h); i++) {
        c = *p++;
        for (j = 0; j < (8 / bpp); j++) {
            c_bits = (c >> (((8 / bpp) - 1 - j) * bpp)) & (0xff >> (8 - bpp));
            if (x < w && c_bits != 0) {
                cur_w = x;
            }
            x++;
            if(x >= ((w + 7) / 8 * 8)) {
                if (cur_w > adv_w)
                    adv_w = cur_w;
                x = 0;
                y++;
            }
        }
    }
    return adv_w + 1;
}

static inline uint16_t gt_font_get_adv_w(gt_font_param_t *param, uint16_t code) {
    uint16_t adv_w = param->size;
    gt_font_get(param, code);
    if (code >= 0x21 && code <= 0x7e) {
        adv_w = get_font_adv_w(param->buf, param->dot, param->size, param->bpp);
    } else if (code == 0x20) {
        adv_w = param->size / 2;
    }
    return adv_w;
}

static bool gt_font_get_glyph_dsc(const struct _lv_font_struct *font, lv_font_glyph_dsc_t *dsc_out, uint32_t letter, uint32_t letter_next) {
    gt_font_param_t *param = font->dsc;
    uint16_t code = gt_unicode2gb18030(letter);

    dsc_out->adv_w = gt_font_get_adv_w(param, code);
    dsc_out->box_w = (param->dot + 7) / 8 * 8;
    // LLOGD("adv_w:%d box_w:%d",dsc_out->adv_w,dsc_out->box_w);
    dsc_out->box_h = param->size;
    dsc_out->ofs_x = 0;
    dsc_out->ofs_y = 0;
    dsc_out->bpp  = param->bpp;

    return true;
}

static uint8_t *gt_font_get_glyph_bitmap(const struct _lv_font_struct *font, uint32_t letter) {
    gt_font_param_t *param = font->dsc;
    gt_font_get(param, gt_unicode2gb18030(letter));
    return param->buf;
}

bool lv_font_is_gt(lv_font_t *font) {
    if (font != NULL && font->get_glyph_dsc == gt_font_get_glyph_dsc)
        return true;
    return false;
}

lv_font_t *lv_font_new_gt(uint8_t sty_zh, uint8_t sty_en, uint8_t size, uint8_t bpp, uint16_t thickness, uint8_t cache_size) {
    lv_font_t *font = lv_mem_alloc(sizeof(lv_font_t));
    if (!font) return NULL;

    memset(font, 0, sizeof(lv_font_t));
    font->get_glyph_dsc = gt_font_get_glyph_dsc;
    font->get_glyph_bitmap = gt_font_get_glyph_bitmap;
    font->line_height = size;

    int malloc_size = size * bpp * size * bpp;
    gt_font_param_t *param = lv_mem_alloc(sizeof(gt_font_param_t) + malloc_size);
    if (!param) {
        lv_font_del_gt(font);
        return NULL;
    }

    memset(param, 0, sizeof(*param));
    font->dsc = param;
    param->sty_zh = sty_zh;
    param->sty_en = sty_en;
    param->size = size;
    param->bpp = bpp;
    param->thickness = thickness;

    return font;
}

void lv_font_del_gt(lv_font_t *font) {
    if (!font) return;
    if (!font->dsc) {
        lv_mem_free(font);
        return;
    }
    gt_font_param_t *param = font->dsc;
    lv_mem_free(param);
    lv_mem_free(font);
}

#else

bool lv_font_is_gt(lv_font_t *font) {
    return false;
}

lv_font_t *lv_font_new_gt(uint8_t sty_zh, uint8_t sty_en, uint8_t size, uint8_t bpp, uint16_t thickness, uint8_t cache_size) {
    return NULL;
}

void lv_font_del_gt(lv_font_t *font) {

}

#endif