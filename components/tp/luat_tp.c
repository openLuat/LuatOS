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
            if (luat_tp_config->callback == NULL){
                luat_gpio_irq_enable(luat_tp_config->pin_int, 1);
            }else{
                luat_tp_config->callback(luat_tp_config,tp_data);
            }
        }else{
            luat_gpio_irq_enable(luat_tp_config->pin_int, 1);
        }
    }
}

int luat_tp_init(luat_tp_config_t* luat_tp_config){
    if (tp_task_handle == 0){
        luat_rtos_task_create(&tp_task_handle, 4096, 10, "tp", luat_tp_task_entry, NULL, 10);
    }
    if (luat_tp_config->opts->init){
        return luat_tp_config->opts->init(luat_tp_config);
    }else{
        LLOGE("tp init error, no init function found!");
        return -1;
    }
}











