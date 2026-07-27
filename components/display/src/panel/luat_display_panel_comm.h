#ifndef __LUAT_DISPLAY_PANEL_COMM_H__
#define __LUAT_DISPLAY_PANEL_COMM_H__

#include "luat_display.h"
#include "luat_display_if_comm.h"

#define ARRAY_SIZE(array) (sizeof(array) / sizeof(array[0]))


/*RGB面板列表*/
extern struct luat_display_panel rgb_panel_custom;
extern struct luat_display_panel rgb_panel_st7701s;

/*DSI面板列表*/
extern struct luat_display_panel dsi_panel_st7701s;

/*SPI面板列表*/
extern struct luat_display_panel spi_panel_st7789;
extern struct luat_display_panel spi_panel_ili9341;




/*显示面板*/
struct luat_display_panel *luat_display_find_panel(unsigned int connector_type);

/*默认复位显示面板*/
int luat_display_panel_reset(struct luat_display_panel *panel);

#endif
