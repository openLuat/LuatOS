#include "luat_base.h"
#include "luat_lcd.h"
#include "luat_gpio.h"
#include "luat_spi.h"
#include "luat_mem.h"
#include "luat_rtos.h"

#define LUAT_LOG_TAG "custom"
#include "luat_log.h"

luat_lcd_opts_t lcd_opts_custom = {
    .name = "custom",
};

static int lcd_user_ctrl_init(luat_lcd_conf_t* conf)
{
	if (LUAT_LCD_IM_QSPI_MODE == conf->interface_mode)
	{
		if (luat_lcd_qspi_is_no_ram(conf))
		{
			conf->opts->no_ram_mode = 1;
		}
	    luat_lcd_qspi_config(conf, NULL);	//必须在第一个命令发送前就准备好
	}

	return 1;
}


luat_lcd_opts_t lcd_opts_user_ctrl = {
    .name = "user",
	.user_ctrl_init = lcd_user_ctrl_init,
};
