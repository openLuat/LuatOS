#include "luat_base.h"
#include "luat_msgbus.h"

#define LUAT_LOG_TAG "luat.msgbus"
#include "luat_log.h"

#include <pthread.h>
#include <errno.h>
#include <unistd.h>


static pthread_cond_t msgbus_cnd;
static pthread_mutex_t msgbus_mutex;

static int msgbus_pos = 0;
static int msgbus_last = 0;
static rtos_msg_t msgs[256] = {0};

// 定义接口方法
void luat_msgbus_init(void) {
    pthread_mutex_init(&msgbus_mutex, NULL);
    pthread_cond_init(&msgbus_cnd, NULL);
}

uint32_t luat_msgbus_put(rtos_msg_t* msg, size_t timeout) {

    pthread_mutex_lock(&msgbus_mutex);

    if (msg[msgbus_last].handler != NULL) {
        LLOGE("over flow!!!");
        return 1;
    } else {
        memcpy(&(msg[msgbus_last]), msg, sizeof(rtos_msg_t));
        if (msgbus_last == 255) {
            msgbus_last = 0;
        }
        else {
            msgbus_last ++;
        }
        pthread_mutex_unlock(&msgbus_mutex);
        pthread_cond_broadcast(&msgbus_cnd);
        return 0;
    }
}


uint32_t luat_msgbus_get(rtos_msg_t* msg, size_t timeout) {
    pthread_cond_wait(&msgbus_cnd, &msgbus_mutex);

    pthread_mutex_lock(&msgbus_mutex);
    if (msgs[msgbus_pos].handler) {
        memcpy(msg, &(msgs[msgbus_pos]), sizeof(rtos_msg_t));
        msgs[msgbus_pos].handler = NULL;
    }
    else {
        msg->handler = NULL;
    }
    if (msgbus_pos == 255) {
        msgbus_pos = 0;
    }
    else {
        msgbus_pos ++;
    }
    pthread_mutex_unlock(&msgbus_mutex);

    return msg->handler == NULL ? 1 : 0;
}

uint32_t luat_msgbus_freesize(void) {
    return 1;
}
