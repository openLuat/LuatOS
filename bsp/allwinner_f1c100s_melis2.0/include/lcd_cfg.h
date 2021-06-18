#ifndef __LCD_CFG_H__
#define __LCD_CFG_H__
#include "port.h"
enum
{
    LCD_PARA_POWER,
    LCD_PARA_PWM,
    LCD_PARA_BACK_LIGHT,
    LCD_PARA_D0,
    LCD_PARA_D23 = LCD_PARA_D0 + 23,
    LCD_PARA_CLK,
    LCD_PARA_DE,
    LCD_PARA_H,
    LCD_PARA_V,
    LCD_PARA_QTY,
};
extern const user_gpio_set_t lcd_common_rgb_gpio_list[LCD_PARA_QTY];
extern void LCD_common_rbg_cfg_panel_info(__panel_para_t * info);
extern void LCD_common_rbg_cfg_panel_info1(__panel_para_t * info);
#endif