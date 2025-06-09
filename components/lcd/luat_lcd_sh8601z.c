#include "luat_base.h"
#include "luat_lcd.h"

#define LUAT_LOG_TAG "sh8601z"
#include "luat_log.h"

static const uint16_t sh8601z_init_cmds[] = {
    // 发送初始化命令
    0x023a,0x0355,
	0x0253,0x0320,
    0x0235,0x0300,
    0x0251,0x03ff,
};


static int sh8601z_inited_init(luat_lcd_conf_t* conf)
{
	luat_lcd_qspi_conf_t auto_flush =
	{
			.write_4line_cmd = 0x32,
			.vsync_reg = 0x61,
			.hsync_cmd = 0xde,
			.hsync_reg = 0x60,
			.write_1line_cmd = 0x02,
			.write_4line_data = 0x12,
	};
    luat_lcd_qspi_config(conf, &auto_flush);	//必须在第一个命令发送前就准备好
    return luat_lcd_init_default(conf);
}

luat_lcd_opts_t lcd_opts_sh8601z = {
    .name = "jd9261t_inited",
    .init_cmds_len = sizeof(sh8601z_init_cmds)/sizeof(sh8601z_init_cmds[0]),
    .init_cmds = sh8601z_init_cmds,
    .direction0 = 0x00,
    .direction90 = 0x00,
    .direction180 = 0x40,
    .direction270 = 0x40,
	.rb_swap = 1,
	.user_ctrl_init = sh8601z_inited_init,
};
