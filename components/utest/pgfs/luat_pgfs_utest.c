#include "luat_base.h"
#include "luat_pgfs.h"

int luat_pgfs_utest(lua_State* L, const char* case_name) {
    (void)L;
    return pgfs_run_c_layer_case(case_name);
}
