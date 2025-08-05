

#include "luat_base.h"
#include "luat_fs.h"

#define LUAT_LOG_TAG "fs"
#include "luat_log.h"

LUAMOD_API int luaopen_fs( lua_State *L ) {
    lua_getglobal(L, "io");
    if (lua_isuserdata(L, -1))
        return 1;
    luaopen_io(L);
    return 1;
}
