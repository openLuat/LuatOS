
#include "luat_base.h"
#include "luat_malloc.h"
#include "luat_msgbus.h"
#include "luat_timer.h"
#include "luat_gpio.h"

#define LUAT_LOG_TAG "luat.msh"
#include "luat_log.h"

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

MSH_CMD_EXPORT(loadstr , run lua code);

#endif

