#ifndef LUAT_TP_H
#define LUAT_TP_H

#include "luat_mcu.h"
#include "luat_rtos.h"
#include "luat_i2c.h"

#define LUAT_TP_TOUCH_MAX 10

typedef struct luat_tp_config luat_tp_config_t;
typedef struct luat_tp_opts luat_tp_opts_t;

enum{
    LUAT_TP_ROTATE_0 = 0,
    LUAT_TP_ROTATE_90,
    LUAT_TP_ROTATE_180,
    LUAT_TP_ROTATE_270,
};

typedef struct{
	uint32_t         timestamp;
    uint16_t         x_coordinate;
    uint16_t         y_coordinate;
    uint8_t          event;
    uint8_t          track_id;
    uint8_t          width;
} luat_tp_data_t;

typedef struct luat_tp_config{
    char* name;
    luat_ei2c_t* soft_i2c;
    uint8_t address;
    uint8_t i2c_id;
    uint8_t pin_rst;
    uint8_t pin_int;
    uint8_t swap_xy;
    uint8_t direction;  // 旋转方向(软件控制) 
    uint8_t refresh_rate;
    uint8_t tp_num;
    uint8_t int_type;
    int16_t w;
    int16_t h;
    void* luat_cb;
    luat_tp_opts_t* opts;
    int (*callback)(luat_tp_config_t* luat_tp_config, luat_tp_data_t* luat_tp_data);
    luat_tp_data_t tp_data[LUAT_TP_TOUCH_MAX];
    luat_rtos_task_handle task_handle;
} luat_tp_config_t;

typedef struct luat_tp_opts {
    const char* name;
    int (*init)(luat_tp_config_t* luat_tp_config);
    int (*read)(luat_tp_config_t* luat_tp_config, uint8_t* data);
    void (*read_done)(luat_tp_config_t* luat_tp_config);
    void (*deinit)(luat_tp_config_t* luat_tp_config);
} luat_tp_opts_t;

typedef enum{
	TP_EVENT_TYPE_NONE = 0,
	TP_EVENT_TYPE_DOWN,
	TP_EVENT_TYPE_UP,
	TP_EVENT_TYPE_MOVE
} luat_tp_event_type_t;


extern luat_tp_opts_t tp_config_gt911;
extern luat_tp_opts_t tp_config_gt9157;
extern luat_tp_opts_t tp_config_jd9261t;
extern luat_tp_opts_t tp_config_jd9261t_inited;
extern luat_tp_opts_t tp_config_ft3x68;
extern luat_tp_opts_t tp_config_cst820;
extern luat_tp_opts_t tp_config_cst92xx;

int luat_tp_init(luat_tp_config_t* luat_tp_config);

int luat_tp_irq_enable(luat_tp_config_t* luat_tp_config, uint8_t enabled);




#endif
