
/*******************************************************************************
 * tool: lvgl_conv_tool V1.0.1
 * author: Dozingfiretruck
 * author_github_url: https://github.com/Dozingfiretruck
 * author_gitee_url: https://gitee.com/Dozingfiretruck
 * qq: 1041390013
 ******************************************************************************/

#ifdef __has_include
    #if __has_include("lvgl.h")
        #ifndef LV_LVGL_H_INCLUDE_SIMPLE
            #define LV_LVGL_H_INCLUDE_SIMPLE
        #endif
    #endif
#endif

#ifdef LV_LVGL_H_INCLUDE_SIMPLE
    #include "lvgl.h"
#else
    #include "lvgl/lvgl.h"
#endif

#include "luat_mem.h"
#include "luat_fs.h"

/*-----------------
 *    STRUCT
 *----------------*/

typedef struct{
    char head[5];
    uint8_t bpp;
    int8_t underline_position;
    int8_t underline_thickness;
    int16_t line_height;
    int16_t base_line;
    uint16_t codes_min;
    uint16_t codes_max;
}custom_font_header_t;

typedef struct{
    uint32_t adv_w;
    uint16_t box_w;
    uint16_t box_h;
    int16_t ofs_x;
    int16_t ofs_y;
    uint32_t glyph_data_len;
}custom_glyph_dsc_t;

typedef struct{
    custom_font_header_t custom_font_header;
    FILE* font_file;
    uint8_t glyph_data[2048];
}custom_font_data_t;

static void *custom_font_getdata(const lv_font_t * font, uint32_t offset, uint32_t size){
    custom_font_data_t* custom_font_data = font->dsc;
    FILE* font_file = custom_font_data->font_file;
    uint8_t* glyph_data = custom_font_data->glyph_data;
    memset(glyph_data, 0, sizeof(custom_font_data->glyph_data));
    luat_fs_fseek(font_file, offset, SEEK_SET);
    luat_fs_fread(glyph_data, 1, size, font_file);
    return glyph_data;
}

/*-----------------
 *  GET DSC
 *----------------*/

static bool custom_font_get_glyph_dsc_fmt_txt(const lv_font_t * font, lv_font_glyph_dsc_t * dsc_out, uint32_t unicode_letter, uint32_t unicode_letter_next) {
    custom_font_data_t* custom_font_data = font->dsc;
    custom_font_header_t* custom_font_header = &custom_font_data->custom_font_header;
    bool is_tab = false;
    if(unicode_letter == '\t') {
        unicode_letter = ' ';
        is_tab = true;
    }
    if( unicode_letter>custom_font_header->codes_max || unicode_letter<custom_font_header->codes_min ) {
        return false;
    }
    uint32_t unicode_offset = sizeof(custom_font_header_t)+(unicode_letter-custom_font_header->codes_min)*sizeof(uint32_t);
    uint32_t *p_pos = (uint32_t *)custom_font_getdata(font, unicode_offset, sizeof(uint32_t));
    if(*p_pos) {
        custom_glyph_dsc_t * gdsc = (custom_glyph_dsc_t*)custom_font_getdata(font, *p_pos, sizeof(custom_glyph_dsc_t));
        dsc_out->box_h = gdsc->box_h;
        dsc_out->box_w = gdsc->box_w;
        dsc_out->ofs_x = gdsc->ofs_x;
        dsc_out->ofs_y = gdsc->ofs_y;
        dsc_out->bpp   = custom_font_header->bpp;

        uint32_t adv_w = gdsc->adv_w;
        if(is_tab) adv_w *= 2;
        dsc_out->adv_w  = (adv_w + (1 << 3)) >> 4;
        if(is_tab) dsc_out->box_w = dsc_out->box_w * 2;
        return true;
    }
    return false;
}

/*-----------------
 *  GET BITMAP
 *----------------*/

static const uint8_t* custom_font_get_bitmap_fmt_txt(const lv_font_t * font, uint32_t unicode_letter) {
    custom_font_data_t* custom_font_data = font->dsc;
    custom_font_header_t* custom_font_header = &custom_font_data->custom_font_header;
    if(unicode_letter == '\t') unicode_letter = ' ';
    if( unicode_letter>custom_font_header->codes_max || unicode_letter<custom_font_header->codes_min ) {
        return NULL;
    }
    uint32_t unicode_offset = sizeof(custom_font_header_t )+(unicode_letter-custom_font_header->codes_min)*sizeof(uint32_t);
    uint32_t *p_pos = (uint32_t *)custom_font_getdata(font, unicode_offset, sizeof(uint32_t));
    uint32_t dsc_offset = p_pos[0];
    if(dsc_offset) {
        custom_glyph_dsc_t* gdsc = (custom_glyph_dsc_t*)custom_font_getdata(font, dsc_offset, sizeof(custom_glyph_dsc_t));
        return custom_font_getdata(font, dsc_offset + sizeof(custom_glyph_dsc_t), gdsc->glyph_data_len);
    }
    return NULL;
}

/*-----------------
 *  PUBLIC FONT
 *----------------*/

lv_font_t* custom_get_font(FILE* font_file){
    lv_font_t* custom_font = luat_heap_malloc(sizeof(lv_font_t));
    if (custom_font == NULL){
        return NULL;
    }
    
    memset(custom_font, 0, sizeof(lv_font_t));
    custom_font->get_glyph_dsc = custom_font_get_glyph_dsc_fmt_txt;
    custom_font->get_glyph_bitmap = custom_font_get_bitmap_fmt_txt;

    custom_font_data_t* custom_font_data = luat_heap_malloc(sizeof(custom_font_data_t));
    memset(custom_font_data, 0, sizeof(custom_font_data_t));
    custom_font_data->font_file = font_file;
    custom_font->dsc = custom_font_data;

    uint32_t *p_pos = (uint32_t *)custom_font_getdata(custom_font, 0, sizeof(custom_font_header_t));
    memcpy(&custom_font_data->custom_font_header, p_pos, sizeof(custom_font_header_t));
    if (strncmp(custom_font_data->custom_font_header.head, "head", 4)){
        luat_heap_free(custom_font);
        return NULL;
    }

    custom_font->base_line = custom_font_data->custom_font_header.base_line;
    custom_font->line_height = custom_font_data->custom_font_header.line_height;
#if LV_VERSION_CHECK(7, 4, 0) || LVGL_VERSION_MAJOR >= 8
    custom_font->underline_position = custom_font_data->custom_font_header.underline_position;
    custom_font->underline_thickness = custom_font_data->custom_font_header.underline_thickness;
#endif
    return custom_font;
}

void custom_free_font(lv_font_t* custom_font){
    if (custom_font){
        luat_heap_free(custom_font->dsc);
        luat_heap_free(custom_font);
    }
}