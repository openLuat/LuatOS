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
			.write_4line_data = 0,
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
    .sleep_cmd = 0xff,			//不需要发命令
    .wakeup_cmd = 0xff,			//不需要发命令
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

#if 0
typedef struct
{
	union
	{
		uint8_t *queue;	//data超过4个字节放地址
		uint8_t buf[4];	//不超过4个字节的，直接放值
	};
	uint8_t delay_ms;
	uint8_t ignore_mask;
	uint8_t len;
	uint8_t cmd;
}spi_lcd_cmd_t;

#define Q_540_MASK	(0)

static const uint8_t data_for_cmd_b2_jd9261t[] = {0x01, 0x23, 0x62, 0x88, 0xE4, 0x1B};
static const uint8_t data_for_cmd_bb_jd9261t[] = {0x0C, 0x54, 0x5A, 0x50, 0x22, 0x22};
static const uint8_t data_for_cmd_c3_jd9261t[] = {0x0D, 0x02, 0x06, 0x00, 0x00, 0x95, 0xFF, 0xFF, 0xFF, 0xFF, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
		0x00, 0x00, 0x00, 0x10, 0x00, 0x10, 0x00, 0x10}; //24
static const uint8_t data_for_cmd_c6_jd9261t[] = {0x01, 0x6E, 0x00, 0x30, 0x00, 0x14, 0x16, 0x82, 0x00, 0x10, 0x00, 0x10, 0x00, 0x09, 0x00, 0x00,
		0x00, 0x00, 0x00, 0x03, 0x00, 0x00, 0x01};	//23
static const uint8_t data_for_cmd_cb_jd9261t[] = {0x7C, 0x6C, 0x5F, 0x4C, 0x3E, 0x34, 0x28, 0x2D, 0x19, 0x36, 0x38, 0x3B, 0x59, 0x47, 0x4F, 0x42,
		0x40, 0x33, 0x22, 0x15, 0x06, 0x7C, 0x6C, 0x5F, 0x4C, 0x3E, 0x34, 0x28, 0x2D, 0x19, 0x36, 0x38,
		0x3B, 0x59, 0x47, 0x4F, 0x42, 0x40, 0x33, 0x22, 0x15, 0x06};	//42

static const uint8_t data_for_cmd_ce_jd9261t[] = {0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0xFF, 0x00, 0x00,
		0x00, 0x00, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF,
		0xFF, 0xFF, 0xFF};	//35

static const uint8_t data_for_cmd_cf_jd9261t[] = {0x52, 0x00, 0x00, 0xFF, 0xFF, 0x18, 0x00, 0x00, 0x00, 0xFF, 0xFF, 0x18, 0x00}; //13
static const uint8_t data_for_cmd_d0_jd9261t[] = {0x00, 0x9F, 0x9F, 0x80, 0x9B, 0x99, 0x8E, 0x8C, 0x8A, 0x88, 0x86, 0x84, 0x98, 0x97, 0x90, 0x92,
		0x9F, 0x9F}; //18
static const uint8_t data_for_cmd_d1_jd9261t[] = {0x00, 0x9F, 0x9F, 0x81, 0x9C, 0x9A, 0x8F, 0x8D, 0x8B, 0x89, 0x87, 0x85, 0x98, 0x97, 0x91, 0x93,
		0x9F, 0x9F}; //18
static const uint8_t data_for_cmd_d2_jd9261t[] = {0x00, 0x9F, 0x9F, 0x91, 0x8D, 0x8F, 0x9A, 0x9C, 0x85, 0x87, 0x89, 0x8B, 0x18, 0x17, 0x81, 0x93,
		0x9F, 0x9F}; //18
static const uint8_t data_for_cmd_d3_jd9261t[] = {0x00, 0x9F, 0x9F, 0x90, 0x8C, 0x8E, 0x99, 0x9B, 0x84, 0x86, 0x88, 0x8A, 0x18, 0x17, 0x80, 0x92,
		0x9F, 0x9F}; //18
static const uint8_t data_for_cmd_d4_jd9261t[] = {0x00, 0x60, 0x23, 0x01, 0x00, 0x03, 0x20, 0x01, 0x00, 0x00, 0x00, 0x04, 0x04, 0x00, 0x04, 0x63,
		0x05, 0x04, 0x6A, 0x05, 0x60, 0x60, 0x04, 0x04, 0x20, 0x00, 0x23, 0x01, 0x03, 0x00, 0x23, 0x00,
		0x01, 0x04, 0x4D, 0x04, 0x4D, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x12, 0x00, 0x00,
		0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x40, 0x00, 0x00, 0x00, 0x00};	//60

static const uint8_t data_for_cmd_d5_jd9261t[] = {0x01, 0x10, 0x01, 0x00, 0x01, 0x00, 0x00, 0x00, 0x00, 0xA0, 0x00, 0x00, 0x00, 0x07, 0x32, 0x5A,
		0x00, 0x0A, 0x3C, 0x00, 0x04, 0x04, 0x7B, 0xF4, 0xA0, 0x27, 0x00, 0x00, 0x08, 0xF4, 0x27, 0x08,
		0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x02};	//39
static const uint8_t data_for_cmd_d7_jd9261t[] = {0x00, 0x6E, 0x6E, 0x6E, 0x6E, 0x6E, 0x6E, 0x6E, 0x6E, 0x6E, 0x6E, 0x6E, 0x6E, 0x6E, 0x6E, 0x6E,
		0x6E}; //17
static const uint8_t data_for_cmd_ca1_jd9261t[] = {0x76, 0x00, 0x00, 0x00, 0x2C, 0x00, 0xD0, 0xD0, 0x22, 0x1C, 0x1C, 0x22, 0xAB, 0xAA, 0x00, 0x00,
		0x04, 0x1C, 0x32, 0x12, 0x44, 0x3F, 0x0F, 0x00, 0x00, 0x00, 0x22, 0x19, 0x02, 0x02, 0x00, 0x00,
		0x00, 0x00, 0x04, 0x03, 0x00, 0xAA, 0x04, 0x25, 0xA0, 0x00, 0x00, 0x00, 0x00, 0x10, 0x01, 0x21,
		0x03, 0x3F, 0x10, 0x03, 0x00, 0x01, 0x00, 0x00, 0x78, 0x12, 0x40, 0x3C, 0x94, 0x19, 0x19, 0x14,
		0x29, 0x19, 0x80};	//67
static const uint8_t data_for_cmd_cb1_jd9261t[] = {0x02, 0x1C, 0x00, 0x00, 0x00, 0x02, 0x00, 0x81, 0x00, 0x02, 0x00, 0xD0, 0xD0, 0x22}; //14

static const uint8_t data_for_cmd_cc1_jd9261t[] = {0x00, 0x00, 0xFF, 0xFF, 0x5F, 0x7F, 0x14, 0x00, 0x00, 0x00, 0x40, 0x22, 0x71, 0x62, 0x35, 0x17,
		0x26, 0x53, 0x35, 0x62, 0x71, 0x71, 0x26, 0x17, 0x71, 0x62, 0x35, 0x17, 0x26, 0x53, 0x35, 0x62,
		0x71, 0x71, 0x26, 0x17};	//36
static const uint8_t data_for_cmd_bb2_jd9261t[] = {0x00, 0x00, 0x00, 0x00, 0x68, 0x69, 0x00, 0x00};
static const uint8_t data_for_cmd_c12_jd9261t[] = {0x00, 0x40, 0x00, 0x00, 0x00, 0x02, 0x02, 0x02, 0x00, 0x00};
static const uint8_t data_for_cmd_c22_jd9261t[] = {0x02, 0xC2, 0x50, 0x00, 0x12, 0xA2, 0x61, 0x73, 0xF7};
static const uint8_t data_for_cmd_c32_jd9261t[] = {0x20, 0xFF, 0x00, 0xA0, 0x10, 0x82, 0x06, 0x01, 0x31, 0x53, 0x64, 0x75, 0x6E, 0x82};
static const uint8_t data_for_cmd_c42_jd9261t[] = {0x00, 0x21, 0x07, 0x00, 0x01, 0x01, 0x08};
static const uint8_t data_for_cmd_d32_jd9261t[] = {0x00, 0x11, 0x00, 0x02, 0x68, 0xAE, 0x14, 0x59, 0xCD, 0x02, 0x68, 0xAE, 0x14, 0x59, 0xCD};
static const uint8_t data_for_cmd_ec2_jd9261t[] = {0x03, 0x0E, 0x7E, 0x77, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0xF1, 0xFF, 0xFF, 0x00, 0x00, 0x00,
		0x00, 0x00, 0xFF, 0x00, 0xFF, 0x01, 0x7F}; //23
static const uint8_t data_for_cmd_d13_jd9261t[] = {0x00, 0x10, 0x21, 0xFF, 0x88, 0x00, 0x87};
static const spi_lcd_cmd_t cmd_list_jd9261t_all[] =
{
		{
				.cmd = 0xDF,
				.len = 3,
				.buf = {0x90,0x62,0xF2},
		},
		{
				.cmd = 0xDE,
				.len = 1,
				.buf = {0x00},
		},
		{
				.cmd = 0xB2,
				.len = sizeof(data_for_cmd_b2_jd9261t),
				.queue = (uint8_t *)data_for_cmd_b2_jd9261t,
		},
		{
				.cmd = 0xBB,
				.len = sizeof(data_for_cmd_bb_jd9261t),
				.queue = (uint8_t *)data_for_cmd_bb_jd9261t,
		},
		{
				.cmd = 0xBD,
				.len = 2,
				.buf = {0x00,0x71},
		},
		{
				.cmd = 0xBF,
				.len = 2,
				.buf = {0x50,0x50},
		},
		{
				.cmd = 0xC0,
				.len = 4,
				.buf = {0x00,0xCD,0x00,0xCD},
		},
		{
				.cmd = 0xC1,
				.len = 3,
				.buf = {0x40,0x11,0x00},
		},
		{
				.cmd = 0xC3,
				.len = sizeof(data_for_cmd_c3_jd9261t),
				.queue = (uint8_t *)data_for_cmd_c3_jd9261t,
		},
		{
				.cmd = 0xC4,
				.len = 2,
				.buf = {0x02,0x06},
		},
		{
				.cmd = 0xC6,
				.len = sizeof(data_for_cmd_c6_jd9261t),
				.queue = (uint8_t *)data_for_cmd_c6_jd9261t,
		},
		{
				.cmd = 0xC8,
				.len = 3,
				.buf = {0x18,0x0E,0x87},
		},
		{
				.cmd = 0xCB,
				.len = sizeof(data_for_cmd_cb_jd9261t),
				.queue = (uint8_t *)data_for_cmd_cb_jd9261t,
		},
		{
				.cmd = 0xCC,
				.len = 1,
				.buf = {0x33},
		},
		{
				.cmd = 0xCD,
				.len = 4,
				.buf = {0x08,0x00,0x08,0x00},
		},
		{
				.cmd = 0xCE,
				.len = sizeof(data_for_cmd_ce_jd9261t),
				.queue = (uint8_t *)data_for_cmd_ce_jd9261t,
		},
		{
				.cmd = 0xCF,
				.len = sizeof(data_for_cmd_cf_jd9261t),
				.queue = (uint8_t *)data_for_cmd_cf_jd9261t,
		},
		{
				.cmd = 0xD0,
				.len = sizeof(data_for_cmd_d0_jd9261t),
				.queue = (uint8_t *)data_for_cmd_d0_jd9261t,
		},
		{
				.cmd = 0xD2,
				.len = sizeof(data_for_cmd_d2_jd9261t),
				.queue = (uint8_t *)data_for_cmd_d2_jd9261t,
		},
		{
				.cmd = 0xD3,
				.len = sizeof(data_for_cmd_d3_jd9261t),
				.queue = (uint8_t *)data_for_cmd_d3_jd9261t,
		},
		{
				.cmd = 0xD4,
				.len = sizeof(data_for_cmd_d4_jd9261t),
				.queue = (uint8_t *)data_for_cmd_d4_jd9261t,
		},
		{
				.cmd = 0xD5,
				.len = sizeof(data_for_cmd_d5_jd9261t),
				.queue = (uint8_t *)data_for_cmd_d5_jd9261t,
		},
		{
				.cmd = 0xD7,
				.len = sizeof(data_for_cmd_d7_jd9261t),
				.queue = (uint8_t *)data_for_cmd_d7_jd9261t,
		},
		{
				.cmd = 0xDE,
				.len = 1,
				.buf = {0x01},
		},
		{
				.cmd = 0xC7,
				.len = 3,
				.buf = {0x06,0x06,0x08},
		},
		{
				.cmd = 0xCA,
				.len = sizeof(data_for_cmd_ca1_jd9261t),
				.queue = (uint8_t *)data_for_cmd_ca1_jd9261t,
				.ignore_mask = (1 << Q_540_MASK),
		},
		{
				.cmd = 0xCB,
				.len = sizeof(data_for_cmd_cb1_jd9261t),
				.queue = (uint8_t *)data_for_cmd_cb1_jd9261t,
				.ignore_mask = (1 << Q_540_MASK),
		},
		{
				.cmd = 0xCC,
				.len = sizeof(data_for_cmd_cc1_jd9261t),
				.queue = (uint8_t *)data_for_cmd_cc1_jd9261t,
				.ignore_mask = (1 << Q_540_MASK),
		},
		{
				.cmd = 0xDE,
				.len = 1,
				.buf = {0x02},
		},
		{
				.cmd = 0xBB,
				.len = sizeof(data_for_cmd_bb2_jd9261t),
				.queue = (uint8_t *)data_for_cmd_bb2_jd9261t,
		},
		{
				.cmd = 0xC1,
				.len = sizeof(data_for_cmd_c12_jd9261t),
				.queue = (uint8_t *)data_for_cmd_c12_jd9261t,
		},
		{
				.cmd = 0xC2,
				.len = sizeof(data_for_cmd_c22_jd9261t),
				.queue = (uint8_t *)data_for_cmd_c22_jd9261t,
		},
		{
				.cmd = 0xC3,
				.len = sizeof(data_for_cmd_c32_jd9261t),
				.queue = (uint8_t *)data_for_cmd_c32_jd9261t,
		},
		{
				.cmd = 0xC4,
				.len = sizeof(data_for_cmd_c42_jd9261t),
				.queue = (uint8_t *)data_for_cmd_c42_jd9261t,
		},
		{
				.cmd = 0xC6,
				.len = 1,
				.buf = {0x4C},
		},
		{
				.cmd = 0xD3,
				.len = sizeof(data_for_cmd_d32_jd9261t),
				.queue = (uint8_t *)data_for_cmd_d32_jd9261t,
		},
		{
				.cmd = 0xE6,
				.len = 3,
				.buf = {0x10, 0x08, 0x63},
		},
		{
				.cmd = 0xEC,
				.len = sizeof(data_for_cmd_ec2_jd9261t),
				.queue = (uint8_t *)data_for_cmd_ec2_jd9261t,
		},
		{
				.cmd = 0xDE,
				.len = 1,
				.buf = {0x03},
		},
		{
				.cmd = 0xD0,
				.len = 4,
				.buf = {0x00, 0x45, 0x31, 0x11},
		},
		{
				.cmd = 0xD1,
				.len = sizeof(data_for_cmd_d13_jd9261t),
				.queue = (uint8_t *)data_for_cmd_d13_jd9261t,
		},
		{
				.cmd = 0xDE,
				.len = 1,
				.buf = {0x00},
		},
//		{
//				.cmd = 0x35,
//				.len = 0,
//				.delay_ms = 30,
//		},
//		{
//				.cmd = 0x3A,
//				.len = 1,
//				.buf = {0x50},
//		},
//		{
//				.cmd = 0x11,
//				.len = 0,
//				.delay_ms = 120,
//		},
//		{
//				.cmd = 0x29,
//				.len = 0,
//				.delay_ms = 120,
//		},
};


static int jd9261t_init(luat_lcd_conf_t* conf)
{
    uint8_t ignore_mask = 0;

    if (540 == conf->w && 540 == conf->h)
    {
    	ignore_mask |= (1 << Q_540_MASK);
    }
    else if (720 == conf->w && 720 == conf->h)
    {

    }
    else
    {
    	LLOGE("no support");
    	return -1;
    }
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
			.write_4line_data = 0,
	};
    luat_gpio_set(conf->pin_rst, Luat_GPIO_LOW);
//    luat_rtos_task_sleep(5);
//    luat_gpio_set(conf->tp_pin_rst, Luat_GPIO_HIGH);
    luat_rtos_task_sleep(5);
    luat_gpio_set(conf->pin_rst, Luat_GPIO_HIGH);
    luat_rtos_task_sleep(150);
    luat_lcd_qspi_config(conf, &auto_flush);	//必须在第一个命令发送前就准备好

	for(int i = 0; i < sizeof(cmd_list_jd9261t_all)/sizeof(spi_lcd_cmd_t); i++)
	{
		if (cmd_list_jd9261t_all[i].ignore_mask & ignore_mask)
		{
			LLOGI("ignore cmd %x", cmd_list_jd9261t_all[i].cmd);
		}
		else
		{

			if (cmd_list_jd9261t_all[i].len > 4)
			{
				lcd_write_cmd_data(conf,cmd_list_jd9261t_all[i].cmd, cmd_list_jd9261t_all[i].queue, cmd_list_jd9261t_all[i].len);
			}
			else
			{
				lcd_write_cmd_data(conf,cmd_list_jd9261t_all[i].cmd, cmd_list_jd9261t_all[i].buf, cmd_list_jd9261t_all[i].len);
			}
		}
	}
	luat_lcd_set_direction(conf,conf->direction);

	uint8_t temp = 0x60;
//	lcd_write_cmd_data(conf,0xc2, &temp, 1);
	lcd_write_cmd_data(conf,0x35, NULL, 0);
	temp = 0x50;
	lcd_write_cmd_data(conf,0x3a, &temp, 1);
	lcd_write_cmd_data(conf,0x11, NULL, 0);
	luat_rtos_task_sleep(120);
	lcd_write_cmd_data(conf,0x29, NULL, 0);
	luat_rtos_task_sleep(120);
    luat_gpio_set(conf->pin_pwr, Luat_GPIO_HIGH);
    luat_lcd_qspi_auto_flush_on_off(conf, 1);
    return 0;
}

luat_lcd_opts_t lcd_opts_jd9261t = {
    .name = "jd9261t",
    .sleep_cmd = 0xff,			//不需要发命令
    .wakeup_cmd = 0xff,			//不需要发命令
    .init_cmds_len = 0,
    .init_cmds = NULL,
    .direction0 = 0x00,
    .direction90 = 0x00,
    .direction180 = 0x03,
    .direction270 = 0x03,
	.rb_swap = 1,
	.no_ram_mode = 1,
	.user_ctrl_init = jd9261t_init,
};

#endif
