#ifndef LUAT_TP_H
#define LUAT_TP_H

#include "luat_mcu.h"
#include "luat_rtos.h"
#include "luat_i2c.h"

extern luat_rtos_task_handle tp_task_handle;

typedef struct luat_tp_config luat_tp_config_t;

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
        };
        uint64_t info;
    };
}luat_tp_info_t;

typedef struct{
    uint8_t          event;
    uint8_t          track_id;
    uint16_t         x_coordinate;
    uint16_t         y_coordinate;
    uint8_t          width;
    uint32_t         timestamp;
} luat_tp_data_t;

typedef struct luat_tp_config{
    char* name;
    luat_ei2c_t* soft_i2c;
    uint8_t address;
    uint8_t i2c_id;
    uint8_t pin_rst;
    uint8_t pin_int;
    uint8_t swap_xy;
    uint8_t refresh_rate;
    uint8_t tp_num;
    uint8_t int_type;
    int16_t w;
    int16_t h;
    int (*init)(luat_tp_config_t* luat_tp_config);
    int (*read)(luat_tp_config_t* luat_tp_config, uint8_t* data);
    void (*deinit)(luat_tp_config_t* luat_tp_config);
    int (*callback)(luat_tp_config_t* luat_tp_config, luat_tp_data_t* luat_tp_data);
} luat_tp_config_t;

typedef enum{
	TP_EVENT_TYPE_NONE = 0,
	TP_EVENT_TYPE_DOWN,
	TP_EVENT_TYPE_UP,
	TP_EVENT_TYPE_MOVE
} luat_tp_event_type_t;

typedef enum{
	TP_INT_TYPE_RISING_EDGE = 0,
	TP_INT_TYPE_FALLING_EDGE,
} luat_tp_int_type_t;

int luat_tp_init(luat_tp_config_t* luat_tp_config);
















#endif