#include "luat_base.h"

typedef struct luat_font_data {
    uint8_t map_type;  // 类型数据, 后面有详细说明
    uint8_t unicode_size; // map表单个字符的字节大小, 可以是2,4
    uint16_t bitmap_size; // 单个字符的bitmap数据的字节大小
    uint16_t char_w_bit;
    uint16_t count;    // 字符数量
    uint32_t unicode_min;
    uint32_t unicode_max;
    uint8_t *map_data;
    uint8_t *bitmap_data;
    // uint32_t reserved; // 保留区域, 扩展用, 默认0x0000
}luat_font_data_t;

typedef struct luat_font_header
{
    uint8_t magic;                 // 总是 0xC5
    uint8_t version;               // 当前为0x0001
    uint8_t line_height;                // 字号
    uint8_t access_mode         : 4;   // 访问模式
    uint8_t font_data_count     : 4;   // 数据总数, 通常就1或2个,不会很多.

    uint32_t reserved;             // 保留区域, 扩展用, 默认0x0000
}luat_font_header_t;


typedef struct luat_font_desc
{
    luat_font_header_t header;
    luat_font_data_t *datas;
}luat_font_desc_t;

typedef struct luat_font_char_desc
{
    // uint32_t unicode;
    uint32_t line_height;
    uint16_t char_w;
    uint16_t reserved;
    uint16_t len;
    uint8_t *data;
}luat_font_char_desc_t;


int luat_font_get_bitmap(luat_font_header_t *font, luat_font_char_desc_t *dsc_out, uint32_t letter);
uint16_t luat_utf8_next(uint8_t b, uint8_t *utf8_state, uint16_t *encoding);

// LVGL

#include "lvgl.h"
#include "lv_font.h"
/** Get a glyph's descriptor from a font*/
bool luat_fonts_lvgl_get_glyph_dsc(const struct _lv_font_struct *, lv_font_glyph_dsc_t *, uint32_t letter, uint32_t letter_next);
/** Get a glyph's bitmap from a font*/
const uint8_t * luat_fonts_lvgl_get_glyph_bitmap(const struct _lv_font_struct *, uint32_t);

