#include "luat_base.h"
#include "luat_tp.h"
#include "luat_gpio.h"
#include "luat_mem.h"
#include "luat_rtos.h"
#include "luat_tp_reg.h"

#define LUAT_LOG_TAG "cts820"
#include "luat_log.h"

#define CTS820_ADDRESS               (0x15)
#define CTS820_CHIP_ID_CODE          (0xB7)
#define CTS820_CHIP_ID               (0xA7)
#define CTS820_STATUS                (0x02)
#define CTS820_POINT1_REG            (0x03)

#define CTS820_CONFIG_SIZE           (CTS820_CONFIG_FRESH - CTS820_CONFIG_REG + 1)
#define CTS820_POINT_INFO_NUM        (4)
#define CTS820_TOUCH_NUMBER_MIN      (1)
#define CTS820_TOUCH_NUMBER_MAX      (2)

#define CTS820_REFRESH_RATE_MIN      (5)
#define CTS820_REFRESH_RATE_MAX      (20)

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

static uint8_t cts820_init_state = 0;

int tp_cts820_clear_status(luat_tp_config_t* luat_tp_config){
	if (tp_i2c_write_reg16(luat_tp_config, CTS820_STATUS, (uint8_t[]){0x00}, 1)){
		LLOGE("write status reg fail!");
		return -1;
	}
	return 0;
}

static int tp_cts820_detect(luat_tp_config_t* luat_tp_config){
    uint8_t chip_id = 0;
    luat_tp_config->address = CTS820_ADDRESS;
    tp_i2c_read_reg8(luat_tp_config, CTS820_CHIP_ID, &chip_id, 1, 0);
    if (chip_id == CTS820_CHIP_ID_CODE){
        LLOGI("TP find device CTS820 ,address:0x%02X",luat_tp_config->address);
        return 0;
    }else{
        return -1;
    }
}


static int luat_tp_irq_cb(int pin, void *args){
    if (cts820_init_state == 0){
        return -1;
    }
    luat_tp_config_t* luat_tp_config = (luat_tp_config_t*)args;
    luat_tp_irq_enable(luat_tp_config, 0);
    luat_rtos_message_send(luat_tp_config->task_handle, 1, args);
    return 0;
}

static int tp_cts820_hw_reset(luat_tp_config_t* luat_tp_config){
    if (luat_tp_config->pin_rst != LUAT_GPIO_NONE){
        luat_gpio_set(luat_tp_config->pin_rst, Luat_GPIO_LOW);
        luat_rtos_task_sleep(10);
        luat_gpio_set(luat_tp_config->pin_rst, Luat_GPIO_HIGH);
        luat_rtos_task_sleep(100);
    }
    return 0;
}

static int tp_cts820_gpio_init(luat_tp_config_t* luat_tp_config){
    luat_gpio_mode(luat_tp_config->pin_rst, Luat_GPIO_OUTPUT, Luat_GPIO_DEFAULT, Luat_GPIO_HIGH);
    luat_gpio_mode(luat_tp_config->pin_int, Luat_GPIO_OUTPUT, Luat_GPIO_DEFAULT, Luat_GPIO_HIGH);
    luat_gpio_set(luat_tp_config->pin_rst, Luat_GPIO_HIGH);
    luat_gpio_set(luat_tp_config->pin_int, Luat_GPIO_HIGH);
    tp_cts820_hw_reset(luat_tp_config);
    return 0;
}

static int tp_cts820_init(luat_tp_config_t* luat_tp_config){
    int ret = 0;
    luat_rtos_task_sleep(100);
    tp_cts820_gpio_init(luat_tp_config);
    luat_rtos_task_sleep(10);
    ret = tp_cts820_detect(luat_tp_config);
    if (ret){
        LLOGE("tp detect fail!");
        return ret;
    }

    luat_rtos_task_sleep(20);
    luat_tp_config->int_type = Luat_GPIO_FALLING;

    luat_gpio_t gpio = {0};
    gpio.pin = luat_tp_config->pin_int;
    gpio.mode = Luat_GPIO_IRQ;
    gpio.pull = Luat_GPIO_PULLUP;
    gpio.irq = luat_tp_config->int_type;
    gpio.irq_cb = luat_tp_irq_cb;
    gpio.irq_args = luat_tp_config;
    luat_gpio_setup(&gpio);

    cts820_init_state = 1;
    return ret;

}

static int tp_cts820_deinit(luat_tp_config_t* luat_tp_config){
    cts820_init_state = 0;
    if (luat_tp_config->pin_int != LUAT_GPIO_NONE){
        luat_gpio_close(luat_tp_config->pin_int);
    }
    if (luat_tp_config->pin_rst != LUAT_GPIO_NONE){
        luat_gpio_close(luat_tp_config->pin_rst);
    }
    return 0;
}

static void tp_cts820_read_done(luat_tp_config_t * luat_tp_config){
	luat_tp_irq_enable(luat_tp_config, 1);
}

// cts820 get tp info.
typedef struct {
    uint8_t x_h : 4;
    uint8_t : 4;
    uint8_t x_l;
    uint8_t y_h : 4;
    uint8_t : 4;
    uint8_t y_l;
} point_data_t;

static int16_t pre_x[CTS820_TOUCH_NUMBER_MAX] = {-1, -1};
static int16_t pre_y[CTS820_TOUCH_NUMBER_MAX] = {-1, -1};
static int16_t pre_w[CTS820_TOUCH_NUMBER_MAX] = {-1, -1};
static uint8_t s_tp_down[CTS820_TOUCH_NUMBER_MAX];

static uint8_t read_buff[CTS820_POINT_INFO_NUM * CTS820_TOUCH_NUMBER_MAX];

void cts820_touch_up(void *buf, int8_t id){
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

void cts820_touch_down(void *buf, int8_t id, int16_t x, int16_t y, int16_t w){
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

void cts820_read_point(uint8_t *input_buff, void *buf, uint8_t touch_num){
	uint8_t *read_buf = input_buff;
	uint8_t read_index;
	int8_t read_id = 0;
	int16_t input_x = 0;
	int16_t input_y = 0;
	int16_t input_w = 0;

	static uint8_t pre_touch = 0;
	static int8_t pre_id[CTS820_TOUCH_NUMBER_MAX] = {0};

	if (pre_touch > touch_num){                                       /* point up */
		for (read_index = 0; read_index < pre_touch; read_index++){
			uint8_t j;
			for (j = 0; j < touch_num; j++){                          /* this time touch num */
				read_id = j;
				if (read_id >= CTS820_POINT_INFO_NUM){
					LLOGE("%s, touch ID %d is out range!\r\n", __func__, read_id);
					return;
				}
				if (pre_id[read_index] == read_id)                   /* this id is not free */
					break;

				if (j >= touch_num - 1){
					uint8_t up_id;
					up_id = pre_id[read_index];
					cts820_touch_up(buf, up_id);
				}
			}
		}
	}
	if (touch_num){                                                 /* point down */
		uint8_t off_set;
		for (read_index = 0; read_index < touch_num; read_index++){
			off_set = read_index * CTS820_POINT_INFO_NUM;
			read_id = read_index;
			if (read_id >= CTS820_POINT_INFO_NUM){
				LLOGE("%s, touch ID %d is out range!\r\n", __func__, read_id);
				return;
			}
			pre_id[read_index] = read_id;
            point_data_t* point_buff = &read_buf[off_set];
			input_x = point_buff->x_h << 8 | point_buff->x_l;	/* x */
			input_y = point_buff->y_h << 8 | point_buff->y_l;	/* y */
			cts820_touch_down(buf, read_id, input_x, input_y, input_w);
		}
	}else if (pre_touch){
		for(read_index = 0; read_index < pre_touch; read_index++){
			cts820_touch_up(buf, pre_id[read_index]);
		}
	}
	pre_touch = touch_num;
}

int tp_cts820_read_status(luat_tp_config_t* luat_tp_config, uint8_t *status){
	if (tp_i2c_read_reg16(luat_tp_config, CTS820_STATUS, status, 1, 1)){
		LLOGE("read status reg fail!\r\n");
		return -1;
	}
	// LLOGD("status=0x%02X\r\n", *status); // 调试需要看!!!
	return 0;
}

static int tp_cts820_read(luat_tp_config_t* luat_tp_config, luat_tp_data_t *luat_tp_data){
    uint8_t touch_num=0, point_status=0;
    tp_i2c_read_reg8(luat_tp_config, CTS820_STATUS, &touch_num, 1, 0);
    
    // tp_cts820_read_status(luat_tp_config, &point_status);
    // if (point_status == 0){           /* no data */
    //     goto exit_;
    // }
    // if ((point_status & 0x80) == 0){   /* data is not ready */
    //     goto exit_;
    // }
    // touch_num = point_status & 0x0F;  /* get point num */
    // LLOGD("touch_num = %d",touch_num);
    if (touch_num > CTS820_TOUCH_NUMBER_MAX) {/* point num is not correct */
        touch_num = 0;
        goto exit_;
    }
    
    // LLOGD("tp_cts820_read touch_num:%d",touch_num);

    memset(read_buff, 0x00, sizeof(read_buff));
    
    if (touch_num){
        tp_i2c_read_reg8(luat_tp_config, CTS820_POINT1_REG, read_buff, touch_num * CTS820_POINT_INFO_NUM, 0);
    }

    cts820_read_point(read_buff, luat_tp_data, touch_num);
    
exit_:
    // tp_cts820_clear_status(luat_tp_config);
    return touch_num;
}

luat_tp_opts_t tp_config_cts820 = {
    .name = "cts820",
    .init = tp_cts820_init,
    .deinit = tp_cts820_deinit,
    .read = tp_cts820_read,
	.read_done = tp_cts820_read_done,
};
