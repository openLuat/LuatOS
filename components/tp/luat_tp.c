#include "luat_base.h"
#include "luat_tp.h"
#include "luat_mem.h"
#include "luat_gpio.h"

#define LUAT_LOG_TAG "tp"
#include "luat_log.h"


luat_rtos_task_handle tp_task_handle = NULL;

void luat_tp_task_entry(void* param){
    uint32_t message_id = 0;
    luat_tp_config_t *luat_tp_config = NULL;
    while (1){
        luat_rtos_message_recv(tp_task_handle, &message_id, &luat_tp_config, LUAT_WAIT_FOREVER);
        luat_tp_data_t* tp_data = luat_tp_config->tp_data;
        uint8_t touch_num = luat_tp_config->opts->read(luat_tp_config,tp_data);
        if (touch_num){
            for (uint8_t i=0; i<LUAT_TP_TOUCH_MAX; i++){
                if ((TP_EVENT_TYPE_DOWN == tp_data[i].event) || (TP_EVENT_TYPE_UP == tp_data[i].event) || (TP_EVENT_TYPE_MOVE == tp_data[i].event)){
                //     LLOGD("event=%d, track_id=%d, x=%d, y=%d, s=%d, timestamp=%u.\r\n", 
                //                 tp_data[i].event,
                //                 tp_data[i].track_id,
                //                 tp_data[i].x_coordinate,
                //                 tp_data[i].y_coordinate,
                //                 tp_data[i].width,
                //                 tp_data[i].timestamp);
                    if (luat_tp_config->callback){
                        luat_tp_config->callback(luat_tp_config,&tp_data[i]);
                    }
                }
            }
        }
        luat_gpio_irq_enable(luat_tp_config->pin_int, 1);
    }
}

int luat_tp_init(luat_tp_config_t* luat_tp_config){
    if (tp_task_handle == 0){
        luat_rtos_task_create(&tp_task_handle, 4096, 50, "tp", luat_tp_task_entry, NULL, 10);
    }
    tp_config_gt911.init(luat_tp_config);


    return 0;
}











