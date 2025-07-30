#include "luat_base.h"
#include "luat_tp.h"
#include "luat_gpio.h"
#include "luat_mem.h"
#include "luat_rtos.h"
#include "luat_tp_reg.h"

#include "cst92xx_fw.h"


#define LUAT_LOG_TAG "cst92xx"
#include "luat_log.h"

#define HYN_POWER_ON_UPDATA           (0) //touch fw updata

#define CST92XX_ADDRESS               (0x5A)

#define CST9217_CHIP_ID_CODE          (0x9217)
#define CST9220_CHIP_ID_CODE          (0x9220)

#define CST92XX_CHIP_ID               (0xA7)

#define CST92XX_STATUS                (0x02)

#define CST92XX_POINT1_REG            (0x03)

#define CST92XX_CONFIG_SIZE           (CST92XX_CONFIG_FRESH - CST92XX_CONFIG_REG + 1)
#define CST92XX_POINT_INFO_NUM        (5)
#define CST92XX_TOUCH_NUMBER_MIN      (1)
#define CST92XX_TOUCH_NUMBER_MAX      (5)

#define CST92XX_REFRESH_RATE_MIN      (5)
#define CST92XX_REFRESH_RATE_MAX      (20)

#define U8TO16(x1,x2) ((((x1)&0xFF)<<8)|((x2)&0xFF))
#define U8TO32(x1,x2,x3,x4) ((((x1)&0xFF)<<24)|(((x2)&0xFF)<<16)|(((x3)&0xFF)<<8)|((x4)&0xFF))
#define U16REV(x)  ((((x)<<8)&0xFF00)|(((x)>>8)&0x00FF))

enum work_mode{
    NOMAL_MODE = 0,
    GESTURE_MODE = 1,
    LP_MODE = 2,
    DEEPSLEEP = 3,
    DIFF_MODE = 4,
    RAWDATA_MODE = 5,
    BASELINE_MODE = 6,
    CALIBRATE_MODE = 7,
    FAC_TEST_MODE = 8,
    ENTER_BOOT_MODE = 0xCA,
};

struct tp_info{
    uint8_t  fw_sensor_txnum;
    uint8_t  fw_sensor_rxnum;
    uint8_t  fw_key_num;
    uint8_t  reserve;
    uint16_t fw_res_y;
    uint16_t fw_res_x;
    uint32_t fw_boot_time;
    uint32_t fw_project_id;
    uint32_t fw_chip_type;
    uint32_t fw_ver;
    uint32_t ic_fw_checksum;
    uint32_t fw_module_id;
};

typedef struct hyn_ts_data {
    enum work_mode work_mode;
    struct tp_info hw_info;
    int boot_is_pass;
    int need_updata_fw;
}hyn_ts_data_t;

static hyn_ts_data_t hyn_92xxdata = {0};

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

static uint8_t cst92xx_init_state = 0;

static int hyn_wr_reg(luat_tp_config_t* luat_tp_config, uint32_t reg_addr, uint8_t reg_len, uint8_t *rbuf, uint16_t rlen){
    int ret = 0,i=0;
    uint8_t wbuf[4] = {0};
    i = reg_len;
    while(i){
        i--;
        wbuf[i] = reg_addr;
        reg_addr >>= 8;
    }

    if (luat_tp_config->soft_i2c != NULL){
        ret = i2c_soft_send(luat_tp_config->soft_i2c, luat_tp_config->address, (char *)wbuf, reg_len, rlen?0:1);
    }else{
        ret = luat_i2c_send(luat_tp_config->i2c_id, luat_tp_config->address, wbuf, reg_len, rlen?0:1);
    }
    if(rlen){
        if (luat_tp_config->soft_i2c != NULL){
            ret |= i2c_soft_recv(luat_tp_config->soft_i2c, luat_tp_config->address, rbuf, rlen);
        }else{
            ret |= luat_i2c_recv(luat_tp_config->i2c_id, luat_tp_config->address, rbuf, rlen);
        }
    }

    return ret;
}

int tp_cst92xx_clear_status(luat_tp_config_t* luat_tp_config){
	if (tp_i2c_write_reg16(luat_tp_config, CST92XX_STATUS, (uint8_t[]){0x00}, 1)){
		LLOGE("write status reg fail!");
		return -1;
	}
	return 0;
}

static int tp_cst92xx_detect(luat_tp_config_t* luat_tp_config){
    struct tp_info *ic = &hyn_92xxdata.hw_info;
    // LLOGD("module_id: 0x%04x", ic->fw_chip_type);
    if ((ic->fw_chip_type != CST9217_CHIP_ID_CODE) && (ic->fw_chip_type != CST9220_CHIP_ID_CODE)){
        LLOGE("fw_chip_type error 0x%04x", ic->fw_chip_type);
        return -1;
    }else{
        LLOGI("TP find device CST9220 ,address:0x%02X",luat_tp_config->address);
    }
    return 0;
}

static int luat_tp_irq_cb(int pin, void *args){
    if (cst92xx_init_state == 0){
        return -1;
    }
    luat_tp_config_t* luat_tp_config = (luat_tp_config_t*)args;
    luat_tp_irq_enable(luat_tp_config, 0);
    luat_rtos_message_send(luat_tp_config->task_handle, 1, args);
    return 0;
}

static int tp_cst92xx_set_workmode(luat_tp_config_t* luat_tp_config, enum work_mode mode,uint8_t enable){
    int ret = -1;
    uint8_t i2c_buf[4] = {0};
    uint8_t i = 0;
    hyn_92xxdata.work_mode = mode;
    if(mode != NOMAL_MODE){

    }
    for(i=0;i<3;i++){
        luat_rtos_task_sleep(2);
        if (hyn_wr_reg(luat_tp_config,0xD11E,2,i2c_buf,0)) {
            luat_rtos_task_sleep(1);
            continue;
        }
        luat_rtos_task_sleep(2);
        if (hyn_wr_reg(luat_tp_config,0x0002,2,i2c_buf,2)) {
            luat_rtos_task_sleep(1);
            continue;
        }
        if(i2c_buf[1] == 0x1E){
            break;
        }
    }

    switch(mode){
        case NOMAL_MODE:
            luat_tp_irq_enable(luat_tp_config, 1);
            if (hyn_wr_reg(luat_tp_config,0xD109,2,i2c_buf,0)) {
                return -1;
            }
            break;
        case GESTURE_MODE:
            if (hyn_wr_reg(luat_tp_config,0xD104,2,i2c_buf,0)) {
                return -1;
            }
            break;
        case LP_MODE:
            if (hyn_wr_reg(luat_tp_config,0xD107,2,i2c_buf,0)) {
                return -1;
            }
            break;
        case DIFF_MODE:
            if (hyn_wr_reg(luat_tp_config,0xD10D,2,i2c_buf,0)) {
                return -1;
            }
            break;

        case RAWDATA_MODE:
            if (hyn_wr_reg(luat_tp_config,0xD10A,2,i2c_buf,0)) {
                return -1;
            }
            break;
        case FAC_TEST_MODE:
            hyn_wr_reg(luat_tp_config,0xD114,2,i2c_buf,0);
            break;
        case DEEPSLEEP:
            hyn_wr_reg(luat_tp_config,0xD105,2,i2c_buf,0);
            break;
        default :
            hyn_92xxdata.work_mode = NOMAL_MODE;
            break;
    }

    return 0;
}

static int tp_cst92xx_updata_tpinfo(luat_tp_config_t* luat_tp_config){
    uint8_t buf[30] = {0};
    struct tp_info *ic = &hyn_92xxdata.hw_info;

    tp_cst92xx_set_workmode(luat_tp_config, 0xff,0);
    if(hyn_wr_reg(luat_tp_config,0xD101,2,buf,0)){
        return -1;
    }
    luat_rtos_task_sleep(5);

    //firmware_project_id   firmware_ic_type
    if(hyn_wr_reg(luat_tp_config,0xD1F4,2,buf,28)){
        return -1;
    }
    ic->fw_project_id = ((uint16_t)buf[17] <<8) + buf[16];
    ic->fw_chip_type = ((uint16_t)buf[19] <<8) + buf[18];

    //firmware_version
    ic->fw_ver = (buf[23]<<24)|(buf[22]<<16)|(buf[21]<<8)|buf[20];

    //tx_num   rx_num   key_num
    ic->fw_sensor_txnum = ((uint16_t)buf[1]<<8) + buf[0];
    ic->fw_sensor_rxnum = buf[2];
    ic->fw_key_num = buf[3];

    ic->fw_res_y = (buf[7]<<8)|buf[6];
    ic->fw_res_x = (buf[5]<<8)|buf[4];

    //fw_checksum
    ic->ic_fw_checksum = (buf[27]<<24)|(buf[26]<<16)|(buf[25]<<8)|buf[24];

    LLOGD("IC_info project_id:%04x ictype:%04x fw_ver:%x checksum:%#x",ic->fw_project_id,ic->fw_chip_type,ic->fw_ver,ic->ic_fw_checksum);

    tp_cst92xx_set_workmode(luat_tp_config,NOMAL_MODE,1);
    return 0;
}

static int tp_cst92xx_hw_reset(luat_tp_config_t* luat_tp_config){
    if (luat_tp_config->pin_rst != LUAT_GPIO_NONE){
        luat_gpio_set(luat_tp_config->pin_rst, Luat_GPIO_LOW);
        luat_rtos_task_sleep(8);
        luat_gpio_set(luat_tp_config->pin_rst, Luat_GPIO_HIGH);
    }
    return 0;
}

static int16_t read_word_from_mem(luat_tp_config_t* luat_tp_config, uint8_t type, uint16_t addr, uint32_t *value){
    uint8_t i2c_buf[4] = {0};

    i2c_buf[0] = 0xA0;
    i2c_buf[1] = 0x10;
    i2c_buf[2] = type;
    if (tp_i2c_write(luat_tp_config, i2c_buf, 3, NULL, 0)){
        return -1;
    }

    i2c_buf[0] = 0xA0;
    i2c_buf[1] = 0x0C;
    i2c_buf[2] = addr;
    i2c_buf[3] = addr >> 8;
    if (tp_i2c_write(luat_tp_config, i2c_buf, 4, NULL, 0)){
        return -1;
    }

    i2c_buf[0] = 0xA0;
    i2c_buf[1] = 0x04;
    i2c_buf[2] = 0xE4;
    if (tp_i2c_write(luat_tp_config, i2c_buf, 3, NULL, 0)){
        return -1;
    }

    for (uint8_t t = 0;; t++){
        if (t >= 100){
            return -1;
        }
        if (hyn_wr_reg(luat_tp_config, 0xA004,2,i2c_buf,1)){
            continue;
        }
        if (i2c_buf[0] == 0x00){
            break;
        }
    }
    if (hyn_wr_reg(luat_tp_config, 0xA018,2, i2c_buf, 4)){
        return -1;
    }
    *value = ((uint32_t)(i2c_buf[0])) |
             (((uint32_t)(i2c_buf[1])) << 8) |
             (((uint32_t)(i2c_buf[2])) << 16) |
             (((uint32_t)(i2c_buf[3])) << 24);

    return 0;
}

static int  tp_cst92xx_enter_boot(luat_tp_config_t* luat_tp_config){
    uint8_t i2c_buf[4] = {0};
    for (uint8_t t = 10; t < 30; t += 2){
        tp_cst92xx_hw_reset(luat_tp_config);
        luat_rtos_task_sleep(t);

        if(hyn_wr_reg(luat_tp_config, 0xA001AA, 3, i2c_buf, 0)){
            continue;
        }

        luat_rtos_task_sleep(1);

        if(hyn_wr_reg(luat_tp_config, 0xA002,  2, i2c_buf, 2)){
            continue;
        }

        if ((i2c_buf[0] == 0x55) && (i2c_buf[1] == 0xB0)) {
            break;
        }
    }

    if(hyn_wr_reg(luat_tp_config, 0xA00100, 3, i2c_buf, 0)){
        return -1;
    }

    return 0;
}

static int tp_cst92xx_read_chip_id(luat_tp_config_t* luat_tp_config){
    int16_t ret = 0;
    uint8_t retry = 3;
    uint32_t partno_chip_type,module_id;

    if (tp_cst92xx_enter_boot(luat_tp_config)){
        LLOGE("enter_bootloader error");
        return -1;
    }
    for (; retry > 0; retry--){
        // partno
        ret = read_word_from_mem(luat_tp_config, 1, 0x077C, &partno_chip_type);
        if (ret){
            continue;
        }
        // module id
        ret = read_word_from_mem(luat_tp_config, 0, 0x7FC0, &module_id);
        if (ret){
            continue;
        }
        if ((partno_chip_type >> 16) == 0xCACA){
            partno_chip_type &= 0xffff;
            break;
        }
    }
    tp_cst92xx_hw_reset(luat_tp_config);
    luat_rtos_task_sleep(30);
    LLOGD("partno_chip_type: 0x%04x", partno_chip_type);
    LLOGD("module_id: 0x%04x", module_id);
    if ((partno_chip_type != CST9217_CHIP_ID_CODE) && (partno_chip_type != CST9220_CHIP_ID_CODE)){
        LLOGE("partno_chip_type error 0x%04x", partno_chip_type);
        // return -1;
    }
    return 0;
}

static uint32_t cst92xx_read_checksum(luat_tp_config_t* luat_tp_config){
    uint8_t i2c_buf[4] = {0};
    uint32_t chip_checksum = 0;
    uint8_t retry = 5;
    
    hyn_92xxdata.boot_is_pass = 0;

    if (hyn_wr_reg(luat_tp_config,0xA00300,3,i2c_buf,0)) {
        return -1;
    }      
    luat_rtos_task_sleep(2);    
    while(retry--){
        luat_rtos_task_sleep(5);
        if (hyn_wr_reg(luat_tp_config,0xA000,2,i2c_buf,1)) {
            continue;
        }
        if(i2c_buf[0]!=0) break;
    }

    luat_rtos_task_sleep(1);
    if(i2c_buf[0] == 0x01){
        hyn_92xxdata.boot_is_pass = 1;
        memset(i2c_buf,0,sizeof(i2c_buf));

        if (hyn_wr_reg(luat_tp_config,0xA008,2,i2c_buf,4)) {
            return -1;
        }      

        chip_checksum = ((uint32_t)(i2c_buf[0])) |
            (((uint32_t)(i2c_buf[1])) << 8) |
            (((uint32_t)(i2c_buf[2])) << 16) |
            (((uint32_t)(i2c_buf[3])) << 24);
    }
    else{
        hyn_92xxdata.need_updata_fw = 1;
    }

    return chip_checksum;
}

static int cst92xx_updata_judge(luat_tp_config_t* luat_tp_config, uint8_t *p_fw, uint16_t len){
    uint32_t f_checksum,f_fw_ver,f_ictype,f_fw_project_id;
    uint8_t *p_data = p_fw + len - 28;   //7F64
    struct tp_info *ic = &hyn_92xxdata.hw_info;

    if (tp_cst92xx_enter_boot(luat_tp_config)){
        LLOGI("cst92xx_enter_boot fail,need update");
        return -1; 
    }
    hyn_92xxdata.hw_info.ic_fw_checksum = cst92xx_read_checksum(luat_tp_config);
    if(hyn_92xxdata.boot_is_pass == 0){
        LLOGI("boot_is_pass %d,need force update",hyn_92xxdata.boot_is_pass);
        return -1; //need updata
    }
    
    f_fw_project_id = U8TO16(p_data[1],p_data[0]);
    f_ictype = U8TO16(p_data[3],p_data[2]);

    f_fw_ver = U8TO16(p_data[7],p_data[6]);
    f_fw_ver = (f_fw_ver<<16)|U8TO16(p_data[5],p_data[4]);

    f_checksum = U8TO16(p_data[11],p_data[10]);
    f_checksum = (f_checksum << 16)|U8TO16(p_data[9],p_data[8]);


    LLOGI("Bin_info project_id:0x%04x ictype:0x%04x fw_ver:0x%x checksum:0x%x",f_fw_project_id,f_ictype,f_fw_ver,f_checksum);
    if(f_ictype != ic->fw_chip_type || f_fw_project_id != ic->fw_project_id){
        LLOGE("not update,please confirm: ic_type 0x%04x,ic_project_id 0x%04x",ic->fw_chip_type,ic->fw_project_id);
        return 0; //not updata
    }
    if(f_checksum != ic->ic_fw_checksum && f_fw_ver > ic->fw_ver){
        LLOGI("need update!");
        return -1; //need updata
    }
    LLOGI("cst92xx_updata_judge done, no need update");
    return 0;
}


static int tp_cst92xx_gpio_init(luat_tp_config_t* luat_tp_config){
    luat_gpio_mode(luat_tp_config->pin_rst, Luat_GPIO_OUTPUT, Luat_GPIO_DEFAULT, Luat_GPIO_HIGH);
    luat_gpio_mode(luat_tp_config->pin_int, Luat_GPIO_OUTPUT, Luat_GPIO_DEFAULT, Luat_GPIO_HIGH);
    luat_gpio_set(luat_tp_config->pin_rst, Luat_GPIO_HIGH);
    luat_gpio_set(luat_tp_config->pin_int, Luat_GPIO_HIGH);
    luat_rtos_task_sleep(10);
    return 0;
}

static int tp_cst92xx_init(luat_tp_config_t* luat_tp_config){
    int ret = 0;
    luat_rtos_task_sleep(100);
    tp_cst92xx_gpio_init(luat_tp_config);

    luat_tp_config->int_type = Luat_GPIO_FALLING;

    luat_gpio_t gpio = {0};
    gpio.pin = luat_tp_config->pin_int;
    gpio.mode = Luat_GPIO_IRQ;
    gpio.pull = Luat_GPIO_PULLUP;
    gpio.irq = luat_tp_config->int_type;
    gpio.irq_cb = luat_tp_irq_cb;
    gpio.irq_args = luat_tp_config;
    luat_gpio_setup(&gpio);
    luat_tp_config->address = CST92XX_ADDRESS;
    tp_cst92xx_hw_reset(luat_tp_config);
    luat_rtos_task_sleep(40);

#if HYN_POWER_ON_UPDATA
    if(tp_cst92xx_read_chip_id(luat_tp_config)){
        LLOGE("cst92xx_read_chip_id failed");
        return ret;
    }

    ret = tp_cst92xx_updata_tpinfo(luat_tp_config);
    if(ret){
        LLOGE("cst92xx_updata_tpinfo failed");
        return ret;
    }
    cst92xx_updata_judge(luat_tp_config,(uint8_t*)fw_bin,CST92XX_BIN_SIZE);
    tp_cst92xx_hw_reset(luat_tp_config);
    luat_rtos_task_sleep(40);
#endif

    ret = tp_cst92xx_updata_tpinfo(luat_tp_config);
    if(ret){
        LLOGE("cst92xx_updata_tpinfo failed");
        return ret;
    }

    ret = tp_cst92xx_detect(luat_tp_config);
    if (ret){
        LLOGE("tp detect fail!");
        return ret;
    }
    ret |= tp_cst92xx_set_workmode(luat_tp_config, NOMAL_MODE,0);
    luat_rtos_task_sleep(20);
    cst92xx_init_state = 1;
    return ret;
}

static int tp_cst92xx_deinit(luat_tp_config_t* luat_tp_config){
    cst92xx_init_state = 0;
    if (luat_tp_config->pin_int != LUAT_GPIO_NONE){
        luat_gpio_close(luat_tp_config->pin_int);
    }
    if (luat_tp_config->pin_rst != LUAT_GPIO_NONE){
        luat_gpio_close(luat_tp_config->pin_rst);
    }
    return 0;
}

static void tp_cst92xx_read_done(luat_tp_config_t * luat_tp_config){
	luat_tp_irq_enable(luat_tp_config, 1);
}

// cst92xx get tp info.
typedef struct {
    uint8_t switch_ : 4;
    uint8_t id : 4;
    uint8_t x_h : 4;
    uint8_t  : 4;
    uint8_t y_h : 4;
    uint8_t  : 4;
    uint8_t y_l : 4;
    uint8_t x_l : 4;
    uint8_t z : 7;
    uint8_t  : 1;
} point_data_t;

static int16_t pre_x[CST92XX_TOUCH_NUMBER_MAX] = {-1, -1};
static int16_t pre_y[CST92XX_TOUCH_NUMBER_MAX] = {-1, -1};
static int16_t pre_w[CST92XX_TOUCH_NUMBER_MAX] = {-1, -1};
static uint8_t s_tp_down[CST92XX_TOUCH_NUMBER_MAX];

static uint8_t read_buff[CST92XX_POINT_INFO_NUM * CST92XX_TOUCH_NUMBER_MAX + 5] = {0};

void cst92xx_touch_up(void *buf, int8_t id){
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

void cst92xx_touch_down(void *buf, int8_t id, int16_t x, int16_t y, int16_t w){
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

void cst92xx_read_point(uint8_t *input_buff, void *buf, uint8_t touch_num){
	uint8_t *read_buf = input_buff;
	uint8_t read_index;
	int8_t read_id = 0;
	int16_t input_x = 0;
	int16_t input_y = 0;
	int16_t input_w = 0;

	static uint8_t pre_touch = 0;
	static int8_t pre_id[CST92XX_TOUCH_NUMBER_MAX] = {0};

	if (pre_touch > touch_num){                                       /* point up */
		for (read_index = 0; read_index < pre_touch; read_index++){
			uint8_t j;
			for (j = 0; j < touch_num; j++){                          /* this time touch num */
				read_id = j;
				if (read_id >= CST92XX_POINT_INFO_NUM){
					LLOGE("%s, touch ID %d is out range!\r\n", __func__, read_id);
					return;
				}
				if (pre_id[read_index] == read_id)                   /* this id is not free */
					break;

				if (j >= touch_num - 1){
					uint8_t up_id;
					up_id = pre_id[read_index];
					cst92xx_touch_up(buf, up_id);
				}
			}
		}
	}
	if (touch_num){                                                 /* point down */
		uint8_t off_set = 0;
		for (read_index = 0; read_index < touch_num; read_index++){
            if (read_index){
                off_set = read_index * CST92XX_POINT_INFO_NUM + 2;
            }
			
			read_id = read_index;
			if (read_id >= CST92XX_POINT_INFO_NUM){
				LLOGE("%s, touch ID %d is out range!", __func__, read_id);
				return;
			}
			pre_id[read_index] = read_id;
            point_data_t* point_buff = &read_buf[off_set];
            LLOGD("%s, id %d switch:0x%02x z:%d", __func__, point_buff->id,point_buff->switch_,point_buff->z);

			input_x = point_buff->x_h << 4 | point_buff->x_l;	/* x */
			input_y = point_buff->y_h << 4 | point_buff->y_l;	/* y */
			cst92xx_touch_down(buf, read_id, input_x, input_y, input_w);
		}
	}else if (pre_touch){
		for(read_index = 0; read_index < pre_touch; read_index++){
			cst92xx_touch_up(buf, pre_id[read_index]);
		}
	}
	pre_touch = touch_num;
}

int tp_cst92xx_read_status(luat_tp_config_t* luat_tp_config, uint8_t *status){
	if (tp_i2c_read_reg16(luat_tp_config, CST92XX_STATUS, status, 1, 1)){
		LLOGE("read status reg fail!\r\n");
		return -1;
	}
	// LLOGD("status=0x%02X\r\n", *status); // 调试需要看!!!
	return 0;
}


static int tp_cst92xx_read(luat_tp_config_t* luat_tp_config, luat_tp_data_t *luat_tp_data){
    uint8_t touch_num=0, point_status=0;
    // uint8_t i2c_buf[CST92XX_TOUCH_NUMBER_MAX*5+5] = {0};
    memset(read_buff, 0x00, sizeof(read_buff));

    if (hyn_wr_reg(luat_tp_config, 0xD000,2,read_buff,sizeof(read_buff))){
        goto exit_;
    }   
        
    if (hyn_wr_reg(luat_tp_config, 0xD000AB,3,read_buff,0)){
        goto exit_;
    }   

    luat_rtos_task_sleep(8);
    // for (size_t i = 0; i < sizeof(read_buff); i++){
    //     LLOGD("read_buff[%d] = 0x%02X", i, read_buff[i]);
    // }

    if (read_buff[6] != 0xAB) {
        // LLOGE("fail buf[6]=0x%02x",i2c_buf[6]);
        goto exit_;
    }

    touch_num = read_buff[5] & 0x7F;

    if (touch_num > CST92XX_TOUCH_NUMBER_MAX) {
        LLOGE("fail touch_num=%d",touch_num);
        goto exit_;
    }

    // LLOGD("touch_num = %d",touch_num);

    if (touch_num > CST92XX_TOUCH_NUMBER_MAX) {/* point num is not correct */
        touch_num = 0;
        goto exit_;
    }

    
    if (touch_num){
    //     tp_i2c_read_reg8(luat_tp_config, CST92XX_POINT1_REG, read_buff, touch_num * CST92XX_POINT_INFO_NUM, 0);
    }else{
        memset(read_buff, 0x00, sizeof(read_buff));
    }

    cst92xx_read_point(read_buff, luat_tp_data, touch_num);
    
exit_:
    // tp_cst92xx_clear_status(luat_tp_config);
    return touch_num;
}

luat_tp_opts_t tp_config_cst92xx = {
    .name = "cst92xx",
    .init = tp_cst92xx_init,
    .deinit = tp_cst92xx_deinit,
    .read = tp_cst92xx_read,
	.read_done = tp_cst92xx_read_done,
};
