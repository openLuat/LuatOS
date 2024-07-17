/*
@module  profiler
@summary 内存分析与性能分析
@date    2020.03.30
@author  wendal
@demo    profiler
@tag LUAT_USE_PROFILER
@usage
-- 当前已完成的功能:
-- 1. 内存分配统计 profiler.mem_stat()
*/

#include "luat_base.h"
#include "luat_mem.h"
#include "luat_mem.h"
#include "luat_timer.h"
#include "luat_profiler.h"

#define LUAT_LOG_TAG "PRO"
#include "luat_log.h"

static inline void toHex(const char* src, size_t len, char *dst) {
    size_t i;
    for (i = 0; i < len; ++i) {
        sprintf(&dst[i*2], "%02X", src[i]);
    }
    dst[len*2] = 0;
}


#include "lgc.h"
int l_profiler_mem_stat(lua_State *L) {
    int counter = 0;
    GCObject *gc = L->l_G->allgc;
    uint32_t type_couter[32] = {0};
    uint32_t type_heap[32] = {0};
    TString *ts;
    lu_byte rtt;
    char tmpbuff[1024];
    while (gc != NULL) {
        counter ++;
        // LLOGD("GCObject %p 类型 %d", gc, gc->tt);
        rtt = gc->tt & 0xF;
        type_couter[rtt] ++;
        // 打印一下内容
        switch (rtt)
        {
        case LUA_TNIL:
            // LLOGD("空类型?? 不太可能有");
            break;
        case LUA_TLIGHTUSERDATA:
            // LLOGD("lightuserdata %p", gc);
            type_heap[rtt] += sizeof(void*) + sizeof(Value);
            break;
        case LUA_TNUMBER:
            // LLOGD("数值 %p", gc);
            type_heap[rtt] += sizeof(lua_Number) + sizeof(Value);
            break;
        case LUA_TSTRING:
            ts = gco2ts(gc);
            type_heap[rtt] += (gc->tt == LUA_TSHRSTR ? ts->shrlen : ts->u.lnglen) + sizeof(UTString) + 1;
            if (gc->tt == LUA_TSHRSTR) {
                LLOGD("短字符串 %08X %d %d %d %s", ts->hash, ts->marked, ts->extra, ts->shrlen, getstr(ts));
                toHex(getstr(ts), ts->shrlen, tmpbuff);
                LLOGD("{.str={.tt = LUA_TSHRSTR, .marked = 4, .extra = %d, .shrlen = %d, .hash = 0x%08X}, .data=\"%s\"},",
                    ts->extra, ts->shrlen, ts->hash, tmpbuff
                );
            }
            break;
        case LUA_TTABLE:
            type_heap[rtt] += gco2t(gc)->sizearray * sizeof(TValue) + sizeof(Value);
            break;
        case LUA_TUSERDATA:
            // LLOGD("userdata %p", gc);
            type_heap[rtt] += gco2u(gc)->len + sizeof(Value);
            break;
        default:
            break;
        }
        gc = gc->next;
    }
    LLOGD("allgc对象计数 %d seek %08X", counter, L->l_G->seed);

    // counter = 0;
    gc = L->l_G->fixedgc;
    while (gc != NULL) {
        counter ++;
        rtt = gc->tt & 0xF;
        switch (rtt)
        {
        case LUA_TSTRING:
            ts = gco2ts(gc);
            // LLOGD("不是一样的吗? %p %p", ts, gc);
            type_heap[rtt] += (gc->tt == LUA_TSHRSTR ? ts->shrlen : ts->u.lnglen) + sizeof(UTString);
            // if (gc->tt == LUA_TSHRSTR)
            //     LLOGD("短字符串 %08X %d %d %d %s", ts->hash, ts->marked, ts->extra, ts->shrlen, getstr(ts));
            break;
        }
        gc = gc->next;
    }
    // LLOGD("fixedgc对象计数 %d", counter);
    for (size_t i = 0; i < 32; i++)
    {
        if (type_couter[i]) {
            LLOGD("类型 %d 计数 %d", i, type_couter[i]);
        }
    }
    for (size_t i = 0; i < 32; i++)
    {
        if (type_heap[i]) {
            LLOGD("类型 %d 内存 %d", i, type_heap[i]);
        }
    }
    
    return 0;
}

#include "rotable2.h"
static const rotable_Reg_t reg_profiler[] =
{
    { "mem_stat",          ROREG_FUNC(l_profiler_mem_stat)},
	{ NULL,            ROREG_INT(0)}
};

LUAMOD_API int luaopen_profiler( lua_State *L ) {
    luat_newlib2(L, reg_profiler);
    return 1;
}
