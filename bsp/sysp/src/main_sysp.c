
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

#define LUAT_HEAP_SIZE (1024*1024)
uint8_t luavm_heap[LUAT_HEAP_SIZE] = {0};

typedef struct luat_fs_onefile
{
    char* ptr;
    uint32_t  size;
    uint32_t  offset;
}luat_fs_onefile_t;

void luat_timer_check(void);

// 被定时调用的方法
#ifdef __EMSCRIPTEN__

static uint32_t sysp_state = 0;
void emscripten_request_animation_frame_loop(EM_BOOL (*cb)(double time, void *userData), void *userData);
EM_BOOL luat_wasm_check(double time, void* userData) {
    if (sysp_state == 0)
        return 1;
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
	if (len == 0)
		len = strlen(data);
    char* tmp = luat_heap_malloc(len);
    if (tmp == NULL) {
        LLOGD("out of memory when add vfs-onefile");
        return -1;
    }
	luat_fs_onefile_t* fd = luat_heap_malloc(sizeof(luat_fs_onefile_t));
    if (fd == NULL) {
        LLOGD("out of memory when add vfs-onefile");
        return -1;
    }
    fd->ptr = tmp;
    memcpy(tmp, data, len);
    fd->size = len;
	luat_fs_conf_t conf = {
		.busname = (char*)fd,
		.type = "onefile",
		.filesystem = "onefile",
		.mount_point = path,
	};
	luat_fs_mount(&conf);
    return 0;
}
#endif

int main(int argc, char** argv) {
    bpool(luavm_heap, LUAT_HEAP_SIZE);
    luat_fs_init();
#ifdef LUAT_USE_LVGL
    lv_init();
#endif
#ifdef __EMSCRIPTEN__
    emscripten_request_animation_frame_loop(luat_wasm_check, 0);
#else
    luat_sysp_init();
    while (1) {
        luat_timer_mdelay(5);
        luat_sysp_loop();
    }
#endif
    return 0;
}

