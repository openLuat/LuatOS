
#include <stdio.h>

#include "luat_base.h"
#include "luat_malloc.h"
#include "luat_msgbus.h"
#include "luat_fs.h"

#include "bget.h"

#include "windows.h"
#include <io.h>

#define LUAT_LOG_TAG "main"
#include "luat_log.h"

#define LUAT_HEAP_SIZE (1024*1024)
uint8_t luavm_heap[LUAT_HEAP_SIZE] = {0};

int cmdline_argc;
char** cmdline_argv;

int lua_main (int argc, char **argv);

void luat_log_init_win32(void);
void luat_uart_initial_win32(void);

static void _luat_main(void* args) {
    //luat_main();
    luat_fs_init();
    lua_main(cmdline_argc, cmdline_argv);
    exit(0);
}

#ifdef LUAT_USE_LVGL

#include "lvgl.h"
static int luat_lvg_handler(lua_State* L, void* ptr) {
    //LLOGD("CALL lv_task_handler");
    // lv_tick_inc(25);
    lv_task_handler();
    return 0;
}

static void CALLBACK _lvgl_handler(HWND hwnd,       
    UINT message,     
    UINT idTimer,     
    DWORD dwTime) {
    rtos_msg_t msg = {0};
    msg.handler = luat_lvg_handler;
    luat_msgbus_put(&msg, 0);
}
#endif

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
    luat_uart_initial_win32();

    SetConsoleCtrlHandler(consoleHandler, TRUE);
    bpool(luavm_heap, LUAT_HEAP_SIZE);
#ifdef LUAT_USE_LVGL
    lv_init();
    SetTimer(NULL, 0, 25, _lvgl_handler);
#endif

    _luat_main(NULL);
    return 0;
}
