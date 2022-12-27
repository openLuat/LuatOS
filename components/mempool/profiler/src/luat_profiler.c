#include "luat_base.h"
#include "luat_malloc.h"
#include "luat_profiler.h"

#define LUAT_LOG_TAG "profiler"
#include "luat_log.h"

static luat_profiler_ctx_t ctx;

void* luat_profiler_alloc(void *ud, void *ptr, size_t osize, size_t nsize) {
    // TODO 加调试信息的head, 这样才能记录实际malloc和realloc的大小
    void* dst = NULL;
    if (ctx.tag == 0) { // 停用状态, 原样返回
        return luat_heap_alloc(ud, ptr, osize, nsize);
    }
    LLOGD("ud %p ptr %p oszie %08X nsize %08X", ud, ptr, osize, nsize);
    if (ptr == NULL && nsize == 0) {
        LLOGD("free NULL");
        return NULL;
    }
    // 如果指针不为NULL, 目标大小为0, 那就是free
    else if (ptr != NULL && nsize == 0) {
        LLOGD("call free %p", ptr);
        ctx.counter_free ++;
        dst = luat_heap_alloc(ud, ptr, osize, nsize);
        LLOGD("done free %p", ptr);
        return dst;
    }
    // 如果指针为NULL, 目标大小不为0, 那就是malloc
    else if (ptr == NULL && nsize > 0) {
        ctx.counter_malloc ++;
        LLOGD("call malloc %08X type %08X", nsize, osize);
        dst = luat_heap_alloc(ud, ptr, osize, nsize);
        LLOGD("call malloc %08X type %08X %p", nsize, osize, dst);
        return dst;
    }
    // 最后剩下realloc
    else {
        ctx.counter_realloc ++;
        LLOGD("call realloc %08X osize %08X", nsize, osize);
        dst = luat_heap_alloc(ud, ptr, osize, nsize);
        LLOGD("call realloc %08X osize %08X %p", nsize, osize, dst);
        return dst;
    }
}

int luat_profiler_start(void) {
    size_t total; size_t used; size_t max_used;
    LLOGD("start profiler");
    memset(&ctx, 0, sizeof(luat_profiler_ctx_t));
    ctx.tag = 1;
    luat_meminfo_luavm(&total, &ctx.lua_heap_begin_used, &max_used);
    LLOGD("%s luavm %ld %ld %ld", "profiler start", total, ctx.lua_heap_begin_used, max_used);
    luat_meminfo_sys(&total, &ctx.sys_heap_begin_used, &max_used);
    LLOGD("%s sys   %ld %ld %ld", "profiler start", total, ctx.sys_heap_begin_used, max_used);
    return 0;
}

int luat_profiler_stop(void) {
    size_t total; size_t used; size_t max_used;
    LLOGD("stop profiler");
    ctx.tag = 0;
    luat_meminfo_luavm(&total, &ctx.lua_heap_end_used, &max_used);
    LLOGD("%s luavm %ld %ld %ld", "profiler stop", total, ctx.lua_heap_end_used, max_used);
    luat_meminfo_sys(&total, &ctx.sys_heap_end_used, &max_used);
    LLOGD("%s sys   %ld %ld %ld", "profiler stop", total, ctx.sys_heap_end_used, max_used);
    return 0;
}

void luat_profiler_print(void) {
    size_t total; size_t used; size_t max_used;
    LLOGD("============================================");
    // 输出调用次数
    LLOGD("counter malloc %08X free %08X realloc %08X", ctx.counter_malloc, ctx.counter_free, ctx.counter_realloc);
    // 输出前后内存大小
    LLOGD("heap used at start: lua %08X sys %08X", ctx.lua_heap_begin_used, ctx.sys_heap_begin_used);
    LLOGD("heap used at stop : lua %08X sys %08X", ctx.lua_heap_end_used, ctx.sys_heap_end_used);
    LLOGD("============================================");
}
