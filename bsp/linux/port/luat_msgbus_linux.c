
#include "luat_msgbus.h"
#include "luat_malloc.h"

#define LUAT_LOG_TAG "msgbus"
#include "luat_log.h"

typedef struct sysp_msgbus {
    uint32_t vaild;
    rtos_msg_t msg;
    void* next;
}sysp_msgbus_t;

#define MSGBUS_SIZE (128)

static int msgbus_w_pos = 0;
static int msgbus_r_pos = 0;
static sysp_msgbus_t *msg_head;

void luat_msgbus_init(void) {
    msg_head = luat_heap_malloc(sizeof(sysp_msgbus_t));
    msg_head->vaild = 0;
}
uint32_t luat_msgbus_put(rtos_msg_t* msg, size_t timeout) {
    sysp_msgbus_t *tmp = luat_heap_malloc(sizeof(sysp_msgbus_t));
    if (tmp == NULL) {
        LLOGD("out of memory when malloc msgbus mss");
        return 1;
    }
    tmp->vaild = 0;

    //LLOGD("luat_msgbus_put GoGo\n");

    sysp_msgbus_t* t = msg_head;
    while (1) {
        if (t->vaild == 0) {
            //LLOGD("luat_msgbus_put t->vaild\n");
            memcpy(&t->msg, msg, sizeof(rtos_msg_t));
            t->vaild = 1;
            t->next = tmp;
            return 0;
        }
        else {
            t = t->next;
        }
    }
    return 0;
}

uint32_t luat_msgbus_get(rtos_msg_t* msg, size_t timeout) {
    //LLOGD("CALL luat_msgbus_get\n");
    sysp_msgbus_t* t = msg_head;
    if (t->vaild) {
        memcpy(msg, &t->msg, sizeof(rtos_msg_t));
        msg_head = t->next;
        luat_heap_free(t);
        return 0;
    }
    return 1;
}

uint32_t luat_msgbus_freesize(void) {
    return 1;
}
