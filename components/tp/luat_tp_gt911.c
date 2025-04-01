#include "luat_base.h"
#include "luat_tp.h"
#include "luat_gpio.h"
#include "luat_mem.h"
#include "luat_rtos.h"
#include "luat_tp_reg.h"

#define LUAT_LOG_TAG "gt911"
#include "luat_log.h"

#define GT911_ADDRESS0              (0x5D)
#define GT911_ADDRESS1              (0x14)

#define GT911_PRODUCT_ID_CODE       (0x00313139)  // "911" ASCII code

#define GT911_COMMAND_REG           (0x8040)

#define GT911_CONFIG_REG            (0x8047)
#define GT911_CONFIG_VERSION        (0x8047)
#define GT911_X_OUTPUT_MAX          (0x8048)
#define GT911_Y_OUTPUT_MAX          (0x804A)
#define GT911_TOUCH_NUMBER          (0x804C)
#define GT911_MODULE_SWITCH1        (0x804D)
#define GT911_MODULE_SWITCH2        (0x804E)
#define GT911_SHAKE_COUNT           (0x804F)
#define GT911_FILTER                (0x8050)
#define GT911_LARGE_TOUCH           (0x8051)
#define GT911_NOISE_REDUCTION       (0x8052)
#define GT911_SCREEN_TOUCH_LEVEL    (0x8053)
#define GT911_SCREEN_LEVEL_TOUCH    (0x8054)
#define GT911_LOW_POWER_CONTROL     (0x8055)
#define GT911_REFRESH_RATE          (0x8056)
#define GT911_X_THRESHOLD           (0x8057)
#define GT911_Y_THRESHOLD           (0x8058)
#define GT911_X_SPEED_LIMIT         (0x8059)
#define GT911_Y_SPEED_LIMIT         (0x805A)
#define GT911_SPACE                 (0x805B)
#define GT911_STRETCH_RATE          (0x805D)
#define GT911_STRETCH_R0            (0x805E)
#define GT911_STRETCH_R1            (0x805F)
#define GT911_STRETCH_R2            (0x8060)
#define GT911_STRETCH_RM            (0x8061)
#define GT911_DRV_GROUPA_NUM        (0x8062)
#define GT911_DRV_GROUPB_NUM        (0x8063)
#define GT911_SENSOR_NUM            (0x8064)
#define GT911_FREQA_FACTOR          (0x8065)
#define GT911_FREQB_FACTOR          (0x8066)
#define GT911_PANNEL_BITFREQL       (0x8067)
#define GT911_PANNEL_BITFREQH       (0x8068)
#define GT911_PANNEL_SENSOR_TIMEL   (0x8069)
#define GT911_PANNEL_SENSOR_TIMEH   (0x806A)
#define GT911_PANNEL_TX_GAIN        (0x806B)
#define GT911_PANNEL_RX_GAIN        (0x806C)

#define GT911_CHECK_SUM             (0x80FF)
#define GT911_CONFIG_FRESH          (0x8100)

#define GT911_PRODUCT_ID            (0x8140)
#define GT911_FIRMWARE_VERSION      (0x8144)
#define GT911_X_RESOLUTION          (0x8146)
#define GT911_Y_RESOLUTION          (0x8148)
#define GT911_VENDOR_ID             (0x814A)

#define GT911_STATUS                (0x814E)

#define GT911_POINT1_REG            (0x814F)
#define GT911_POINT2_REG            (0x8157)
#define GT911_POINT3_REG            (0x815F)
#define GT911_POINT4_REG            (0x8167)
#define GT911_POINT5_REG            (0x816F)

#define GT911_CONFIG_SIZE           (GT911_CONFIG_FRESH - GT911_CONFIG_REG + 1)
#define GT911_POINT_INFO_NUM        (8)
#define GT911_TOUCH_NUMBER_MIN      (1)
#define GT911_TOUCH_NUMBER_MAX      (5)

#define GT911_REFRESH_RATE_MIN      (5)
#define GT911_REFRESH_RATE_MAX      (20)

typedef struct luat_touch_info{
    union{
        struct {
            uint64_t version:8;
            uint64_t x_max:16;
            uint64_t y_max:16;
            uint64_t touch_num:4;
            uint64_t :4;
            uint64_t int_type:2;
            uint64_t :1;
            uint64_t x2y:1;
            uint64_t stretch_rank:2;
            uint64_t :2;
            uint64_t :8;
        };
        uint64_t info;
    };
}luat_tp_info_t;

static uint8_t gt911_init_state = 0;

// static uint8_t gt911_cfg_table[GT911_CONFIG_SIZE] ={
// // #if 1
// // 	0x41,0x20,0x03,0xe0,0x01,0x05,0x3d,0x00,0x01,0x08,0x28,0x05,0x50,0x32,0x03,0x05,
// // 	0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x18,0x1a,0x1f,0x14,0x8c,0x24,0x0a,0x1b,0x19,
// // 	0xf4,0x0a,0x00,0x00,0x00,0x21,0x04,0x1d,0x00,0x00,0x00,0x00,0x00,0x03,0x64,0x32,
// // 	0x00,0x00,0x00,0x11,0xb2,0x94,0xc5,0x02,0x07,0x00,0x00,0x04,0x8e,0x16,0x00,0x5d,
// // 	0x23,0x00,0x3d,0x38,0x00,0x2a,0x5a,0x00,0x22,0x90,0x00,0x22,0x00,0x00,0x00,0x00,
// // 	0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,
// // 	0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,
// // 	0x14,0x12,0x10,0x0e,0x0c,0x0a,0x08,0x06,0x04,0x02,0xff,0xff,0xff,0xff,0x00,0x00,
// // 	0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x1d,0x1c,
// // 	0x18,0x16,0x14,0x13,0x12,0x10,0x0f,0x0c,0x0a,0x08,0x06,0x04,0x02,0x00,0xff,0xff,
// // 	0xff,0xff,0xff,0xff,0xff,0xff,0xff,0xff,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,
// // 	0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x2a,0x00
// // #else
// // 	0x42,0x20,0x03,0xE0,0x01,0x01,0x3D,0x00,0x01,0x08,0x28,0x05,0x50,0x32,0x03,0x05,
// // 	0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x18,0x1A,0x1F,0x14,0x8C,0x24,0x0A,0x1B,0x19,
// // 	0xF4,0x0A,0x00,0x00,0x00,0x20,0x04,0x1C,0x00,0x00,0x00,0x00,0x00,0x03,0x64,0x32,
// // 	0x00,0x00,0x00,0x11,0xB2,0x94,0xC5,0x02,0x07,0x00,0x00,0x04,0x8E,0x16,0x00,0x5D,
// // 	0x23,0x00,0x3D,0x38,0x00,0x2A,0x5A,0x00,0x22,0x90,0x00,0x22,0x00,0x00,0x00,0x00,
// // 	0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,
// // 	0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,
// // 	0x14,0x12,0x10,0x0E,0x0C,0x0A,0x08,0x06,0x04,0x02,0xFF,0xFF,0xFF,0xFF,0xFF,0xFF,
// // 	0xFF,0xFF,0xFF,0xFF,0xFF,0xFF,0xFF,0xFF,0xFF,0xFF,0xFF,0xFF,0xFF,0xFF,0x1D,0x1C,
// // 	0x18,0x16,0x14,0x13,0x12,0x10,0x0F,0x0C,0x0A,0x08,0x06,0x04,0x02,0x00,0xFF,0xFF,
// // 	0xFF,0xFF,0xFF,0xFF,0xFF,0xFF,0xFF,0xFF,0xFF,0xFF,0xFF,0xFF,0xFF,0xFF,0xFF,0xFF,
// // 	0xFF,0xFF,0xFF,0xFF,0xFF,0xFF,0xFF,0xFF,0x4F,0x00
// // #endif

//     0x6b,0x00,0x04,0x58,0x02,0x05,0x0d,0x00,0x01,0x0f,0x28,0x0f,0x50,0x32,0x03,0x05,
//     0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x8a,0x2a,0x0c,0x45,0x47,
//     0x0c,0x08,0x00,0x00,0x00,0x40,0x03,0x2c,0x00,0x01,0x00,0x00,0x00,0x03,0x64,0x32,
//     0x00,0x00,0x00,0x28,0x64,0x94,0xd5,0x02,0x07,0x00,0x00,0x04,0x95,0x2c,0x00,0x8b,
//     0x34,0x00,0x82,0x3f,0x00,0x7d,0x4c,0x00,0x7a,0x5b,0x00,0x7a,0x00,0x00,0x00,0x00,
//     0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,
//     0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,
//     0x18,0x16,0x14,0x12,0x10,0x0e,0x0c,0x0a,0x08,0x06,0x04,0x02,0xff,0xff,0x00,0x00,
//     0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x16,0x18,
//     0x1c,0x1d,0x1e,0x1f,0x20,0x21,0x22,0x24,0x13,0x12,0x10,0x0f,0x0a,0x08,0x06,0x04,
//     0x02,0x00,0xff,0xff,0xff,0xff,0xff,0xff,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,
//     0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x79,0x01,

// };

static int gt911_obtain_config(luat_tp_config_t* luat_tp_config, uint8_t *config, uint8_t size){
    if (tp_i2c_read_reg16(luat_tp_config, GT911_CONFIG_REG, config, size, 1)){
        LLOGE("obtain config regs fail!");
        return -1;
    }
    uint8_t check_sum = 0;
    for (uint8_t index=0; index<size-2; index++){
        check_sum += config[index];
    }
    check_sum = (~check_sum) + 1;
    if (config[GT911_CHECK_SUM - GT911_CONFIG_REG] != check_sum){
        LLOGE("check sum 0X%02x and 0X%02x is not equal!", config[GT911_CHECK_SUM - GT911_CONFIG_REG], check_sum);
        return -1;
    }
	return 0;
}

static int gt911_update_config(luat_tp_config_t* luat_tp_config, uint8_t *config, uint8_t size){
	uint8_t check_sum = 0;
	for (uint8_t index=0; index<size-2; index++){
		check_sum += config[index];
	}
	check_sum = (~check_sum) + 1;
	config[GT911_CHECK_SUM - GT911_CONFIG_REG] = check_sum;
	config[GT911_CONFIG_FRESH - GT911_CONFIG_REG] = 1;
	if (tp_i2c_write_reg16(luat_tp_config, GT911_CONFIG_REG, config, size)){
		LLOGE("write config regs fail!");
		return -1;
	}
	return 0;
}

int tp_gt911_read_status(luat_tp_config_t* luat_tp_config, uint8_t *status){
	if (tp_i2c_read_reg16(luat_tp_config, GT911_STATUS, status, 1, 1)){
		LLOGE("read status reg fail!\r\n");
		return -1;
	}
	// LLOGD("status=0x%02X\r\n", *status); // 调试需要看!!!
	return 0;
}

int tp_gt911_clear_status(luat_tp_config_t* luat_tp_config){
	if (tp_i2c_write_reg16(luat_tp_config, GT911_STATUS, (uint8_t[]){0x00}, 1)){
		LLOGE("write status reg fail!");
		return -1;
	}
	return 0;
}

static int tp_gt911_detect(luat_tp_config_t* luat_tp_config){
    uint32_t product_id = 0;
    luat_tp_config->address = GT911_ADDRESS0;
    tp_i2c_read_reg16(luat_tp_config, GT911_PRODUCT_ID, &product_id, sizeof(product_id), 1);
    if (product_id == GT911_PRODUCT_ID_CODE){
        LLOGI("TP find device GT911 ,address:0x%02X",luat_tp_config->address);
        return 0;
    }else{
        luat_tp_config->address = GT911_ADDRESS1;
        tp_i2c_read_reg16(luat_tp_config, GT911_PRODUCT_ID, &product_id, sizeof(product_id), 1);
        if (product_id == GT911_PRODUCT_ID_CODE){
            LLOGI("TP find device GT911 ,address:0x%02X",luat_tp_config->address);
            return 0;
        }else{
            return -1;
        }
    }
}


static int luat_tp_irq_cb(int pin, void *args){
    if (gt911_init_state == 0){
        return -1;
    }
    luat_tp_config_t* luat_tp_config = (luat_tp_config_t*)args;
    luat_tp_irq_enable(luat_tp_config, 0);
    luat_rtos_message_send(luat_tp_config->task_handle, 1, args);
    return 0;
}

static int tp_gt911_gpio_init(luat_tp_config_t* luat_tp_config){
    if (luat_tp_config->pin_rst != LUAT_GPIO_NONE){
        luat_gpio_mode(luat_tp_config->pin_rst, Luat_GPIO_OUTPUT, Luat_GPIO_DEFAULT, Luat_GPIO_LOW);
        luat_gpio_set(luat_tp_config->pin_rst, Luat_GPIO_LOW);
    }
    if (luat_tp_config->pin_int != LUAT_GPIO_NONE){
        luat_gpio_mode(luat_tp_config->pin_int, Luat_GPIO_OUTPUT, Luat_GPIO_DEFAULT, Luat_GPIO_LOW);
        luat_gpio_set(luat_tp_config->pin_int, Luat_GPIO_LOW);
    }
    // /* 0x14 */
    // luat_gpio_set(luat_tp_config->pin_int, Luat_GPIO_HIGH);
    /* 0x5D */
    luat_gpio_set(luat_tp_config->pin_int, Luat_GPIO_LOW);
    
    if (luat_tp_config->pin_rst != LUAT_GPIO_NONE){

        luat_rtos_task_sleep(1);
        luat_gpio_set(luat_tp_config->pin_rst, Luat_GPIO_HIGH);
        luat_rtos_task_sleep(5);

        luat_rtos_task_sleep(2);
        luat_gpio_set(luat_tp_config->pin_rst, Luat_GPIO_HIGH);
    }
    return 0;
}

static int tp_gt911_soft_reset(luat_tp_config_t* luat_tp_config){
    return tp_i2c_write_reg16(luat_tp_config, GT911_COMMAND_REG, (uint8_t[]){0x02}, 1);
}

static int tp_gt911_init(luat_tp_config_t* luat_tp_config){
    int ret = 0;
    luat_rtos_task_sleep(100);
    tp_gt911_gpio_init(luat_tp_config);
    tp_i2c_init(luat_tp_config);

    ret = tp_gt911_detect(luat_tp_config);
    if (ret){
        LLOGE("tp detect fail!");
        return ret;
    }

    uint8_t cfg_table[GT911_CONFIG_SIZE] = {0};
    gt911_obtain_config(luat_tp_config, cfg_table, GT911_CONFIG_SIZE);

	// renew config parameters.
	memcpy((uint8_t*)(&cfg_table[GT911_X_OUTPUT_MAX - GT911_CONFIG_REG]), (uint8_t*)(&luat_tp_config->w), 2);
	memcpy((uint8_t*)(&cfg_table[GT911_Y_OUTPUT_MAX - GT911_CONFIG_REG]), (uint8_t*)(&luat_tp_config->h), 2);

	if (LUAT_GPIO_RISING_IRQ == luat_tp_config->int_type){
		cfg_table[GT911_MODULE_SWITCH1 - GT911_CONFIG_REG] &= 0xFC;
		cfg_table[GT911_MODULE_SWITCH1 - GT911_CONFIG_REG] |= 0x00;
	}else if (LUAT_GPIO_FALLING_IRQ == luat_tp_config->int_type){
		cfg_table[GT911_MODULE_SWITCH1 - GT911_CONFIG_REG] &= 0xFC;
		cfg_table[GT911_MODULE_SWITCH1 - GT911_CONFIG_REG] |= 0x01;
	}

	// xy cordinate swap.
	if (luat_tp_config->swap_xy){
		cfg_table[GT911_MODULE_SWITCH1 - GT911_CONFIG_REG] &= 0xF7;
		cfg_table[GT911_MODULE_SWITCH1 - GT911_CONFIG_REG] |= 0x08;
    }
	// refresh rate.
    if (luat_tp_config->refresh_rate > GT911_REFRESH_RATE_MAX || luat_tp_config->refresh_rate == 0){
		cfg_table[GT911_REFRESH_RATE - GT911_CONFIG_REG] = GT911_REFRESH_RATE_MAX;
	}else if (luat_tp_config->refresh_rate < GT911_REFRESH_RATE_MIN){
		cfg_table[GT911_REFRESH_RATE - GT911_CONFIG_REG] = GT911_REFRESH_RATE_MIN;
	}else{
		cfg_table[GT911_REFRESH_RATE - GT911_CONFIG_REG] = luat_tp_config->refresh_rate - GT911_REFRESH_RATE_MIN;
	}
	// touch number.
	if (luat_tp_config->tp_num > GT911_TOUCH_NUMBER_MAX || luat_tp_config->tp_num == 0){
		cfg_table[GT911_TOUCH_NUMBER - GT911_CONFIG_REG] = GT911_TOUCH_NUMBER_MAX;
	}else if (luat_tp_config->tp_num < GT911_TOUCH_NUMBER_MIN){
		cfg_table[GT911_TOUCH_NUMBER - GT911_CONFIG_REG] = GT911_TOUCH_NUMBER_MIN;
	}else{
		cfg_table[GT911_TOUCH_NUMBER - GT911_CONFIG_REG] = luat_tp_config->tp_num;
	}

    gt911_update_config(luat_tp_config, cfg_table, GT911_CONFIG_SIZE);
    
    // gt911_update_config(luat_tp_config, gt911_cfg_table, GT911_CONFIG_SIZE);

    // luat_rtos_task_sleep(5);
    // tp_gt911_soft_reset(luat_tp_config);

    luat_rtos_task_sleep(20);
    // tp_i2c_write_reg16(luat_tp_config, GT911_COMMAND_REG, (uint8_t[]){0x00}, 1);
    
    if (luat_tp_config->pin_int != LUAT_GPIO_NONE){
        luat_gpio_t gpio = {0};
        gpio.pin = luat_tp_config->pin_int;
        gpio.mode = Luat_GPIO_IRQ;
        gpio.pull = Luat_GPIO_DEFAULT;
        gpio.irq = luat_tp_config->int_type;
        gpio.irq_cb = luat_tp_irq_cb;
        gpio.irq_args = luat_tp_config;
        luat_gpio_setup(&gpio);
    }

    gt911_init_state = 1;
    return ret;

}

static int tp_gt911_deinit(luat_tp_config_t* luat_tp_config){
    gt911_init_state = 0;
    if (luat_tp_config->pin_int != LUAT_GPIO_NONE){
        luat_gpio_close(luat_tp_config->pin_int);
    }
    if (luat_tp_config->pin_rst != LUAT_GPIO_NONE){
        luat_gpio_close(luat_tp_config->pin_rst);
    }
    return 0;
}

static int tp_gt911_get_info(luat_tp_config_t* luat_tp_config, luat_tp_info_t *luat_touch_info){
    return tp_i2c_read_reg16(luat_tp_config, GT911_CONFIG_REG, luat_touch_info, sizeof(luat_tp_info_t), 1);
}
static void tp_gt911_read_done(luat_tp_config_t * luat_tp_config)
{
	luat_tp_irq_enable(luat_tp_config, 1);
}

// gt911 get tp info.
static int16_t pre_x[GT911_TOUCH_NUMBER_MAX] = {-1, -1, -1, -1, -1};
static int16_t pre_y[GT911_TOUCH_NUMBER_MAX] = {-1, -1, -1, -1, -1};
static int16_t pre_w[GT911_TOUCH_NUMBER_MAX] = {-1, -1, -1, -1, -1};
static uint8_t s_tp_down[GT911_TOUCH_NUMBER_MAX];
static uint8_t read_buff[GT911_POINT_INFO_NUM * GT911_TOUCH_NUMBER_MAX];

void gt911_touch_up(void *buf, int8_t id){
	luat_tp_data_t *read_data = (luat_tp_data_t *)buf;

	if(s_tp_down[id] == 1){
		s_tp_down[id] = 0;
		read_data[id].event = TP_EVENT_TYPE_UP;
	}else{
		read_data[id].event = TP_EVENT_TYPE_NONE;
	}

	read_data[id].timestamp = luat_mcu_ticks();
	read_data[id].width = pre_w[id];
	read_data[id].x_coordinate = pre_x[id];
	read_data[id].y_coordinate = pre_y[id];
	read_data[id].track_id = id;

	pre_x[id] = -1;  /* last point is none */
	pre_y[id] = -1;
	pre_w[id] = -1;
}

void gt911_touch_down(void *buf, int8_t id, int16_t x, int16_t y, int16_t w){
	luat_tp_data_t *read_data = (luat_tp_data_t *)buf;

	if (s_tp_down[id] == 1){
		read_data[id].event = TP_EVENT_TYPE_MOVE;
	}else{
		read_data[id].event = TP_EVENT_TYPE_DOWN;
		s_tp_down[id] = 1;
	}

	read_data[id].timestamp = luat_mcu_ticks();
	read_data[id].width = w;
	read_data[id].x_coordinate = x;
	read_data[id].y_coordinate = y;
	read_data[id].track_id = id;

	pre_x[id] = x; /* save last point */
	pre_y[id] = y;
	pre_w[id] = w;
}

void gt911_read_point(uint8_t *input_buff, void *buf, uint8_t touch_num){
	uint8_t *read_buf = input_buff;
	uint8_t read_index;
	int8_t read_id = 0;
	int16_t input_x = 0;
	int16_t input_y = 0;
	int16_t input_w = 0;

	static uint8_t pre_touch = 0;
	static int8_t pre_id[GT911_TOUCH_NUMBER_MAX] = {0};

	if (pre_touch > touch_num){                                       /* point up */
		for (read_index = 0; read_index < pre_touch; read_index++){
			uint8_t j;
			for (j = 0; j < touch_num; j++){                          /* this time touch num */
				read_id = read_buf[j * 8] & 0x0F;
				if (read_id >= GT911_POINT_INFO_NUM){
					LLOGE("%s, touch ID %d is out range!\r\n", __func__, read_id);
					return;
				}
				if (pre_id[read_index] == read_id)                   /* this id is not free */
					break;

				if (j >= touch_num - 1){
					uint8_t up_id;
					up_id = pre_id[read_index];
					gt911_touch_up(buf, up_id);
				}
			}
		}
	}
	if (touch_num){                                                 /* point down */
		uint8_t off_set;
		for (read_index = 0; read_index < touch_num; read_index++){
			off_set = read_index * 8;
			read_id = read_buf[off_set] & 0x0F;
			if (read_id >= GT911_POINT_INFO_NUM){
				LLOGE("%s, touch ID %d is out range!\r\n", __func__, read_id);
				return;
			}
			pre_id[read_index] = read_id;
			input_x = read_buf[off_set + 1] | (read_buf[off_set + 2] << 8);	/* x */
			input_y = read_buf[off_set + 3] | (read_buf[off_set + 4] << 8);	/* y */
			input_w = read_buf[off_set + 5] | (read_buf[off_set + 6] << 8);	/* size */
			gt911_touch_down(buf, read_id, input_x, input_y, input_w);
		}
	}else if (pre_touch){
		for(read_index = 0; read_index < pre_touch; read_index++){
			gt911_touch_up(buf, pre_id[read_index]);
		}
	}
	pre_touch = touch_num;
}

static int tp_gt911_read(luat_tp_config_t* luat_tp_config, luat_tp_data_t *luat_tp_data){
    uint8_t touch_num=0, point_status=0;

    // luat_tp_info_t luat_touch_info = {0};
    // tp_gt911_get_info(luat_tp_config, &luat_touch_info);
    // uint8_t read_num = luat_touch_info.touch_num;
    // LLOGD("tp_gt911_read read_num:%d",read_num);

    tp_gt911_read_status(luat_tp_config, &point_status);
    if (point_status == 0){           /* no data */
        goto exit_;
    }
    if ((point_status & 0x80) == 0){  /* data is not ready */
        goto exit_;
    }
    touch_num = point_status & 0x0F;  /* get point num */
    if (touch_num > GT911_TOUCH_NUMBER_MAX) {/* point num is not correct */
        touch_num = 0;
        goto exit_;
    }
    
    // LLOGD("tp_gt911_read touch_num:%d",touch_num);

    memset(read_buff, 0x00, sizeof(read_buff));
    
    tp_i2c_read_reg16(luat_tp_config, GT911_POINT1_REG, read_buff, touch_num * GT911_POINT_INFO_NUM, 1);

    gt911_read_point(read_buff, luat_tp_data, touch_num);
    
    
exit_:
    tp_gt911_clear_status(luat_tp_config);
    return touch_num;
}

luat_tp_opts_t tp_config_gt911 = {
    .name = "gt911",
    .init = tp_gt911_init,
    .deinit = tp_gt911_deinit,
    .read = tp_gt911_read,
	.read_done = tp_gt911_read_done,
};
