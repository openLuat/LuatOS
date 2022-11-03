#include "luat_lvgl_fonts.h"

#ifdef LUAT_USE_GTFONT

#include "GT5SLCD2E_1A.h"

extern unsigned short unicodetogb2312(unsigned short);

typedef struct
{
    int life;
    uint16_t code;
    uint16_t dot;
    char data[1];
} gt_font_char_t;

typedef struct
{
    uint16_t i;
    gt_font_char_t **chars;
} gt_font_cache_t;

typedef struct
{
    uint8_t sty_zh;
    uint8_t sty_en;
    uint16_t size;
    uint16_t bpp;
    uint16_t thickness;
    gt_font_cache_t *cache;
    uint16_t adv_w[94];
    uint16_t code;
    uint32_t dot;
    char buf[1];
} gt_font_param_t;

gt_font_char_t **gt_font_cache_open(gt_font_param_t *param, uint16_t code) {
    if (param->cache == NULL)
        return NULL;

    gt_font_char_t *cached_char = NULL;
    gt_font_cache_t *cache = param->cache;
    gt_font_char_t **chars = cache->chars;

    int i = 0;
    for (i = 0; i < cache->i && chars[i] != NULL; ++i)
    {
        if(chars[i]->life > (INT32_MIN + 1)) {
            chars[i]->life -= 1;
        }
    }

    for(i = 0; i < cache->i && chars[i] != NULL; i++) {
        if(chars[i]->code == code) {
            cached_char = chars[i];
            cached_char->life += 1;
            if(cached_char->life > 1000) cached_char->life = 1000;
            break;
        }
    }

    if (cached_char || i < cache->i) return &chars[i];

    i = 0;
    for(int j = 1; j < cache->i; j++) {
        if(cache->chars[j]->life < chars[i]->life) {
            i = j;
        }
    }

    chars[i]->life = 0;
    chars[i]->code = 0;

    return &chars[i];
}

static void gt_font_get(gt_font_param_t *param, uint16_t code) {
    if (param->code == code)
        return;

    gt_font_char_t *vc = NULL;
    gt_font_char_t **cached_char = gt_font_cache_open(param, code);
    if (cached_char != NULL && (vc = *cached_char) != NULL && vc->code == code) {
        param->code = code;
        param->dot = vc->dot;
        int size = ((param->dot + 7) / 8 * 8) * param->size * param->bpp / 8;
        memcpy(param->buf, vc->data, size);
        return;
    }

    uint8_t sty = param->sty_zh;
    if (code >= 0x20 && code <= 0x7e)
        sty = param->sty_en;

    memset(param->buf, 0, param->size * param->bpp * param->size * param->bpp);

    uint32_t dot = get_font(param->buf, sty, code, param->size * param->bpp, param->size * param->bpp, param->thickness);

    param->code = code;
    param->dot = dot / param->bpp;

    Gray_Process(param->buf, param->dot, param->size, param->bpp);

    if (cached_char != NULL) {
        int size = ((param->dot + 7) / 8 * 8) * param->size * param->bpp / 8;
        vc = lv_mem_realloc(vc, sizeof(gt_font_char_t) + size);
        vc->dot = param->dot;
        vc->code = code;
        vc->life = 0;
        memcpy(vc->data, param->buf, size);

        *cached_char = vc;
    }
}

int get_font_adv_w(uint8_t *buf, int width, int height, int bpp) {
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

    if (code >= 0x21 && code <= 0x7e) {
        int i = code - 0x21;
        if (param->adv_w[i] == 0xFFFF) {
            gt_font_get(param, code);
            param->adv_w[i] = get_font_adv_w(param->buf, param->dot, param->size, param->bpp);
        }
        adv_w = param->adv_w[i];
    } else if (code == 0x20) {
        adv_w = param->size / 2;
    }

    return adv_w;
}

bool gt_font_get_glyph_dsc(const struct _lv_font_struct *font, lv_font_glyph_dsc_t *dsc_out, uint32_t letter, uint32_t letter_next) {
    gt_font_param_t *param = font->dsc;
    uint16_t code = unicodetogb2312(letter);

    dsc_out->adv_w = gt_font_get_adv_w(param, code);
    dsc_out->box_w = ((param->code == code ? param->dot : param->size) + 7) / 8 * 8;
    dsc_out->box_h = param->size;
    dsc_out->ofs_x = 0;
    dsc_out->ofs_y = 0;
    dsc_out->bpp   = param->bpp;

    return true;
}

uint8_t *gt_font_get_glyph_bitmap(const struct _lv_font_struct *font, uint32_t letter) {
    gt_font_param_t *param = font->dsc;
    uint16_t code = unicodetogb2312(letter);
    gt_font_get(param, code);
    return param->buf;
}

bool lv_font_is_gt(lv_font_t *font) {
    if (font != NULL && font->get_glyph_dsc == gt_font_get_glyph_dsc)
        return true;
    return false;
}

lv_font_t *lv_font_new_gt(uint8_t sty_zh, uint8_t sty_en, uint8_t size, uint8_t bpp, uint16_t thickness, uint8_t cache_size) {
    lv_font_t *font = NULL;
    do {
        font = lv_mem_alloc(sizeof(lv_font_t));
        if (!font) break;

        memset(font, 0, sizeof(lv_font_t));
        font->get_glyph_dsc = gt_font_get_glyph_dsc;
        font->get_glyph_bitmap = gt_font_get_glyph_bitmap;
        font->line_height = size;

        int malloc_size = size * bpp * size * bpp;
        gt_font_param_t *param = lv_mem_alloc(sizeof(gt_font_param_t) + malloc_size);
        if (!param) break;

        memset(param, 0, sizeof(*param));
        font->dsc = param;
        memset(param->adv_w, 0xFF, sizeof(param->adv_w));
        param->sty_zh = sty_zh;
        param->sty_en = sty_en;
        param->size = size;
        param->bpp = bpp;
        param->thickness = thickness;
        if (cache_size != 0) {
            gt_font_cache_t *cache = lv_mem_alloc(sizeof(gt_font_cache_t));
            if (!cache) break;

            memset(cache, 0, sizeof(*cache));
            param->cache = cache;
            cache->i = cache_size;
            cache->chars = lv_mem_alloc(cache_size * sizeof(gt_font_char_t *));
            if (!cache->chars) break;

            memset(cache->chars, 0, cache_size * sizeof(gt_font_char_t *));
        }

        return font;

    } while (0);

    lv_font_del_gt(font);
    return NULL;
}

void lv_font_del_gt(lv_font_t *font) {
    if (!font) return;
    if (!font->dsc) {
        lv_mem_free(font);
        return;
    }
    gt_font_param_t *param = font->dsc;
    if (param->cache) {
        gt_font_char_t **chars = param->cache->chars;
        for (int i = 0; i < param->cache->i; ++i) {
            if (chars[i]) lv_mem_free(chars[i]);
        }
        if (param->cache->chars) lv_mem_free(param->cache->chars);
        lv_mem_free(param->cache);
    }
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