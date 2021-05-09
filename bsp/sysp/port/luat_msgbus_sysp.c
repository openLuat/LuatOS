
#include "luat_msgbus.h"

#define LUAT_LOG_TAG "msgbus"
#include "luat_log.h"

typedef struct sysp_msgbus {
    int vaild;
    rtos_msg_t msg;
}sysp_msgbus_t;

#define MSGBUS_SIZE (128)

static int msgbus_w_pos = 0;
static int msgbus_r_pos = 0;
static sysp_msgbus_t msgs[MSGBUS_SIZE] = {0};

void luat_msgbus_init(void) {
    
}
uint32_t luat_msgbus_put(rtos_msg_t* msg, size_t timeout) {
    int overflow = msgs[msgbus_w_pos].vaild;
    if (overflow) {
        LLOGW("msgbus overflow!!!");
        msgbus_r_pos = msgbus_w_pos;
    }

    memcpy(&msgs[msgbus_w_pos].msg, msg, sizeof(msg));
    msgs[msgbus_w_pos].vaild = 0;
    if (msgbus_w_pos < (MSGBUS_SIZE - 1)) {
        msgbus_w_pos ++;
    }
    else {
        msgbus_w_pos = 0;
    }

    return 0;
}

uint32_t luat_msgbus_get(rtos_msg_t* msg, size_t timeout) {
    if (msgs[msgbus_r_pos].vaild) {
        memcpy(msg, &msgs[msgbus_r_pos].msg, sizeof(msg));
        if (msgbus_r_pos < (MSGBUS_SIZE - 1))
            msgbus_r_pos ++;
        else
            msgbus_r_pos = 0;
        return 0;
    }
    return 1; // 要不要除portTICK_RATE_MS呢?
}

uint32_t luat_msgbus_freesize(void) {
    return 1;
}
