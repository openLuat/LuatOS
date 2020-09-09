
#include "lua.h"
#include "lauxlib.h"

typedef struct luat_memp_type
{
    int type;
    size_t obj_total;
    size_t mem_total;
    size_t mem_max; // 最大内存
    size_t mem_min; // 最小内存
    size_t mem_count[10]; // 内存分布, 在最大值和最小值之间的区域, 等分为10份
}luat_memp_type_t;

typedef struct luat_memp
{
    size_t version;
    size_t luat_memp_type_t[LUA_NUMTAGS]; // 每种类型的统计数量
}luat_memp_t;


luat_memp_t* luat_memp_check(lua_State *L);
int luat_memp_dump(lua_State *L);
