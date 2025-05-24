#include "luat_base.h"
#include "luat_tp.h"
#include "luat_mem.h"
#include "luat_gpio.h"

#define LUAT_LOG_TAG "tp"
#include "luat_log.h"


static luat_rtos_task_handle g_s_tp_task_handle = NULL;

uint16_t last_x = 0;
uint16_t last_y = 0;
void luat_tp_task_entry(void* param){
    uint32_t message_id = 0;
    luat_tp_config_t *luat_tp_config = NULL;
    while (1){
        luat_rtos_message_recv(g_s_tp_task_handle, &message_id, &luat_tp_config, LUAT_WAIT_FOREVER);
        luat_tp_data_t* tp_data = luat_tp_config->tp_data;
        luat_tp_config->opts->read(luat_tp_config,tp_data);
        uint16_t coordinate_tmp;

        if (luat_tp_config->direction == LUAT_TP_ROTATE_90){
            coordinate_tmp = tp_data->x_coordinate;
            tp_data->x_coordinate = tp_data->y_coordinate;
            tp_data->y_coordinate = luat_tp_config->w - coordinate_tmp;
        }else if (luat_tp_config->direction == LUAT_TP_ROTATE_180){
            coordinate_tmp = tp_data->y_coordinate;
            tp_data->x_coordinate = luat_tp_config->w - tp_data->x_coordinate;
            tp_data->y_coordinate = luat_tp_config->h - coordinate_tmp;
        }else if (luat_tp_config->direction == LUAT_TP_ROTATE_270){
            coordinate_tmp = tp_data->x_coordinate;
            tp_data->x_coordinate = luat_tp_config->h - tp_data->y_coordinate;
            tp_data->y_coordinate = coordinate_tmp;
        }

        // 抬起时，坐标为松开前的最后一次的坐标
        if (tp_data->event == TP_EVENT_TYPE_UP)
        {
            tp_data->x_coordinate = last_x;
            tp_data->y_coordinate = last_y;
        }
        else
        {
            last_x = tp_data->x_coordinate;
            last_y = tp_data->y_coordinate;
        }
        

        if (luat_tp_config->callback == NULL){
        	luat_tp_config->opts->read_done(luat_tp_config);
        }else{
            luat_tp_config->callback(luat_tp_config,tp_data);
        }
    }
}

int luat_tp_init(luat_tp_config_t* luat_tp_config){
    if (g_s_tp_task_handle == NULL){
        int ret = luat_rtos_task_create(&g_s_tp_task_handle, 4096, 10, "tp", luat_tp_task_entry, NULL, 32);
        if (ret){
        	g_s_tp_task_handle = NULL;
            LLOGE("tp task create failed!");
            return -1;
        }
    }
    luat_tp_config->task_handle = g_s_tp_task_handle;
    if (luat_tp_config->opts->init){
        return luat_tp_config->opts->init(luat_tp_config);
    }else{
        LLOGE("tp init error, no init function found!");
        return -1;
    }
}

int luat_tp_irq_enable(luat_tp_config_t* luat_tp_config, uint8_t enabled){
    return luat_gpio_irq_enable(luat_tp_config->pin_int, enabled, luat_tp_config->int_type, luat_tp_config);
}









