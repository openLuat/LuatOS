#include "luat_base.h"
#include "luat_pgfs.h"

#ifdef LUAT_USE_UTEST
extern int luat_pgfs_utest(lua_State* L, const char* case_name);

static int l_pgfs_utest(lua_State* L) {
    const char* case_name = luaL_optstring(L, 1, "c_layer_selftests");
    lua_pushboolean(L, luat_pgfs_utest(L, case_name) == 0);
    return 1;
}
#endif

#include "rotable2.h"

static const rotable_Reg_t reg_pgfs[] = {
#ifdef LUAT_USE_UTEST
    { "utest", ROREG_FUNC(l_pgfs_utest) },
#endif
    { NULL, ROREG_INT(0) }
};

LUAMOD_API int luaopen_pgfs(lua_State* L) {
    luat_newlib2(L, reg_pgfs);
    return 1;
}
