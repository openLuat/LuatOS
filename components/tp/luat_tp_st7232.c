#include "luat_base.h"
#include "luat_gpio.h"
#include "luat_mem.h"
#include "luat_rtos.h"
#include "luat_tp.h"
#include <string.h>
#define LUAT_LOG_TAG "st7232-tp"
#include "luat_log.h"

/* 寄存器读命令帧：寄存器大端 4 字节 + 读长大端 2 字节，共 6 字节 */
#define ST7232_CMD_LEN         6
#define ST7232_ADDR            0x68
#define ST7232_REG_PRODUCT_ID  0x40008076
#define ST7232_REG_REPORT      0x20011120
/* 报点区：3 字节头 + 每指 5 字节，实测读长 21 字节 */
#define ST7232_HEAD_LEN        3
#define ST7232_POINT_LEN       5
#define ST7232_REPORT_LEN      (ST7232_HEAD_LEN + 3 * ST7232_POINT_LEN)
#define ST7232_MAX_POINT       ((ST7232_REPORT_LEN - ST7232_HEAD_LEN) / ST7232_POINT_LEN)
#define ST7232_POINT_EMPTY     0xff
#define ST7232_RATE_DEFAULT_HZ 50
#define ST7232_RATE_MIN_HZ     10
#define ST7232_RATE_MAX_HZ     100

typedef struct
{
	luat_tp_config_t* config;
	luat_rtos_timer_t scan_timer;
	uint16_t active_mask;
	uint8_t is_inited;
	uint8_t scan_time;
}st7232_tp_ctrl_t;

static st7232_tp_ctrl_t st7232_tp;

/* 拼寄存器读命令帧 */
static void tp_st7232_cmd(uint8_t* cmd, uint32_t reg, uint16_t len)
{
	cmd[0] = (uint8_t)(reg >> 24);
	cmd[1] = (uint8_t)(reg >> 16);
	cmd[2] = (uint8_t)(reg >> 8);
	cmd[3] = (uint8_t)(reg >> 0);
	cmd[4] = (uint8_t)(len >> 8);
	cmd[5] = (uint8_t)(len >> 0);
}

/* 一次 transfer 读寄存器，写命令转读数据中间发 repeated start */
static int tp_st7232_read_reg(luat_tp_config_t* luat_tp_config, uint32_t reg, uint8_t* buff, uint16_t len)
{
	uint8_t cmd[ST7232_CMD_LEN];
	tp_st7232_cmd(cmd, reg, len);
	if (luat_tp_config->soft_i2c != NULL){
		i2c_soft_send(luat_tp_config->soft_i2c, ST7232_ADDR, (char*)cmd, ST7232_CMD_LEN, 0);
		return i2c_soft_recv(luat_tp_config->soft_i2c, ST7232_ADDR, (char*)buff, len);
	}else{
		return luat_i2c_transfer(luat_tp_config->i2c_id, ST7232_ADDR, cmd, ST7232_CMD_LEN, buff, len);
	}
}

static void tp_st7232_pin_output(int pin, int level)
{
	luat_gpio_t gpio = {0};
	gpio.pin = pin;
	gpio.mode = LUAT_GPIO_OUTPUT;
	gpio.pull = LUAT_GPIO_DEFAULT;
	gpio.alt_func = -1;
	gpio.irq = LUAT_GPIO_NO_IRQ;
	luat_gpio_setup(&gpio);
	luat_gpio_set(pin, level);
}

/* 驱动触摸复位脚与模式脚时序，让芯片退出复位并进正常工作模式 */
static void tp_st7232_reset(luat_tp_config_t* luat_tp_config)
{
	int pin_rst = luat_tp_config->pin_rst;
	int pin_int = luat_tp_config->pin_int;
	if (pin_rst == LUAT_GPIO_NONE) return;
	tp_st7232_pin_output(pin_rst, LUAT_GPIO_LOW);
	if (pin_int != LUAT_GPIO_NONE)
	{
		tp_st7232_pin_output(pin_int, LUAT_GPIO_LOW);
		luat_gpio_set(pin_int, LUAT_GPIO_HIGH);
	}
	luat_rtos_task_sleep(5);
	luat_gpio_set(pin_rst, LUAT_GPIO_HIGH);
	luat_rtos_task_sleep(5);
	luat_gpio_set(pin_rst, LUAT_GPIO_LOW);
	luat_rtos_task_sleep(50);
	luat_gpio_set(pin_rst, LUAT_GPIO_HIGH);
	luat_rtos_task_sleep(100);
}

/* 读报点区，解析当前触点并给消失的触点补抬手事件 */
static int tp_st7232_read(luat_tp_config_t* luat_tp_config, luat_tp_data_t* luat_tp_data)
{
	uint8_t buff[ST7232_REPORT_LEN];
	uint16_t now_mask = 0;
	uint16_t released;
	uint8_t count;
	uint8_t used = 0;

	memset(luat_tp_data, 0, sizeof(luat_tp_data_t) * LUAT_TP_TOUCH_MAX);
	if (tp_st7232_read_reg(luat_tp_config, ST7232_REG_REPORT, buff, ST7232_REPORT_LEN))
	{
		if (tp_st7232_read_reg(luat_tp_config, ST7232_REG_REPORT, buff, ST7232_REPORT_LEN))
		{
			LLOGE("TP read point failed");
			return -1;
		}
	}
	count = buff[0];
	if (count > ST7232_MAX_POINT) count = 0;
	for (uint8_t i = 0; i < count && used < LUAT_TP_TOUCH_MAX; i++)
	{
		uint8_t* point = buff + ST7232_HEAD_LEN + i * ST7232_POINT_LEN;
		uint16_t tp_x, tp_y;
		if (point[0] == ST7232_POINT_EMPTY) break;
		tp_x = ((uint16_t)point[0] << 8) | point[1];
		tp_y = ((uint16_t)point[2] << 8) | point[3];
		if (tp_x >= luat_tp_config->w || tp_y >= luat_tp_config->h) break;
		luat_tp_data[used].event = TP_EVENT_TYPE_DOWN;
		luat_tp_data[used].track_id = i;
		luat_tp_data[used].x_coordinate = tp_x;
		luat_tp_data[used].y_coordinate = tp_y;
		luat_tp_data[used].width = point[4] ? point[4] : 1;
		now_mask |= (uint16_t)1 << i;
		used++;
	}
	released = st7232_tp.active_mask & ~now_mask;
	for (uint8_t i = 0; i < ST7232_MAX_POINT && used < LUAT_TP_TOUCH_MAX; i++)
	{
		if (!(released & ((uint16_t)1 << i))) continue;
		luat_tp_data[used].event = TP_EVENT_TYPE_UP;
		luat_tp_data[used].track_id = i;
		used++;
	}
	st7232_tp.active_mask = now_mask;
	return used;
}

/* 轮询定时器到点，向 tp 任务投一次取点消息 */
static LUAT_RT_RET_TYPE st7232_scan_once(LUAT_RT_CB_PARAM)
{
    luat_tp_config_t* luat_tp_config = (luat_tp_config_t*)param;
    if (luat_tp_config != NULL && luat_tp_config->task_handle != NULL)
    {
        luat_rtos_message_send(luat_tp_config->task_handle, 1, luat_tp_config);
    }
}

static int tp_st7232_init(luat_tp_config_t* luat_tp_config)
{
	if (st7232_tp.is_inited) return -1;
	uint8_t ID[2] = {0};

    if (luat_tp_config->soft_i2c != NULL){
        i2c_soft_setup(luat_tp_config->soft_i2c);
    }else{
        luat_i2c_setup(luat_tp_config->i2c_id, I2C_SPEED_SLOW);
    }
	tp_st7232_reset(luat_tp_config);

	if (tp_st7232_read_reg(luat_tp_config, ST7232_REG_PRODUCT_ID, ID, 2))
	{
		LLOGE("TP not detect");
	}
	else
	{
		LLOGI("TP detect %02x%02x", ID[0], ID[1]);
	}
	if (luat_tp_config->refresh_rate == 0)
	{
		luat_tp_config->refresh_rate = ST7232_RATE_DEFAULT_HZ;
	}
	if (luat_tp_config->refresh_rate < ST7232_RATE_MIN_HZ)
	{
		luat_tp_config->refresh_rate = ST7232_RATE_MIN_HZ;
	}
	if (luat_tp_config->refresh_rate > ST7232_RATE_MAX_HZ)
	{
		luat_tp_config->refresh_rate = ST7232_RATE_MAX_HZ;
	}
	st7232_tp.scan_time = (1000 / luat_tp_config->refresh_rate);
	st7232_tp.config = luat_tp_config;
	st7232_tp.active_mask = 0;
	st7232_tp.scan_timer = luat_create_rtos_timer(st7232_scan_once, st7232_tp.config, NULL);
	luat_start_rtos_timer(st7232_tp.scan_timer, st7232_tp.scan_time, 1);
	st7232_tp.is_inited = 1;
    return 0;
}

static int tp_st7232_deinit(luat_tp_config_t* luat_tp_config)
{
	st7232_tp.is_inited = 0;
	st7232_tp.active_mask = 0;
	if (st7232_tp.scan_timer != NULL)
	{
		luat_stop_rtos_timer(st7232_tp.scan_timer);
		st7232_tp.scan_timer = NULL;
	}
    if (luat_tp_config->pin_int != LUAT_GPIO_NONE){
        luat_gpio_close(luat_tp_config->pin_int);
    }
    if (luat_tp_config->pin_rst != LUAT_GPIO_NONE){
        luat_gpio_close(luat_tp_config->pin_rst);
    }
    return 0;
}

luat_tp_opts_t tp_config_st7232 = {
    .name = "st7232",
    .init = tp_st7232_init,
    .deinit = tp_st7232_deinit,
    .read = tp_st7232_read,
};
