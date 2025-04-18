#include "luat_base.h"
#include "luat_lcd.h"

#define LUAT_LOG_TAG "st7789"
#include "luat_log.h"

static const uint16_t st7789_init_cmds[] = {
    /* RGB 5-6-5-bit  */
    0x023A,0x0305,
    /* Porch Setting */
    0x02B2,0x030C,0x030C,0x0300,0x0333,0x0333,
    /*  Gate Control */
    0x02B7,0x0335,
    /* VCOM Setting */
    0x02BB,0x0332,
    /* LCM Control */
    // 0x02C0,
    // 0x032C,
    /* VDV and VRH Command Enable */
    0x02C2,0x0301,
    /* VRH Set */
    0x02C3,0x0315,
    /* VDV Set */
    0x02C4,0x0320,
    /* Frame Rate Control in Normal Mode */
    0x02C6,0x030F,
    /* Power Control 1 */
    0x02D0,0x03A4,0x03A1,
    /* Positive Voltage Gamma Control */
    0x02E0,0x03D0,0x0308,0x030E,0x0309,0x0309,0x0305,0x0331,0x0333,0x0348,0x0317,0x0314,0x0315,0x0331,0x0334,
    /* Negative Voltage Gamma Control */
    0x02E1,0x03D0,0x0308,0x030E,0x0309,0x0309,0x0315,0x0331,0x0333,0x0348,0x0317,0x0314,0x0315,0x0331,0x0334,
    0x0221,
};

luat_lcd_opts_t lcd_opts_st7789 = {
    .name = "st7789",
    .init_cmds_len = sizeof(st7789_init_cmds)/sizeof(st7789_init_cmds[0]),
    .init_cmds = st7789_init_cmds,
    .direction0 = 0x00,
    .direction90 = 0xC0,
    .direction180 = 0x70,
    .direction270 = 0xA0,
	.rb_swap = 1,
};
