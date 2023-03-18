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
#include <stdbool.h>

#include "windows.h"
#include "windowsx.h"

#define LUAT_LOG_TAG "msgbus"
#include "luat_log.h"


static DWORD luat_main_thread_id;

void luat_msgbus_init(void) {
    luat_main_thread_id = GetCurrentThreadId();
    // LLOGD("main thread id %d", luat_main_thread_id);
}
uint32_t luat_msgbus_put(rtos_msg_t* msg, size_t timeout) {
    rtos_msg_t* tmp = luat_heap_malloc(sizeof(rtos_msg_t));
    memcpy(tmp, msg, sizeof(rtos_msg_t));
    PostThreadMessageA(luat_main_thread_id, WM_COMMAND, (WPARAM)tmp, 0);
    return 0;
}


uint32_t luat_msgbus_get(rtos_msg_t* rtmsg, size_t timeout) {
    MSG msg;
    rtos_msg_t* tmp;
    bool ret = FALSE;
    if ((ret = GetMessageA(&msg,NULL,0,0)) == 0) {
      exit(0);
      return 0;
    }
    
    
    int mouse_x, mouse_y;
    bool mouse_pressed;
    switch (msg.message)
    {
    case WM_COMMAND:
        tmp = (rtos_msg_t*)msg.wParam;
        if (tmp != NULL) {
            memcpy(rtmsg, tmp, sizeof(rtos_msg_t));
            luat_heap_free(tmp);
            return 0;
        }
        break;
    default:
        DispatchMessage(&msg);
        break;
    }
    return 1;
}

// uint32_t luat_msgbus_freesize(void) {
//     return 1;
// }
