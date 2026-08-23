
#include "luat_base.h"
#include "u8g2.h"

enum {
    LUAT_U8G2_FLUSH_PAGE = 0,
    LUAT_U8G2_FLUSH_PAGE_ARG,
    LUAT_U8G2_FLUSH_WINDOW_GRAY4,
    LUAT_U8G2_FLUSH_WINDOW_2ROW_LUT,
};

enum {
    LUAT_U8G2_HVLINE_VERTICAL_TOP = 0,
    LUAT_U8G2_HVLINE_HORIZONTAL_RIGHT,
};

enum {
    LUAT_U8G2_CAD_001 = 1,
    LUAT_U8G2_CAD_011 = 11,
    LUAT_U8G2_CAD_100 = 100,
};

typedef struct luat_u8g2_custom {
    size_t init_cmd_count;
    uint32_t *initcmd; // 实际命令长度与init_cmd_count相同
    u8x8_display_info_t display_info;
    uint8_t flush_mode;
    uint8_t hvline;
    uint8_t cad_mode;
    uint8_t tile_w;
    uint8_t tile_h;
    uint8_t column_start;
    uint8_t row_offset;
    uint8_t has_column_start;
    uint8_t has_sleepcmd;
    uint8_t has_wakecmd;
}luat_u8g2_custom_t;

typedef struct luat_u8g2_conf
{
    uint16_t w;
    uint16_t h;
    uint8_t sleepcmd;
    uint8_t wakecmd;
    int lua_ref;
    char cname[32]; // 控制器名称, 例如SSD1306
    u8g2_t u8g2;
    const u8g2_cb_t* direction;//方向 
    uint8_t* buff_ptr;
    void* userdata;
#ifdef LUAT_USE_HZFONT
    void* hzfont;
    uint8_t is_hzfont_enabled;
#endif
} luat_u8g2_conf_t;

uint8_t u8x8_d_custom_noname(u8x8_t *u8x8, uint8_t msg, uint8_t arg_int, void *arg_ptr);

int luat_u8g2_setup(luat_u8g2_conf_t *conf);

// 仅 PC 模拟器(luat_u8g2_sdl2.c)使用,暴露 file-static i2c_id/spi_id 给 override
void luat_u8g2_get_bus_ids(int* i2c_id_out, int* spi_id_out);

int luat_u8g2_close(luat_u8g2_conf_t *conf);

void luat_u8g2_set_ascii_indentation(uint8_t value);

u8g2_uint_t luat_u8g2_need_ascii_cut(u8g2_uint_t org_delta);
