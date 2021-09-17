
#include <stdio.h>

#include "luat_base.h"
#include "luat_malloc.h"
#include "luat_msgbus.h"

#include "bget.h"

#include "FreeRTOS.h"
#include "task.h"
#include "windows.h"
#include <unistd.h>

#define LUAT_HEAP_SIZE (1024*1024)
uint8_t luavm_heap[LUAT_HEAP_SIZE] = {0};

void luat_log_init_win32(void);

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

#ifdef LUAT_USE_LWIP
int lwip_init_main(void);
static void _lwip_init(void* arg) {
    lwip_init_main();
}
#endif

BOOL WINAPI consoleHandler(DWORD signal) {
    if (signal == CTRL_C_EVENT) {
        printf("Ctrl-C handled\n"); // do cleanup
        exit(1);
    }
    return TRUE;
}

int cmdline_argc;
char** cmdline_argv;

// boot
int main(int argc, char** argv) {
    cmdline_argc = argc;
    cmdline_argv = argv;
    if (cmdline_argc > 1) {
        size_t len = strlen(cmdline_argv[1]);
        if (cmdline_argv[1][0] != '-') {
            if (cmdline_argv[1][len - 1] == '/' || cmdline_argv[1][len - 1] == '\\') {
                printf("chdir %s %d\n", cmdline_argv[1], chdir(cmdline_argv[1]));
                cmdline_argc = 1;
            }
        }
    }

    luat_log_init_win32();

    SetConsoleCtrlHandler(consoleHandler, TRUE);
    bpool(luavm_heap, LUAT_HEAP_SIZE);
#ifdef LUAT_USE_LVGL
    lv_init();
    xTaskCreate( _lvgl_handler, "lvgl", 1024*2, NULL, 23, NULL );
#endif

#ifdef LUAT_USE_LWIP
    //xTaskCreate( _lwip_init, "lwip", 1024*2, NULL, 22, NULL );
#endif

    xTaskCreate( _luat_main, "luatos", 1024*16, NULL, 21, NULL );
    vTaskStartScheduler();
    return 0;
}
