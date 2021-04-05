
#include <stdio.h>

#include "luat_base.h"
#include "luat_malloc.h"

#include "bget.h"

#include "FreeRTOS.h"
#include "task.h"
#include "windows.h"

#define LUAT_HEAP_SIZE (1024*1024)
uint8_t luavm_heap[LUAT_HEAP_SIZE] = {0};

static void _luat_main(void* args) {
    luat_main();
}

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
    xTaskCreate( _luat_main, "luatos", 1024*16, NULL, 21, NULL );
    vTaskStartScheduler();
    return 0;
}
