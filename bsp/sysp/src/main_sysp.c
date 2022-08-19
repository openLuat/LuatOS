
#ifdef __EMSCRIPTEN__
#include <emscripten.h>
#include <emscripten/html5.h>
#endif

#include <stdio.h>

#include "luat_base.h"
#include "luat_malloc.h"
#include "luat_timer.h"
#include "bget.h"
#include "luat_fs.h"

#define LUAT_LOG_TAG "main"
#include "luat_log.h"

#ifdef LUAT_USE_LVGL
#include "lvgl.h"
#endif

int luat_sysp_init(void);
int luat_sysp_loop(void);

#define LUAT_HEAP_SIZE (256*1024)
uint8_t luavm_heap[LUAT_HEAP_SIZE] = {0};

void luat_timer_check(void);

void luat_custom_init(lua_State *L) {
    // sys.lua的run函数有个钩子, 如果存在SYSP, 就不走真正的sys.run了
    lua_pushboolean(L, 1);
    lua_setglobal(L, "SYSP");
    // 提前加载sys.lua,这样用户脚本即使写 local sys = require "sys" 也没问题了
    luaL_loadstring(L, "_G.sys = require(\"sys\")");
    lua_pcall(L, 0, 0, 0);
}

// 被定时调用的方法
#ifdef __EMSCRIPTEN__

static uint32_t sysp_state = 0;
void emscripten_request_animation_frame_loop(EM_BOOL (*cb)(double time, void *userData), void *userData);
EM_BOOL luat_wasm_check(double time, void* userData) {
    // LLOGD("sysp_state %d", sysp_state);
    if (sysp_state == 0)
        return 1;
    //LLOGD("CALL luat_wasm_check");
#ifdef LUAT_USE_LVGL
    lv_task_handler();
#endif
    luat_timer_check(); // 遍历定时器,插入消息
    int ret = luat_sysp_loop(); // 取消息, 执行消息, 执行lua代码
    if (ret == 0) {
        return 1;
    }
    LLOGE("end of world!!! exit!!");
    sysp_state = 0;
    return 0;
}
#endif

#ifdef __EMSCRIPTEN__
int EMSCRIPTEN_KEEPALIVE luat_sysp_start(void) {
    luat_sysp_init();
    sysp_state = 1;
    return 0;
}


int EMSCRIPTEN_KEEPALIVE luat_fs_append_onefile(const char* path, const char* data, size_t len) {
    LLOGD("add file %s %p %d", path, data, len);
	if (len == 0)
		len = strlen(data);
    char dst[256];
    sprintf(dst, "/luadb%s", path);
    LLOGD("file to /luadb%s size %d", path, len);
	FILE* fd = fopen(dst, "w");
	if (fd) {
		fwrite(data, len, 1, fd);
		fflush(fd);
		fclose(fd);
	}
    return 0;
}

int luat_str_base64_decode( unsigned char *dst, size_t dlen, size_t *olen,
                   const unsigned char *src, size_t slen );
int EMSCRIPTEN_KEEPALIVE luat_fs_append_base64(const char* path, const char* data) {
    size_t len = strlen(data);
	if (len == 0)
		len = strlen(data);
    char dst[256] = {0};
    unsigned char *buff = luat_heap_malloc(len);
    if (buff == NULL) {
        LLOGD("out of memory when malloc onefile");
        return 0;
    }
    size_t olen = 0;
    luat_str_base64_decode(buff, len, &olen, data, len);
    sprintf(dst, "/luadb%s", path);
    LLOGD("file to /luadb%s size %d", path, olen);
	FILE* fd = fopen(dst, "w");
	if (fd) {
		fwrite(buff, olen, 1, fd);
		fflush(fd);
		fclose(fd);
	}
    return 0;
}
#endif

int main(int argc, char** argv) {
    //LLOGI("sysp main start");
    bpool(luavm_heap, LUAT_HEAP_SIZE);
    luat_fs_init();
#ifdef LUAT_USE_LVGL
    lv_init();
#endif
#ifdef __EMSCRIPTEN__
    LLOGI("sysp main __EMSCRIPTEN__");
    emscripten_request_animation_frame_loop(luat_wasm_check, 0);
#else
    //LLOGI("sysp main normal");
    luat_sysp_init();
    while (1) {
        luat_timer_mdelay(5);
        luat_sysp_loop();
    }
#endif
    //LLOGI("sysp main exit");
    return 0;
}

