#include "luat_base.h"
#include "luat_lcd.h"

#define LUAT_LOG_TAG "gc9106l"
#include "luat_log.h"

static const uint16_t gc9106l_init_cmds[] = {
   //------------------------------------gc9106lS Frame Rate-----------------------------------------//
    0x02FE,
    0x02EF,
    0x02B3,0x0303,
    0x0221,
    0x023A,0x0305,
    0x02B4,0x0321,
    0x02F0,0x032D,0x0354,0x0324,0x0361,0x03AB,0x032E,0x032F,0x0300,0x0320,0x0310,0x0310,0x0317,0x0313,0x030F,
    0x02F1,0x0302,0x0322,0x0325,0x0335,0x03A8,0x0308,0x0308,0x0300,0x0300,0x0309,0x0309,0x0317,0x0318,0x030F,
    0x02FE,
    0x02FF,
};


const luat_lcd_opts_t lcd_opts_gc9106l = {
    .name = "gc9106l",
    .init_cmds_len = sizeof(gc9106l_init_cmds)/sizeof(gc9106l_init_cmds[0]),
    .init_cmds = gc9106l_init_cmds,
    .interface_mode = LUAT_LCD_IM_4_WIRE_8_BIT_INTERFACE_I,
    .direction0 = 0xC8,
    .direction90 = 0x08,
    .direction180 = 0x68,
    .direction270 = 0xA8
};
