#include "luat_base.h"
#include "luat_lcd.h"
#include "luat_gpio.h"
#include "luat_mem.h"
#include "luat_rtos.h"
#include "luat_tp.h"
#define LUAT_LOG_TAG "jd9261t-tp"
#include "luat_log.h"

typedef struct
{
	luat_tp_config_t* config;
	luat_rtos_timer_t scan_timer;
	uint8_t is_inited;
	uint8_t scan_cnt;
	uint8_t scan_time;
	uint8_t is_pressed;
}jd9261t_tp_ctrl_t;

static jd9261t_tp_ctrl_t jd9261t_tp;

static int tp_jd9261t_read(luat_tp_config_t* luat_tp_config, luat_tp_data_t *luat_tp_data)
{
	uint16_t tp_x, tp_y;
	int res;
	uint8_t pressed = 0;
	uint8_t buff[60];
	buff[0] = 0x20;
	buff[1] = 0x01;
	buff[2] = 0x11;
	buff[3] = 0x20;
	res = luat_i2c_send(luat_tp_config->i2c_id, 0x68, buff, 4, 1);
	if (res)
	{
		res = luat_i2c_send(luat_tp_config->i2c_id, 0x68, buff, 4, 1);
		if (res)
		{
			LLOGE("TP read point failed");
			return -1;
		}
	}
	luat_timer_us_delay(15);
	res = luat_i2c_recv(luat_tp_config->i2c_id, 0x68, buff, 60);
	if (res)
	{
		res = luat_i2c_recv(luat_tp_config->i2c_id, 0x68, buff, 60);
		if (res)
		{
			LLOGE("TP read point failed");
			return -1;
		}
	}
	if (!buff[0]) return -1;
	memset(luat_tp_data, 0, sizeof(luat_tp_data_t) * LUAT_TP_TOUCH_MAX);
	for (uint8_t i = 0; i < 10; i++)
	{
		if (buff[i * 5 + 3] != 0xff)
		{
			//LLOGI("%d, %x %x %x %x", i * 5 + 3, buff[i * 5 + 3], buff[i * 5 + 4], buff[i * 5 + 5], buff[i * 5 + 6]);
			tp_x = buff[i * 5 + 3];
			tp_x = (tp_x << 8) | buff[i * 5 + 4];
			tp_y = buff[i * 5 + 5];
			tp_y = (tp_y << 8) | buff[i * 5 + 6];
			if (tp_x < luat_tp_config->w && tp_y < luat_tp_config->h)
			{
				LLOGI("TP point %d x %d y %d", i+1, tp_x, tp_y);
				luat_tp_data[pressed].event = TP_EVENT_TYPE_DOWN;
				luat_tp_data[pressed].x_coordinate = tp_x;
				luat_tp_data[pressed].y_coordinate = tp_y;
				pressed++;
				if (pressed >= LUAT_TP_TOUCH_MAX)
				{
					return pressed;
				}
			}
			else
			{
				return pressed;
			}
		}
		else
		{
			return pressed;
		}
	}
	return pressed;
}

static LUAT_RT_RET_TYPE jd9261t_scan_once(LUAT_RT_CB_PARAM)
{
	jd9261t_tp.scan_cnt++;
    luat_tp_config_t* luat_tp_config = (luat_tp_config_t*)param;
    luat_rtos_message_send(luat_tp_config->task_handle, 1, luat_tp_config);
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
		luat_start_rtos_timer(jd9261t_tp.scan_timer, jd9261t_tp.scan_time, 1);
	}
	return 0;
}

static int tp_jd9261t_inited_init(luat_tp_config_t* luat_tp_config)
{
	if (jd9261t_tp.is_inited) return -1;
	uint8_t ID[4];
	ID[0] = 0x40;
	ID[1] = 0x00;
	ID[2] = 0x80;
	ID[3] = 0x76;
    if (luat_tp_config->soft_i2c != NULL){
        i2c_soft_setup(luat_tp_config->soft_i2c);
    }else{
        luat_i2c_setup(luat_tp_config->i2c_id, I2C_SPEED_SLOW);
    }

	if (luat_i2c_transfer(luat_tp_config->i2c_id, 0x68, ID, 4, ID, 2))
	{
		LLOGE("TP not detect");
	}
	else
	{
		if (luat_tp_config->refresh_rate < 10)
		{
			luat_tp_config->refresh_rate = 10;
		}
		if (luat_tp_config->refresh_rate > 50)
		{
			luat_tp_config->refresh_rate = 50;
		}
		jd9261t_tp.scan_time = (1000 / luat_tp_config->refresh_rate);
		LLOGI("TP detect %02x%02x, refresh time %dms", ID[1], ID[0], jd9261t_tp.scan_time);
		jd9261t_tp.config = luat_tp_config;
		jd9261t_tp.scan_cnt = 100;
		jd9261t_tp.scan_timer = luat_create_rtos_timer(jd9261t_scan_once, NULL, NULL);
		luat_gpio_t gpio = {0};
		gpio.pin = luat_tp_config->pin_int;
		gpio.mode = LUAT_GPIO_IRQ;
		gpio.alt_func = -1;
		gpio.pull = (luat_tp_config->int_type == LUAT_GPIO_FALLING_IRQ)?LUAT_GPIO_PULLUP:LUAT_GPIO_PULLDOWN;
		gpio.irq = luat_tp_config->int_type;
		gpio.irq_cb = jd9261t_irq_cb;
		luat_gpio_setup(&gpio);
		jd9261t_tp.is_inited = 1;
	}
    return 0;
}

static int tp_jd9261t_deinit(luat_tp_config_t* luat_tp_config){
	jd9261t_tp.is_inited = 0;
    if (luat_tp_config->pin_int != LUAT_GPIO_NONE){
        luat_gpio_close(luat_tp_config->pin_int);
    }
    if (luat_tp_config->pin_rst != LUAT_GPIO_NONE){
        luat_gpio_close(luat_tp_config->pin_rst);
    }
    return 0;
}

static void tp_jd9261t_read_done(luat_tp_config_t * luat_tp_config)
{

}

luat_tp_opts_t tp_config_jd9261t_inited = {
    .name = "jd9261t_inited",
    .init = tp_jd9261t_inited_init,
    .deinit = tp_jd9261t_deinit,
    .read = tp_jd9261t_read,
	.read_done = tp_jd9261t_read_done,
};
