#include "luat_base.h"
#include "luat_lcd.h"
#include "luat_gpio.h"
#include "luat_rtos.h"
#define LUAT_LOG_TAG "sh8601z"
#include "luat_log.h"

static int sh8601z_inited_init(luat_lcd_conf_t* conf)
{
	luat_lcd_qspi_conf_t auto_flush =
	{
			.write_4line_cmd = 0x32,
			.vsync_reg = 0,
			.hsync_cmd = 0,
			.hsync_reg = 0,
			.write_1line_cmd = 0x02,
			.write_4line_data = 0x12,
	};
    luat_lcd_qspi_config(conf, &auto_flush);	//必须在第一个命令发送前就准备好
    luat_gpio_set(conf->pin_rst, Luat_GPIO_LOW);
    luat_rtos_task_sleep(10);
    luat_gpio_set(conf->pin_rst, Luat_GPIO_HIGH);
    luat_rtos_task_sleep(50);
    luat_lcd_wakeup(conf);
    luat_rtos_task_sleep(100);
    uint8_t temp = 0x55;
    lcd_write_cmd_data(conf,0x3A, &temp, 1);
    temp = 0x20;
    lcd_write_cmd_data(conf,0x53, &temp, 1);
    temp = 0xff;
    lcd_write_cmd_data(conf,0x51, &temp, 1);
//    luat_lcd_clear(conf,LCD_BLACK);
    luat_lcd_display_on(conf);
    return 0;
}

luat_lcd_opts_t lcd_opts_sh8601z = {
    .name = "sh8601z",
    .init_cmds_len = 0,
    .init_cmds = NULL,
    .direction0 = 0x00,
    .direction90 = 0x00,
    .direction180 = 0x40,
    .direction270 = 0x40,
	.rb_swap = 1,
	.user_ctrl_init = sh8601z_inited_init,
};
