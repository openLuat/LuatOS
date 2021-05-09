
#ifdef __EMCC
#include <emscripten.h>
#include <emscripten/html5.h>
#endif

#include <stdio.h>

#include "luat_base.h"
#include "luat_malloc.h"
#include "luat_timer.h"
#include "bget.h"

int luat_sysp_init(void);
int luat_sysp_loop(void);

#define LUAT_HEAP_SIZE (1024*1024)
uint8_t luavm_heap[LUAT_HEAP_SIZE] = {0};

int win32_argc;
char** win32_argv;

// 务必先看看文档 https://emscripten.org/docs/porting/guidelines/api_limitations.html

// 未完工的, luat_timer_sysp.c 里面获取当前毫秒数的API未实现!!!

void luat_timer_check(void);

// 被定时调用的方法
uint8_t luat_wasm_check(double time, void* userData) {
    luat_timer_check(); // 遍历定时器,插入消息
    int ret = luat_sysp_loop(); // 取消息, 执行消息, 执行lua代码
    if (ret == 0) {
        return 0;
    }
    return 1;
}


// 下面的方法只是演示在wasm中的类似调用逻辑
int main(int argc, char** argv) {
    //win32_argc = argc;
    //win32_argv = argv;
    
    bpool(luavm_heap, LUAT_HEAP_SIZE);
    luat_sysp_init();
#ifdef __EMSCRIPTEN__
    emscripten_request_animation_frame_loop(luat_wasm_check, 0);
#else
    while (1) {
        luat_timer_mdelay(5);
        luat_sysp_loop();
    }
#endif
    
    return 0;
}
