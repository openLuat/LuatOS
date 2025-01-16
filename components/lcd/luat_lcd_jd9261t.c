#include "luat_base.h"
#include "luat_lcd.h"
#include "luat_gpio.h"
#include "luat_mem.h"
#include "luat_rtos.h"
#include "luat_i2c.h"
#define LUAT_LOG_TAG "jd9261t"
#include "luat_log.h"

typedef struct
{
	luat_lcd_conf_t* lcd;
	luat_rtos_timer_t scan_timer;
	uint8_t scan_cnt;
}jd9261t_tp_ctrl_t;

static jd9261t_tp_ctrl_t jd9261t_tp;
static void jd9261t_get_tp_point(void *param, uint32_t param_len)
{
	uint16_t tp_x, tp_y;
	int res;
	uint8_t buff[60];
	buff[0] = 0x20;
	buff[1] = 0x01;
	buff[2] = 0x11;
	buff[3] = 0x20;
	res = luat_i2c_send(jd9261t_tp.lcd->tp_i2c_id, 0x68, buff, 4, 1);
	if (res)
	{
		res = luat_i2c_send(jd9261t_tp.lcd->tp_i2c_id, 0x68, buff, 4, 1);
		if (res)
		{
			LLOGE("TP read point failed");
			return;
		}
	}
	luat_timer_us_delay(15);
	res = luat_i2c_recv(jd9261t_tp.lcd->tp_i2c_id, 0x68, buff, 60);
	if (res)
	{
		res = luat_i2c_recv(jd9261t_tp.lcd->tp_i2c_id, 0x68, buff, 60);
		if (res)
		{
			LLOGE("TP read point failed");
			return;
		}
	}
	if (!buff[0]) return;

	for (uint8_t i = 0; i < 10; i++)
	{
		if (buff[i * 5 + 3] != 0xff)
		{
			//LLOGI("%d, %x %x %x %x", i * 5 + 3, buff[i * 5 + 3], buff[i * 5 + 4], buff[i * 5 + 5], buff[i * 5 + 6]);
			tp_x = buff[i * 5 + 3] & 0x01;
			tp_x = (tp_x << 8) | buff[i * 5 + 4];
			tp_y = buff[i * 5 + 5] & 0x01;
			tp_y = (tp_y << 8) | buff[i * 5 + 6];
			LLOGI("TP point %d x %d y %d", i+1, tp_x, tp_y);
		}
	}
}

static LUAT_RT_RET_TYPE jd9261t_scan_once(LUAT_RT_CB_PARAM)
{
	jd9261t_tp.scan_cnt++;
	luat_lcd_run_api_in_service(jd9261t_get_tp_point, jd9261t_tp.lcd, 0);
	if (jd9261t_tp.scan_cnt > 10)
	{
		luat_rtos_timer_stop(jd9261t_tp.scan_timer);
	}
}

static int jd9261t_irq_cb(int pin, void* args)
{
	if (jd9261t_tp.scan_cnt > 10)
	{
		jd9261t_tp.scan_cnt = 0;
		luat_start_rtos_timer(jd9261t_tp.scan_timer, 20, 1);
	}
	return 0;
}

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
	luat_gpio_set(conf->tp_pin_rst, Luat_GPIO_HIGH);
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
    if ((conf->tp_pin_rst != LUAT_GPIO_NONE) && (conf->tp_pin_rst || conf->tp_pin_irq))
    {
    	uint8_t ID[4];
    	ID[0] = 0x40;
    	ID[1] = 0x00;
    	ID[2] = 0x80;
    	ID[3] = 0x76;
    	luat_i2c_setup(conf->tp_i2c_id, 200000);
    	luat_i2c_set_polling_mode(conf->tp_i2c_id, 1);
    	if (luat_i2c_transfer(conf->tp_i2c_id, 0x68, ID, 4, ID, 2))
    	{
    		LLOGE("TP not detect");
    	}
    	else
    	{
    		LLOGI("TP detect %02x%02x", ID[1], ID[0]);
    		jd9261t_tp.lcd = conf;
    		jd9261t_tp.scan_cnt = 100;
    		jd9261t_tp.scan_timer = luat_create_rtos_timer(jd9261t_scan_once, NULL, NULL);
    		luat_gpio_t gpio = {0};
    		gpio.pin = conf->tp_pin_irq;
    		gpio.mode = LUAT_GPIO_IRQ;
    		gpio.alt_func = -1;
    		gpio.pull = LUAT_GPIO_PULLUP;
    		gpio.irq = LUAT_GPIO_FALLING_IRQ;
    		gpio.irq_cb = jd9261t_irq_cb;
    		luat_gpio_setup(&gpio);
    	}
    }
    else
    {
    	LLOGI("TP not work");
    }
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
