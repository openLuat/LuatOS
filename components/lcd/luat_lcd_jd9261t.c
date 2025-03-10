#include "luat_base.h"
#include "luat_lcd.h"
#include "luat_gpio.h"
#include "luat_mem.h"
#include "luat_rtos.h"
#include "luat_i2c.h"
#define LUAT_LOG_TAG "jd9261t-lcd"
#include "luat_log.h"

static int jd9261t_inited_init(luat_lcd_conf_t* conf)
{
    if (!conf->buff)
    {
    	conf->buff = luat_heap_opt_zalloc(LUAT_HEAP_AUTO, conf->w * conf->h * ((conf->bpp <= 16)?2:4));
    	conf->flush_y_min = conf->h;
    	conf->flush_y_max = 0;
    }
	luat_lcd_qspi_conf_t auto_flush =
	{
			.write_4line_cmd = 0xde,
			.vsync_reg = 0x61,
			.hsync_cmd = 0xde,
			.hsync_reg = 0x60,
			.write_1line_cmd = 0xde,
	};
    luat_gpio_set(conf->pin_rst, Luat_GPIO_LOW);
//    luat_rtos_task_sleep(5);
//    luat_gpio_set(conf->tp_pin_rst, Luat_GPIO_HIGH);
    luat_rtos_task_sleep(5);
    luat_gpio_set(conf->pin_rst, Luat_GPIO_HIGH);
//    luat_gpio_set(conf->tp_pin_rst, Luat_GPIO_LOW);
//    luat_rtos_task_sleep(50);
//    luat_gpio_set(conf->tp_pin_rst, Luat_GPIO_HIGH);
//    luat_rtos_task_sleep(100);
    luat_rtos_task_sleep(150);
    luat_lcd_qspi_config(conf, &auto_flush);	//必须在第一个命令发送前就准备好
    luat_lcd_set_direction(conf,conf->direction);
    luat_rtos_task_sleep(5);
    luat_gpio_set(conf->pin_pwr, Luat_GPIO_HIGH);
    luat_lcd_qspi_auto_flush_on_off(conf, 1);
    return 0;
}

luat_lcd_opts_t lcd_opts_jd9261t_inited = {
    .name = "jd9261t_inited",
    .init_cmds_len = 0,
    .init_cmds = NULL,
    .direction0 = 0x00,
    .direction90 = 0x00,
    .direction180 = 0x03,
    .direction270 = 0x03,
	.rb_swap = 1,
	.no_ram_mode = 1,
	.user_ctrl_init = jd9261t_inited_init,
};
