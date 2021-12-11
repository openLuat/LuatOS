
#include "luat_base.h"
#include "luat_malloc.h"
#include "luat_msgbus.h"
#include "luat_timer.h"
#include "luat_gpio.h"

#define LUAT_LOG_TAG "msh"
#include "luat_log.h"

#include "luat_dbg.h"

#include "rtthread.h"
#include <rtdevice.h>

#ifdef FINSH_USING_MSH

extern lua_State *L;

static int msgbus_handler(lua_State *L, void* ptr) {
    int re = luaL_dostring(L, (const char*)ptr);
    if (re) {
        LLOGE("luaL_dostring  return re != 0\n");
        LLOGE(lua_tostring(L, -1));
    }
    luat_heap_free(ptr);
    return 0;
}

static void loadstr(int argc, char**argv) {
    if (argc < 2)
        return;
    char* buff = luat_heap_malloc(strlen(argv[1])+1);
    strcpy(buff, argv[1]);
    rtos_msg_t msg;
    msg.handler = msgbus_handler;
    msg.ptr = buff;
    luat_msgbus_put(&msg, 0);
    
};

#include "luat_dbg.h"

static void dbg(int argc, char**argv) {
    if (argc < 2)
        return;
    if (!strcmp("start", argv[1])) {
        luat_dbg_set_hook_state(2);
    }
    else if (!strcmp("next", argv[1]) || !strcmp("step", argv[1])) {
        luat_dbg_set_hook_state(4);
    }
    else if (!strcmp("stepin", argv[1]) || !strcmp("stepIn", argv[1])) {
        luat_dbg_set_hook_state(5);
    }
    else if (!strcmp("stepout", argv[1]) || !strcmp("stepOut", argv[1])) {
        luat_dbg_set_hook_state(6);
    }
    else if (!strcmp("continue", argv[1])) {
        luat_dbg_set_hook_state(2);
    }
    else if (!strcmp("bt", argv[1])) {
        if (argc > 2) {
            luat_dbg_set_runcb(luat_dbg_backtrace, (void*)atoi(argv[2]));
        }
        else {
            luat_dbg_set_runcb(luat_dbg_backtrace, (void*)-1);
        }
    }
    else if (!strcmp("vars", argv[1])) {
        if (argc > 2) {
            luat_dbg_set_runcb(luat_dbg_vars, (void*)atoi(argv[2]));
        }
        else {
            luat_dbg_set_runcb(luat_dbg_vars, (void*)0);
        }
    }
    else if (!strcmp("break", argv[1])) {
        if (!strcmp("add", argv[2]) && argc == 5) {
            luat_dbg_breakpoint_add(argv[3], atoi(argv[4]));
        }
        else if (!strcmp("del", argv[2]) && argc == 4) {
            luat_dbg_breakpoint_del(atoi(argv[3]));
        }
        else if (!strcmp("clr", argv[2]) || !strcmp("clear", argv[2])) {
            if (argc > 3)
                luat_dbg_breakpoint_clear(argv[3]);
            else
                luat_dbg_breakpoint_clear(NULL);
        }
    }
};

MSH_CMD_EXPORT(loadstr , run lua code);
MSH_CMD_EXPORT(dbg , luat debugger);

#endif

