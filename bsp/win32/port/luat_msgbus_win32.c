/**
 * @file luat_msgbus_win32.c
 * @author wendal (wendal1985@gamil.com)
 * @brief 基于win32的ThreadMessage机制实现的msgbus
 * @version 0.1
 * @date 2022-03-27
 * 
 * @copyright Copyright (c) 2022 OpenLuat & AirM2M
 * 
 */
#include "luat_base.h"
#include "luat_msgbus.h"
#include "luat_timer.h"
#include "luat_malloc.h"

#include "SDL.h"

#define LUAT_LOG_TAG "msgbus"
#include "luat_log.h"

void luat_msgbus_init(void) {

}
uint32_t luat_msgbus_put(rtos_msg_t* msg, size_t timeout) {
    // LLOGD("luat_msgbus_put  msg handler:%08X arg1:%d arg2:%d", msg->handler,msg->arg1,msg->arg2);
    SDL_Event event;
    event.type = SDL_USEREVENT;
    event.user.data1 = luat_heap_malloc(sizeof(rtos_msg_t));
    memcpy(event.user.data1, msg, sizeof(rtos_msg_t));
    SDL_PushEvent(&event);
    SDL_PumpEvents();
    return 0;
}


uint32_t luat_msgbus_get(rtos_msg_t* rtmsg, size_t timeout) {
    SDL_Event event;
    if (SDL_WaitEventTimeout(&event,timeout) != 1){
        exit(0);
        return -1;
    }
    memcpy(rtmsg, event.user.data1, sizeof(rtos_msg_t));
    // LLOGD("luat_msgbus_get  tmp handler:%08X arg1:%d arg2:%d", rtmsg->handler,rtmsg->arg1,rtmsg->arg2);
    luat_heap_free(event.user.data1);
    return 0;
}

uint32_t luat_msgbus_freesize(void) {
    return 1;
}
