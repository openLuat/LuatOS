
#include "luat_base.h"
#include "luat_malloc.h"
#include "luat_msgbus.h"
#include "luat_timer.h"
#include "luat_gpio.h"

#include "rtthread.h"
#include <rtdevice.h>

#ifdef FINSH_USING_MSH

static void loadstr(int argc, char**argv) {
    if (argc < 2)
        return;
    luaL_dostring(luat_get_state(), argv[1]);
};

MSH_CMD_EXPORT(loadstr , run lua code);

#endif

