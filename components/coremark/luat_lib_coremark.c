#include "luat_base.h"

#include "printf.h"

#define LUAT_LOG_TAG "coremark"
#include "luat_log.h"

void ee_main(void);;

int ee_printf(const char *fmt, ...) {
    va_list va;
    va_start(va, fmt);
    char buff[512];
    vsnprintf_(buff, 512, fmt, va);
    va_end(va);
    LLOGD("%s", buff);
    return 0;
}

// uint32_t ee_iterations = 0;

static int l_coremark_run(lua_State *L) {
    // if (lua_isinteger(L, 1))
    //     ee_iterations = luaL_checkinteger(L, 1);
    // else
    //     ee_iterations = 10*10000;
    ee_main();
    return 0;
}

#include "rotable2.h"
static const rotable_Reg_t reg_coremark[] =
{
    { "run" ,         ROREG_FUNC(l_coremark_run)},
    { NULL,           {}}
};

LUAMOD_API int luaopen_coremark( lua_State *L ) {
    luat_newlib2(L, reg_coremark);
    return 1;
}
