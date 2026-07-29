#ifndef __LUAT_DISPLAY_IF_COMM_H__
#define __LUAT_DISPLAY_IF_COMM_H__





extern struct luat_display_funcs sdl_funcs;
extern struct luat_display_funcs rgb_funcs;
extern struct luat_display_funcs dsi_funcs;
extern struct luat_display_funcs spi_funcs;
extern struct luat_display_funcs lvds_funcs;



/*****************************************************
 * RGB面板操作接口
 ******************************************************/
int rgb_spi_panel_send_sequence(struct luat_display_panel *panel, const unsigned char *data, uint32_t len);

/*****************************************************
 * DSI面板操作接口
 ******************************************************/
int dsi_panel_send_sequence(struct luat_display_panel *panel, const unsigned char *data, uint32_t len);

/*****************************************************
 * SPI面板操作接口
 ******************************************************/
int spi_panel_send_sequence(struct luat_display_panel *panel, const unsigned char *data, uint32_t len);




#endif  /* __LUAT_DISPLAY_IF_COMM_H__ */

