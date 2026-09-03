#ifndef __LUAT_DISPLAY_PANEL_COMM_H__
#define __LUAT_DISPLAY_PANEL_COMM_H__

#include "luat_display.h"
#include "luat_display_if_comm.h"

#define ARRAY_SIZE(array) (sizeof(array) / sizeof(array[0]))


/*RGB面板列表*/
extern struct luat_display_panel rgb_panel_custom;
extern struct luat_display_panel rgb_panel_st7701s;
extern struct luat_display_panel rgb_panel_nv3052c;

/*DSI面板列表*/
extern struct luat_display_panel dsi_panel_st7701s;
extern struct luat_display_panel dsi_panel_custom;

/*LVDS面板列表*/
extern struct luat_display_panel lvds_panel_custom;

/*SPI面板列表*/
extern struct luat_display_panel spi_panel_st7789;
extern struct luat_display_panel spi_panel_ili9341;



/*PC面板*/
extern struct luat_display_panel panel_pc;


/*显示面板*/
struct luat_display_panel *luat_display_find_panel(unsigned int connector_type);

/*默认复位显示面板*/
int luat_display_panel_reset(struct luat_display_panel *panel);

/*按连接器类型发送一条命令序列，data 首字节为命令，返回 0 表示成功*/
int luat_display_send_sequence(struct luat_display_panel *panel, const void *data, uint32_t len);

/*发送 Lua 自定义初始化命令序列（custom_cmds，无则不发送）*/
int luat_display_panel_send_custom_cmds(struct luat_display_panel *panel);

/*各面板 panel_ctrl 的通用实现（含 LUAT_DISPLAY_SEND_SEQ 命令序列下发）*/
int luat_display_panel_ctrl(struct luat_display_panel *panel, enum display_ctrl_cmd cmd, void *arg);

#endif
