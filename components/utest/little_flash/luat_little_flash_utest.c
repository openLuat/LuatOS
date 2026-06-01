#include "luat_base.h"
#include "little_flash_ftl.h"

int luat_little_flash_utest(lua_State *L, const char *case_name) {
    (void)L;
    return little_flash_ftl_utest_case(case_name);
}
