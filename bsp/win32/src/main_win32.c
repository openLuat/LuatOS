
#include <stdio.h>

#include "luat_base.h"
#include "luat_malloc.h"
#include "luat_msgbus.h"

#include "bget.h"

#include "FreeRTOS.h"
#include "task.h"
#include "windows.h"

#define LUAT_HEAP_SIZE (1024*1024)
uint8_t luavm_heap[LUAT_HEAP_SIZE] = {0};

static void _luat_main(void* args) {
    luat_main();
}
#ifdef LUAT_USE_LVGL

#include "lvgl.h"
static int luat_lvg_handler(lua_State* L, void* ptr) {
    lv_task_handler();
    return 0;
}

static void _lvgl_handler(void* args) {
    rtos_msg_t msg = {0};
    msg.handler = luat_lvg_handler;
    while (1) {
        luat_msgbus_put(&msg, 0);
        vTaskDelay(5);
    };
}
#endif

BOOL WINAPI consoleHandler(DWORD signal) {
    if (signal == CTRL_C_EVENT) {
        printf("Ctrl-C handled\n"); // do cleanup
        exit(1);
    }
    return TRUE;
}

int win32_argc;
char** win32_argv;

// boot
int main(int argc, char** argv) {
    win32_argc = argc;
    win32_argv = argv;
    
    SetConsoleCtrlHandler(consoleHandler, TRUE);
    bpool(luavm_heap, LUAT_HEAP_SIZE);
#ifdef LUAT_USE_LVGL
    lv_init();
    xTaskCreate( _lvgl_handler, "lvgl", 1024*2, NULL, 21, NULL );
#endif

    xTaskCreate( _luat_main, "luatos", 1024*16, NULL, 21, NULL );
    vTaskStartScheduler();
    return 0;
}
