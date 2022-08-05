#include "luat_base.h"
#include "luat_ufont.h"

#define LUAT_LOG_TAG "ufont"
#include "luat_log.h"

#include "lvgl.h"
#include "lv_font.h"
/** Get a glyph's descriptor from a font*/
bool luat_fonts_lvgl_get_glyph_dsc(const struct _lv_font_struct * lfont, lv_font_glyph_dsc_t * ldsc, uint32_t letter, uint32_t letter_next) {
    luat_font_char_desc_t dsc_out = {0};
    luat_font_header_t *font = (luat_font_header_t *)lfont->dsc;
    int ret = luat_font_get_bitmap(font, &dsc_out, letter);

    if (ret != 0) {
        ldsc->data_ready = 0;
        return false;
    }

    ldsc->adv_w = dsc_out.char_w;
    ldsc->box_h = font->line_height;
    ldsc->box_w = dsc_out.char_w;
    ldsc->bpp = 1;
    ldsc->ofs_x = 0;
    ldsc->ofs_y = 0;
    uint32_t ptr_value = (uint32_t)ldsc->data;
    // LLOGD("copy bitmap %p %p %04X", ldsc->data, dsc_out.data, (ldsc->box_h * ldsc->box_w + 7) / 8);
    //LLOGD("get_glyph_dsc->data %p data_ready %d", ldsc->data, ldsc->data_ready);
    if (ldsc->data && ldsc->data_ready == 0 && font->line_height <= 64) {
        //LLOGD("memcpy %p %p %04X", ldsc->data, dsc_out.data, (ldsc->box_h * ldsc->box_w + 7) / 8);
        memcpy(ldsc->data, dsc_out.data, (ldsc->box_h * ldsc->box_w + 7) / 8);
        ldsc->data_ready = 1;
    }
    return  true;
}
/** Get a glyph's bitmap from a font*/
const uint8_t * luat_fonts_lvgl_get_glyph_bitmap(const struct _lv_font_struct *lfont, uint32_t letter) {
    luat_font_char_desc_t dsc_out = {0};
    luat_font_header_t *font = (luat_font_header_t *)lfont->dsc;
    int ret = luat_font_get_bitmap(font, &dsc_out, letter);

    if (ret != 0) {
        return NULL;
    }
    return dsc_out.data;
}


