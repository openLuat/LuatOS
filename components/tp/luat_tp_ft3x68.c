#include "luat_base.h"
#include "luat_tp.h"
#include "luat_gpio.h"
#include "luat_mem.h"
#include "luat_rtos.h"
#include "luat_tp_reg.h"

#define LUAT_LOG_TAG "ft3x68"
#include "luat_log.h"

#define FT3X68_DEVIDE_MODE 0x00   //模式控制
#define FT3X68_TD_STATUS   0x02		//触摸状态

#define FT3X68_TP1_REG 		 0X03
#define FT3X68_TP2_REG 		 0X09
#define FT3X68_TP3_REG 		 0X0F
#define FT3X68_TP4_REG 		 0X15
#define FT3X68_TP5_REG 		 0X1B
#define ID_G_CIPHER_HIGH     0xA3
#define ID_G_CIPHER_MID      0x9F
#define ID_G_CIPHER_LOW      0xA0

#define	FT3X68_ID_G_LIB_VERSION		0xA1
#define	FT3X68_CHIP_VENDOR_ID		  0xA3
#define FT3X68_ID_G_MODE 			    0xA4   	//中断控制
#define FT3X68_ID_G_THGROUP			  0x80   	//触摸有效值
#define FT3X68_ID_G_PERIODACTIVE	0x88   	//激活状态周期

#define FTS_CHIP_IDH    0x64
#define FTS_CHIP_IDL    0x56

#define FTS_FW_VER       0x02
#define FTS_CMD_READ_ID  0x90

#define FTS_UPGRADE_AA   0xAA
#define FTS_UPGRADE_55   0x55

#define FTS_REG_FW_VER    0xA6
#define FTS_REG_UPGRADE   0xFC

#define FTS_RETRIES_CHECK_ID                        20
#define FTS_DELAY_UPGRADE_AA                        10
#define FTS_DELAY_UPGRADE_RESET                     400
#define FTS_DELAY_READ_ID                           20
#define FTS_DELAY_UPGRADE                           80
#define FTS_RETRIES_UPGRADE                         2

#define FTS_CMD_RESET                               0x07
#define FTS_CMD_FLASH_MODE                          0x09
#define FTS_FLASH_MODE_UPGRADE_VALUE                0x0B
#define FTS_CMD_FLASH_STATUS                        0x6A
#define FTS_CMD_ERASE_APP                           0x61

#define FTS_CMD_START_DELAY                 		12

/* register address */
#define FTS_REG_WORKMODE                    		0x00
#define FTS_REG_WORKMODE_FACTORY_VALUE      		0x40
#define FTS_REG_WORKMODE_SCAN_VALUE				    	0xC0
#define FTS_REG_FLOW_WORK_CNT               		0x91
#define FTS_REG_POWER_MODE                  		0xA5
#define FTS_REG_GESTURE_EN                  		0xD0
#define FTS_REG_GESTURE_ENABLE              		0x01
#define FTS_REG_GESTURE_OUTPUT_ADDRESS      		0xD3


#define FT3X68_I2C_ADDRESS	(0x38)
#define FT3X68_TOUCH_NUMBER_MAX (5)
typedef struct{
    uint8_t x_h;
    uint8_t x_l;
    uint8_t y_h;
    uint8_t y_l;
    uint8_t w;
}luat_tp_touch_t;

typedef struct ft3x68_tp{
	uint8_t is_inited;
	uint8_t scan_time;
	uint8_t is_scan;
    uint8_t touch_num;
    luat_tp_touch_t point[FT3X68_TOUCH_NUMBER_MAX];
}luat_tp_info_t;

static int16_t pre_x[FT3X68_TOUCH_NUMBER_MAX] = {-1, -1, -1, -1, -1};
static int16_t pre_y[FT3X68_TOUCH_NUMBER_MAX] = {-1, -1, -1, -1, -1};
static int16_t pre_w[FT3X68_TOUCH_NUMBER_MAX] = {-1, -1, -1, -1, -1};
static uint8_t s_tp_down[FT3X68_TOUCH_NUMBER_MAX];
static uint8_t pre_touch = 0;
static int8_t pre_id[FT3X68_TOUCH_NUMBER_MAX] = {0};
static luat_tp_info_t ft3x68_tp;

static int luat_tp_irq_cb(int pin, void *args){
    if (ft3x68_tp.is_inited == 0){
        return -1;
    }
    luat_tp_config_t* luat_tp_config = (luat_tp_config_t*)args;
    luat_tp_irq_enable(luat_tp_config, 0);
    luat_rtos_message_send(luat_tp_config->task_handle, 1, args);
    return 0;
}

static int tp_ft3x68_init(luat_tp_config_t* luat_tp_config)
{
    if (luat_tp_config->pin_rst != LUAT_GPIO_NONE){
        luat_gpio_mode(luat_tp_config->pin_rst, Luat_GPIO_OUTPUT, Luat_GPIO_DEFAULT, Luat_GPIO_LOW);
        luat_gpio_set(luat_tp_config->pin_rst, Luat_GPIO_HIGH);
        luat_rtos_task_sleep(5);
        luat_gpio_set(luat_tp_config->pin_rst, Luat_GPIO_LOW);
        luat_rtos_task_sleep(20);
        luat_gpio_set(luat_tp_config->pin_rst, Luat_GPIO_HIGH);
        luat_rtos_task_sleep(50);
    }

    if (luat_tp_config->soft_i2c != NULL){
        i2c_soft_setup(luat_tp_config->soft_i2c);
    }else{
        luat_i2c_setup(luat_tp_config->i2c_id, I2C_SPEED_SLOW);
    }
    luat_tp_config->address = FT3X68_I2C_ADDRESS;
    uint8_t id[4] = {FT3X68_CHIP_VENDOR_ID, 0, 0, 0};
    tp_i2c_read(luat_tp_config, id, 1, id, 4, 1);
    if (id[0] == FTS_CHIP_IDH)
    {
    	LLOGD("find ft3x68");
        if (luat_tp_config->pin_int != LUAT_GPIO_NONE)
        {
            luat_gpio_t gpio = {0};
            gpio.pin = luat_tp_config->pin_int;
            gpio.mode = Luat_GPIO_IRQ;
            gpio.pull = Luat_GPIO_PULLUP;
            gpio.irq = LUAT_GPIO_FALLING_IRQ;
            gpio.irq_cb = luat_tp_irq_cb;
            gpio.irq_args = luat_tp_config;
            luat_gpio_setup(&gpio);
        }
        ft3x68_tp.is_inited = 1;
    }
    return 0;
}


static int tp_ft3x68_deinit(luat_tp_config_t* luat_tp_config){
	ft3x68_tp.is_inited = 0;
    if (luat_tp_config->pin_int != LUAT_GPIO_NONE){
        luat_gpio_close(luat_tp_config->pin_int);
    }
    if (luat_tp_config->pin_rst != LUAT_GPIO_NONE){
        luat_gpio_close(luat_tp_config->pin_rst);
    }
    return 0;
}

static void tp_ft3x68_read_done(luat_tp_config_t * luat_tp_config){
    if (luat_gpio_get(luat_tp_config->pin_int)){
        luat_tp_irq_enable(luat_tp_config, 1);
    }else{
        luat_rtos_message_send(luat_tp_config->task_handle, 1, luat_tp_config);
    }
}

void ft3x68_touch_up(void *buf, int8_t id){
	luat_tp_data_t *read_data = (luat_tp_data_t *)buf;
	if (pre_x[id] == -1 && pre_y[id] == -1)
	{
		read_data[id].event = TP_EVENT_TYPE_NONE;
		return;
	}

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

void ft3x68_touch_down(void *buf, int8_t id, int16_t x, int16_t y, int16_t w){
	luat_tp_data_t *read_data = (luat_tp_data_t *)buf;
	if (x == pre_x[id] && y == pre_y[id])
	{
		read_data[id].event = TP_EVENT_TYPE_NONE;
		return;
	}
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

void ft3x68_read_point(luat_tp_config_t* luat_tp_config, luat_tp_touch_t *input_buff, void *buf, uint8_t touch_num){
	luat_tp_touch_t *read_buf = input_buff;
	uint8_t read_index;
	int8_t read_id = 0;
	int16_t input_x = 0;
	int16_t input_y = 0;
	int16_t input_w = 0;



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
					ft3x68_touch_up(buf, up_id);
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
			ft3x68_touch_down(buf, read_index, input_x, input_y, input_w);
		}
	}else if (pre_touch){
		for(read_index = 0; read_index < pre_touch; read_index++){
			ft3x68_touch_up(buf, pre_id[read_index]);
		}
	}
	pre_touch = touch_num;
}
const int FT3X68_TPX_TBL[5]={FT3X68_TP1_REG,FT3X68_TP2_REG,FT3X68_TP3_REG,FT3X68_TP4_REG,FT3X68_TP5_REG};
static int tp_ft3x68_read(luat_tp_config_t* luat_tp_config, luat_tp_data_t *luat_tp_data){
    uint8_t touch_num=0, point_status=0;
    uint8_t temp[1] = {FT3X68_TD_STATUS};
    if (!tp_i2c_read(luat_tp_config, temp, 1, temp, 4, 1))
    {
    	touch_num = temp[0] & 0x0f;
    	if(touch_num && (touch_num <= FT3X68_TOUCH_NUMBER_MAX))
    	{
    		for(int i = 0; i < touch_num; i++)
    		{
    			temp[0] = FT3X68_TPX_TBL[i];
    			if (!tp_i2c_read(luat_tp_config, temp, 1, &ft3x68_tp.point[i], 4, 1))
    			{
//    				LLOGD("point %d data%x,%x,%x,%x", i, ft3x68_tp.point[i].x_h, ft3x68_tp.point[i].x_l, ft3x68_tp.point[i].y_h, ft3x68_tp.point[i].y_l);
    				if (0x80 != (ft3x68_tp.point[i].x_h & 0xF0))
    				{
//    					LLOGE("point %d data error %x,%x,%x,%x", i, ft3x68_tp.point[i].x_h, ft3x68_tp.point[i].x_l, ft3x68_tp.point[i].y_h, ft3x68_tp.point[i].y_l);
    					memset(&ft3x68_tp.point[i], 0, sizeof(ft3x68_tp.point[i]));
    					touch_num--;
    				}
    				else
    				{
    					ft3x68_tp.point[i].x_h &= 0x0f;
    					point_status = 1;
    				}
    			}
    		}
    	}
    }
    if (point_status || pre_touch)
    {
    	ft3x68_tp.touch_num = touch_num;
    	ft3x68_read_point(luat_tp_config, ft3x68_tp.point, luat_tp_data, ft3x68_tp.touch_num);
    }
    else
    {
    	if (!pre_touch && !touch_num)
    	{
    		memset(luat_tp_data, 0, sizeof(luat_tp_data_t) * LUAT_TP_TOUCH_MAX);
    	}
    }
    return touch_num;
}

luat_tp_opts_t tp_config_ft3x68 = {
    .name = "ft3x68",
    .init = tp_ft3x68_init,
    .deinit = tp_ft3x68_deinit,
    .read = tp_ft3x68_read,
	.read_done = tp_ft3x68_read_done,
};
