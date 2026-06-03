#include "luat_base.h"
#include "little_flash_ftl.h"

int luat_little_flash_utest(lua_State *L, const char *case_name) {
    (void)L;
    (void)case_name;
    /* little_flash FTL C-level unit tests have been removed (FTL moved to
     * pgfs). Return -1 to signal "no such test" — the Lua layer treats
     * this as a skip. */
    return -1;
}
