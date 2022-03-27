
#include <stdio.h>

#include "luat_base.h"
#include "luat_malloc.h"
#include "luat_msgbus.h"
#include "luat_fs.h"

#include "bget.h"

#define LUAT_LOG_TAG "main"
#include "luat_log.h"

// #include "FreeRTOS.h"
// #include "task.h"
#include "windows.h"
#include <unistd.h>
#include "luat_remotem.h"

#ifdef LUAT_USE_LVGL
#include "lvgl.h"
#endif

#define LUAT_HEAP_SIZE (1024*1024)
uint8_t luavm_heap[LUAT_HEAP_SIZE] = {0};

int cmdline_argc;
char** cmdline_argv;

int lua_main (int argc, char **argv);

void luat_log_init_win32(void);

static void _luat_main(void* args) {
    //luat_main();
    luat_fs_init();
    lua_main(cmdline_argc, cmdline_argv);
    exit(0);
}


BOOL WINAPI consoleHandler(DWORD signal) {
    if (signal == CTRL_C_EVENT) {
        printf("Ctrl-C handled\n"); // do cleanup
        exit(1);
    }
    return TRUE;
}

// boot
int main(int argc, char** argv) {
    cmdline_argc = argc;
    cmdline_argv = argv;

    luat_remotem_init(argc, argv);

    SetConsoleCtrlHandler(consoleHandler, TRUE);
    bpool(luavm_heap, LUAT_HEAP_SIZE);

    luat_msgbus_init();

#ifdef LUAT_USE_LVGL
    lv_init();
#endif

    extern int mqtt_main(void);
    mqtt_main();

    // xTaskCreate( _luat_main, "luatos", 1024*16, NULL, 21, NULL );
    // vTaskStartScheduler();
    luat_main();
    return 0;
}
