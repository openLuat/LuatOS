#include "luat_base.h"
#include "luat_tp.h"
#include "luat_gpio.h"
#include "luat_mem.h"
#include "luat_rtos.h"
#include "luat_tp_reg.h"

#define LUAT_LOG_TAG "jd9261t"
#include "luat_log.h"

#define JT9261T_ADDRESS0              (0x68)
#define JT9261T_ADDRESS1              (0x14)

#define JT9261T_PRODUCT_ID_CODE       (0x9062)

#define JT9261T_REG_RESET             (0x40008004)
#define JT9261T_CMD_RESET             (0xA5)

#define JT9261T_POR_INIT_REG          (0x40008081)
#define JT9261T_PRODUCT_ID            (0x40008076)

#define JT9261T_READ_COOR_ADDR        (0x20011120)
#define JT9261T_REG_SLEEP             (0x8040)
#define JT9261T_REG_SENSOR_ID         (0x814A)
#define JT9261T_REG_CONFIG_DATA       (0x8047)
#define JT9261T_REG_VERSION           (0x8140)
#define JT9261T_REG_READ_POINT        (0x8150)
#define JT9261T_REG_MODULE_SWITCH     (0x804D)
#define JT9261T_REG_CONFIG_CHKSUM     (0x80FF)
#define JT9261T_REG_CONFIG_FRESH      (0x8100)

#define JT9261T_POINT_INFO_NUM        (6)
#define JT9261T_TOUCH_NUMBER_MIN      (1)
#define JT9261T_TOUCH_NUMBER_MAX      (10)

#define JT9261T_REFRESH_RATE_MIN      (5)
#define JT9261T_REFRESH_RATE_MAX      (20)

typedef struct{
    uint8_t x_h;
    uint8_t x_l;
    uint8_t y_h;
    uint8_t y_l;
    uint8_t w;
    uint8_t reserved;
}luat_tp_touch_t;

typedef struct luat_touch_info{
    uint8_t touch_num;
    uint8_t reserved0;
    uint8_t reserved1;
    luat_tp_touch_t point[JT9261T_TOUCH_NUMBER_MAX];
}luat_tp_info_t;

static uint8_t jd9261t_init_state = 0;

/* 根据官方推荐,优先使用后门方式,自动识别，如不支持自动切换至非后门 */
static uint8_t jd9261t_back_door_mode = 1;

static inline int jd9261t_Read_BackDoor_RegSingle(luat_tp_config_t* luat_tp_config, uint32_t addr, uint8_t *rdata){
    uint8_t addrBuf[] = {
        0xF3,
        (uint8_t)((addr & 0xFF000000) >> 24),
        (uint8_t)((addr & 0x00FF0000) >> 16),
        (uint8_t)((addr & 0x0000FF00) >> 8),
        (uint8_t)((addr & 0x000000FF) >> 0),
        0x03,
    };
    return tp_i2c_read(luat_tp_config, addrBuf, sizeof(addrBuf), rdata, 1, 0);
}

static inline int jd9261t_Write_BackDoor_RegSingle(luat_tp_config_t* luat_tp_config, uint32_t addr, uint8_t wdata){
    uint8_t addrBuf[] = {
        0xF2,
        (uint8_t)((addr & 0xFF000000) >> 24),
        (uint8_t)((addr & 0x00FF0000) >> 16),
        (uint8_t)((addr & 0x0000FF00) >> 8),
        (uint8_t)((addr & 0x000000FF) >> 0),
        0x03,
    };
    return tp_i2c_write(luat_tp_config, addrBuf, sizeof(addrBuf), (uint8_t[]){wdata}, 1);
}

static inline int jd9261t_Read_BackDoor_RegMulti(luat_tp_config_t* luat_tp_config, uint32_t addr, uint8_t *rdata, uint16_t rlen){
    uint8_t addrBuf[] = {
        0xF3,
        (uint8_t)((addr & 0xFF000000) >> 24),
        (uint8_t)((addr & 0x00FF0000) >> 16),
        (uint8_t)((addr & 0x0000FF00) >> 8),
        (uint8_t)((addr & 0x000000FF) >> 0),
        0x03,
    };
    return tp_i2c_read(luat_tp_config, addrBuf, sizeof(addrBuf), rdata, rlen, 0);
}

static inline int jd9261t_Write_BackDoor_RegMulti(luat_tp_config_t* luat_tp_config, uint32_t addr, uint8_t *wdata, uint16_t wlen){
    uint8_t addrBuf[] = {
        0xF2,
        (uint8_t)((addr & 0xFF000000) >> 24),
        (uint8_t)((addr & 0x00FF0000) >> 16),
        (uint8_t)((addr & 0x0000FF00) >> 8),
        (uint8_t)((addr & 0x000000FF) >> 0),
        0x03,
    };
    return tp_i2c_write(luat_tp_config, addrBuf, sizeof(addrBuf), wdata, wlen);
}

static int jd9261t_Read_FW_RegSingleI2c(luat_tp_config_t* luat_tp_config, uint32_t addr, uint8_t *rdata){
    uint8_t addrBuf[] = {
        (uint8_t)((addr & 0xFF000000) >> 24),
        (uint8_t)((addr & 0x00FF0000) >> 16),
        (uint8_t)((addr & 0x0000FF00) >> 8),
        (uint8_t)((addr & 0x000000FF) >> 0),
        0x00,
        0x01,
    };
    return tp_i2c_read(luat_tp_config, addrBuf, sizeof(addrBuf), rdata, 1, 0);
}

static int jd9261t_Write_FW_RegSingleI2c(luat_tp_config_t* luat_tp_config, uint32_t addr, uint8_t wdata){
    uint8_t addrBuf[] = {
        (uint8_t)((addr & 0xFF000000) >> 24),
        (uint8_t)((addr & 0x00FF0000) >> 16),
        (uint8_t)((addr & 0x0000FF00) >> 8),
        (uint8_t)((addr & 0x000000FF) >> 0),
        0x00,
        0x01,
    };
    return tp_i2c_write(luat_tp_config, addrBuf, sizeof(addrBuf), (uint8_t[]){wdata}, 1);
}

static int jd9261t_Read_FW_RegMultiI2c(luat_tp_config_t* luat_tp_config, uint32_t addr, uint8_t *rdata, uint16_t rlen){
    uint8_t addrBuf[] = {
        (uint8_t)((addr & 0xFF000000) >> 24),
        (uint8_t)((addr & 0x00FF0000) >> 16),
        (uint8_t)((addr & 0x0000FF00) >> 8),
        (uint8_t)((addr & 0x000000FF) >> 0),
        (uint8_t)((rlen & 0xFF00) >> 8),
        (uint8_t)((rlen & 0x00FF) >> 0),
    };
    return tp_i2c_read(luat_tp_config, addrBuf, sizeof(addrBuf), rdata, rlen, 0);
}

static int jd9261t_Write_FW_RegMultiI2c(luat_tp_config_t* luat_tp_config, uint32_t addr, uint8_t *wdata, uint16_t wlen){
    uint8_t addrBuf[] = {
        (uint8_t)((addr & 0xFF000000) >> 24),
        (uint8_t)((addr & 0x00FF0000) >> 16),
        (uint8_t)((addr & 0x0000FF00) >> 8),
        (uint8_t)((addr & 0x000000FF) >> 0),
        (uint8_t)((wlen & 0xFF00) >> 8),
        (uint8_t)((wlen & 0x00FF) >> 0),
    };
    return tp_i2c_write(luat_tp_config, addrBuf, sizeof(addrBuf), wdata, wlen);
}

static inline int jd9261t_ReadRegSingle(luat_tp_config_t* luat_tp_config, uint32_t addr, uint8_t *rdata){
    if (jd9261t_back_door_mode){
        return jd9261t_Read_BackDoor_RegSingle(luat_tp_config, addr, rdata);
    } else {
        return jd9261t_Read_FW_RegSingleI2c(luat_tp_config, addr, rdata);
    }
}

static inline int jd9261t_WriteRegSingle(luat_tp_config_t* luat_tp_config, uint32_t addr, uint8_t wdata){
    if (jd9261t_back_door_mode){
        return jd9261t_Write_BackDoor_RegSingle(luat_tp_config, addr, wdata);
    } else {
        return jd9261t_Write_FW_RegSingleI2c(luat_tp_config, addr, wdata);
    }
}

static inline int jd9261t_ReadRegMulti(luat_tp_config_t* luat_tp_config, uint32_t addr, uint8_t *rdata, uint16_t rlen){
    if (jd9261t_back_door_mode){
        return jd9261t_Read_BackDoor_RegMulti(luat_tp_config, addr, rdata, rlen);
    } else {
        return jd9261t_Read_FW_RegMultiI2c(luat_tp_config, addr, rdata, rlen);
    }
}

static inline int jd9261t_WriteRegMulti(luat_tp_config_t* luat_tp_config, uint32_t addr, uint8_t *wdata, uint16_t wlen){
    if (jd9261t_back_door_mode){
        return jd9261t_Write_BackDoor_RegMulti(luat_tp_config, addr, wdata, wlen);
    } else {
        return jd9261t_Write_FW_RegMultiI2c(luat_tp_config, addr, wdata, wlen);
    }
}


static inline int jd9261t_EnterBackDoor(luat_tp_config_t* luat_tp_config){
    uint8_t addrBuf[] = {
        0xF2,
        0xAA,
        0xF0,
        0x0F,
        0x55,
    };
    return tp_i2c_write(luat_tp_config, addrBuf, sizeof(addrBuf), (uint8_t[]){0x68}, 1);
}

static inline int jd9261t_ExitBackDoor(luat_tp_config_t* luat_tp_config){
    uint8_t addrBuf[] = {
        0xF2,
        0xAA,
        0x88,
        0x00,
        0x00,
    };
    return tp_i2c_write(luat_tp_config, addrBuf, sizeof(addrBuf), (uint8_t[]){0x00}, 1);
}

// static int jd9261t_obtain_config(luat_tp_config_t* luat_tp_config, uint8_t *config, uint8_t size){
//     if (tp_i2c_read_reg16(luat_tp_config, JT9261T_CONFIG_REG, config, size, 1)){
//         LLOGE("obtain config regs fail!");
//         return -1;
//     }
//     uint8_t check_sum = 0;
//     for (uint8_t index=0; index<size-2; index++){
//         check_sum += config[index];
//     }
//     check_sum = (~check_sum) + 1;
//     if (config[JT9261T_CHECK_SUM - JT9261T_CONFIG_REG] != check_sum){
//         LLOGE("check sum 0X%02x and 0X%02x is not equal!", config[JT9261T_CHECK_SUM - JT9261T_CONFIG_REG], check_sum);
//         return -1;
//     }
// 	return 0;
// }

// static int jd9261t_update_config(luat_tp_config_t* luat_tp_config, uint8_t *config, uint8_t size){
// 	uint8_t check_sum = 0;
// 	for (uint8_t index=0; index<size-2; index++){
// 		check_sum += config[index];
// 	}
// 	check_sum = (~check_sum) + 1;
// 	config[JT9261T_CHECK_SUM - JT9261T_CONFIG_REG] = check_sum;
// 	config[JT9261T_CONFIG_FRESH - JT9261T_CONFIG_REG] = 1;
// 	if (tp_i2c_write_reg16(luat_tp_config, JT9261T_CONFIG_REG, config, size)){
// 		LLOGE("write config regs fail!");
// 		return -1;
// 	}
// 	return 0;
// }

static inline int tp_jd9261t_soft_reset(luat_tp_config_t* luat_tp_config){
    return tp_i2c_write_reg32(luat_tp_config, JT9261T_REG_RESET, (uint8_t[]){JT9261T_CMD_RESET}, 1);
}

static int tp_jd9261t_detect(luat_tp_config_t* luat_tp_config){
    uint16_t product_id = 0;
    luat_tp_config->address = JT9261T_ADDRESS0;
    if (jd9261t_back_door_mode){
        jd9261t_EnterBackDoor(luat_tp_config); /* EnterBackDoor */
    }
    jd9261t_ReadRegMulti(luat_tp_config, JT9261T_PRODUCT_ID, &product_id, sizeof(product_id));
    if (product_id == JT9261T_PRODUCT_ID_CODE){
        LLOGI("TP find device JT9261T ,address:0x%02X",luat_tp_config->address);
        return 0;
    }else{
        luat_tp_config->address = JT9261T_ADDRESS1;
        if (jd9261t_back_door_mode){
            jd9261t_EnterBackDoor(luat_tp_config); /* EnterBackDoor */
        }
        jd9261t_ReadRegMulti(luat_tp_config, JT9261T_PRODUCT_ID, &product_id, sizeof(product_id));
        if (product_id == JT9261T_PRODUCT_ID_CODE){
            LLOGI("TP find device JT9261T ,address:0x%02X",luat_tp_config->address);
            return 0;
        }else{
            return -1;
        }
    }
}

static int luat_tp_irq_cb(int pin, void *args){
    if (jd9261t_init_state == 0){
        return -1;
    }
    luat_tp_config_t* luat_tp_config = (luat_tp_config_t*)args;
    luat_tp_irq_enable(luat_tp_config, 0);
    luat_rtos_message_send(luat_tp_config->task_handle, 1, args);
    return 0;
}

static inline int tp_jd9261t_gpio_init(luat_tp_config_t* luat_tp_config){
    if (luat_tp_config->pin_rst != LUAT_GPIO_NONE){
        luat_gpio_mode(luat_tp_config->pin_rst, Luat_GPIO_OUTPUT, Luat_GPIO_DEFAULT, Luat_GPIO_LOW);
        luat_gpio_set(luat_tp_config->pin_rst, Luat_GPIO_LOW);
    }
    if (luat_tp_config->pin_int != LUAT_GPIO_NONE){
        luat_gpio_mode(luat_tp_config->pin_int, Luat_GPIO_OUTPUT, Luat_GPIO_DEFAULT, Luat_GPIO_LOW);
        luat_gpio_set(luat_tp_config->pin_int, Luat_GPIO_LOW);
    }

    luat_gpio_set(luat_tp_config->pin_int, Luat_GPIO_HIGH);

    if (luat_tp_config->pin_rst != LUAT_GPIO_NONE){
            
        luat_rtos_task_sleep(5);
        luat_gpio_set(luat_tp_config->pin_rst, Luat_GPIO_HIGH);
        luat_rtos_task_sleep(5);
        luat_gpio_set(luat_tp_config->pin_rst, Luat_GPIO_LOW);
        luat_rtos_task_sleep(50);
        luat_gpio_set(luat_tp_config->pin_rst, Luat_GPIO_HIGH);
        luat_rtos_task_sleep(100);
    }
    return 0;
}

static int tp_jd9261t_init(luat_tp_config_t* luat_tp_config){
    int ret = 0;
    luat_rtos_task_sleep(100);

    tp_jd9261t_gpio_init(luat_tp_config);

    ret = tp_jd9261t_detect(luat_tp_config);
    if (ret){
        LLOGD("tp backdoor mode detect fail!");
        jd9261t_back_door_mode = 0;
        ret = tp_jd9261t_detect(luat_tp_config);
        if(ret){
            LLOGE("tp detect fail!");
            return ret;
        }
    }



    // uint8_t cfg_table[JT9261T_CONFIG_SIZE] = {0};
    // jd9261t_obtain_config(luat_tp_config, cfg_table, JT9261T_CONFIG_SIZE);

	// // renew config parameters.
	// memcpy((uint8_t*)(&cfg_table[JT9261T_X_OUTPUT_MAX - JT9261T_CONFIG_REG]), (uint8_t*)(&luat_tp_config->w), 2);
	// memcpy((uint8_t*)(&cfg_table[JT9261T_Y_OUTPUT_MAX - JT9261T_CONFIG_REG]), (uint8_t*)(&luat_tp_config->h), 2);

	// if (LUAT_GPIO_RISING_IRQ == luat_tp_config->int_type){
	// 	cfg_table[JT9261T_MODULE_SWITCH1 - JT9261T_CONFIG_REG] &= 0xFC;
	// 	cfg_table[JT9261T_MODULE_SWITCH1 - JT9261T_CONFIG_REG] |= 0x00;
	// }else if (LUAT_GPIO_FALLING_IRQ == luat_tp_config->int_type){
	// 	cfg_table[JT9261T_MODULE_SWITCH1 - JT9261T_CONFIG_REG] &= 0xFC;
	// 	cfg_table[JT9261T_MODULE_SWITCH1 - JT9261T_CONFIG_REG] |= 0x01;
	// }

	// // xy cordinate swap.
	// if (luat_tp_config->swap_xy){
	// 	cfg_table[JT9261T_MODULE_SWITCH1 - JT9261T_CONFIG_REG] &= 0xF7;
	// 	cfg_table[JT9261T_MODULE_SWITCH1 - JT9261T_CONFIG_REG] |= 0x08;
    // }
	// // refresh rate.
    // if (luat_tp_config->refresh_rate > JT9261T_REFRESH_RATE_MAX || luat_tp_config->refresh_rate == 0){
	// 	cfg_table[JT9261T_REFRESH_RATE - JT9261T_CONFIG_REG] = JT9261T_REFRESH_RATE_MAX;
	// }else if (luat_tp_config->refresh_rate < JT9261T_REFRESH_RATE_MIN){
	// 	cfg_table[JT9261T_REFRESH_RATE - JT9261T_CONFIG_REG] = JT9261T_REFRESH_RATE_MIN;
	// }else{
	// 	cfg_table[JT9261T_REFRESH_RATE - JT9261T_CONFIG_REG] = luat_tp_config->refresh_rate - JT9261T_REFRESH_RATE_MIN;
	// }
	// // touch number.
	// if (luat_tp_config->tp_num > JT9261T_TOUCH_NUMBER_MAX || luat_tp_config->tp_num == 0){
	// 	cfg_table[JT9261T_TOUCH_NUMBER - JT9261T_CONFIG_REG] = JT9261T_TOUCH_NUMBER_MAX;
	// }else if (luat_tp_config->tp_num < JT9261T_TOUCH_NUMBER_MIN){
	// 	cfg_table[JT9261T_TOUCH_NUMBER - JT9261T_CONFIG_REG] = JT9261T_TOUCH_NUMBER_MIN;
	// }else{
	// 	cfg_table[JT9261T_TOUCH_NUMBER - JT9261T_CONFIG_REG] = luat_tp_config->tp_num;
	// }

    // jd9261t_update_config(luat_tp_config, cfg_table, JT9261T_CONFIG_SIZE);
    
    // // jd9261t_update_config(luat_tp_config, jd9261t_cfg_table, JT9261T_CONFIG_SIZE);

    // // luat_rtos_task_sleep(5);
    // // tp_jd9261t_soft_reset(luat_tp_config);

    // luat_rtos_task_sleep(20);
    // // tp_i2c_write_reg16(luat_tp_config, JT9261T_COMMAND_REG, (uint8_t[]){0x00}, 1);
    
    if (luat_tp_config->pin_int != LUAT_GPIO_NONE){
        luat_gpio_t gpio = {0};
        gpio.pin = luat_tp_config->pin_int;
        gpio.mode = Luat_GPIO_IRQ;
        gpio.pull = Luat_GPIO_DEFAULT;
        gpio.irq = LUAT_GPIO_FALLING_IRQ;
        gpio.irq_cb = luat_tp_irq_cb;
        gpio.irq_args = luat_tp_config;
        luat_gpio_setup(&gpio);
    }

    jd9261t_init_state = 1;
    return ret;

}

static int tp_jd9261t_deinit(luat_tp_config_t* luat_tp_config){
    jd9261t_init_state = 0;
    if (luat_tp_config->pin_int != LUAT_GPIO_NONE){
        luat_gpio_close(luat_tp_config->pin_int);
    }
    if (luat_tp_config->pin_rst != LUAT_GPIO_NONE){
        luat_gpio_close(luat_tp_config->pin_rst);
    }
    return 0;
}

static void tp_jd9261t_read_done(luat_tp_config_t * luat_tp_config){
    if (luat_gpio_get(luat_tp_config->pin_int)){
        luat_tp_irq_enable(luat_tp_config, 1);
    }else{
        luat_rtos_message_send(luat_tp_config->task_handle, 1, luat_tp_config);
    }
}

// jd9261t get tp info.
static int16_t pre_x[JT9261T_TOUCH_NUMBER_MAX] = {-1, -1, -1, -1, -1};
static int16_t pre_y[JT9261T_TOUCH_NUMBER_MAX] = {-1, -1, -1, -1, -1};
static int16_t pre_w[JT9261T_TOUCH_NUMBER_MAX] = {-1, -1, -1, -1, -1};
static uint8_t s_tp_down[JT9261T_TOUCH_NUMBER_MAX];
// static uint8_t read_buff[JT9261T_POINT_INFO_NUM * JT9261T_TOUCH_NUMBER_MAX];
static luat_tp_info_t luat_touch_info = {0};

void jd9261t_touch_up(void *buf, int8_t id){
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

void jd9261t_touch_down(void *buf, int8_t id, int16_t x, int16_t y, int16_t w){
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

void jd9261t_read_point(luat_tp_config_t* luat_tp_config, luat_tp_touch_t *input_buff, void *buf, uint8_t touch_num){
	luat_tp_touch_t *read_buf = input_buff;
	uint8_t read_index;
	int8_t read_id = 0;
	int16_t input_x = 0;
	int16_t input_y = 0;
	int16_t input_w = 0;

	static uint8_t pre_touch = 0;
	static int8_t pre_id[JT9261T_TOUCH_NUMBER_MAX] = {0};

	if (pre_touch > touch_num){                                       /* point up */
		for (read_index = 0; read_index < pre_touch; read_index++){
			uint8_t j;
			for (j = 0; j < touch_num; j++){                          /* this time touch num */
				read_id = j;
				if (pre_id[read_index] == read_id)                   /* this id is not free */
					break;

				if (j >= touch_num - 1){
					uint8_t up_id;
					up_id = pre_id[read_index];
					jd9261t_touch_up(buf, up_id);
				}
			}
		}
	}
	if (touch_num){                                                 /* point down */
		for (read_index = 0; read_index < touch_num; read_index++){
			pre_id[read_index] = read_index;
			input_x = read_buf[read_index].x_h<<8 | read_buf[read_index].x_l;	/* x */
			input_y = read_buf[read_index].y_h<<8 | read_buf[read_index].y_l;	/* y */
            if (input_x>luat_tp_config->w || input_y>luat_tp_config->h){
                return;
            }
            input_w = read_buf[read_index].w;	/* w */
			jd9261t_touch_down(buf, read_index, input_x, input_y, input_w);
		}
	}else if (pre_touch){
		for(read_index = 0; read_index < pre_touch; read_index++){
			jd9261t_touch_up(buf, pre_id[read_index]);
		}
	}
	pre_touch = touch_num;
}

static int tp_jd9261t_read(luat_tp_config_t* luat_tp_config, luat_tp_data_t *luat_tp_data){
    uint8_t touch_num=0;

    jd9261t_ReadRegMulti(luat_tp_config, JT9261T_READ_COOR_ADDR, (uint8_t *)&luat_touch_info, sizeof(luat_touch_info));
    
    touch_num = luat_touch_info.touch_num;
    jd9261t_read_point(luat_tp_config, luat_touch_info.point, luat_tp_data, luat_touch_info.touch_num);

    return touch_num;
}

luat_tp_opts_t tp_config_jd9261t = {
    .name = "jd9261t",
    .init = tp_jd9261t_init,
    .deinit = tp_jd9261t_deinit,
    .read = tp_jd9261t_read,
	.read_done = tp_jd9261t_read_done,
};