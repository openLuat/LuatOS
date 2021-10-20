#include "luat_base.h"
#include "luat_msgbus.h"
#include "luat_irq.h"

#ifndef LUAT_VMX_COUNT
#define LUAT_VMX_COUNT 4
#endif

typedef struct luat_vmx {
    lua_State* L;
    char* buff;
}luat_vmx_t;

static luat_vmx_t vms[LUAT_VMX_COUNT];

// 创建虚拟机
static int l_vmx_create(lua_State *L) {
    // 寻找空位

    // 分配内存

    // 创建lua_State

    // 加入必要的库

    // 返回结果

    return 0;
}

// 将值在两个VM之间搬运
static int vm2vm_copy(int index, lua_State *Lsrc, lua_State *Ldst) {
    if (lua_isnil(Lsrc, index)) {
        lua_pushnil(Ldst);
    }
    else if (lua_isboolean(Lsrc, index)) {
        lua_pushboolean(Ldst, lua_toboolean(Lsrc, index));
    }
    else if (lua_isinteger(Lsrc, index)) {
        lua_pushinteger(Ldst, lua_tointeger(Lsrc, index));
    }
    else if (lua_isnumber(Lsrc, index)) {
        lua_pushnumber(Ldst, lua_tonumber(Lsrc, index));
    }
    else if (lua_isstring(Lsrc, index)) {
        int str_len = 0;
        const char* tmp = luaL_checklstring(Lsrc, index, &str_len);
        lua_pushlstring(Ldst, tmp, str_len);
    }
    else {
        return -1;
    }
    return 0;
}

// 在指定虚拟机内执行代码
static int l_vmx_exec(lua_State *L) {
    int vm_id = luaL_checkinteger(L, 1);
    size_t sz = 0;
    const char* buff = luaL_checklstring(L, 2, &sz);
    if (sz == 0) {
        lua_pushboolean(L, 0);
        lua_pushliteral(L, "emtry string");
        return 2;
    }
    if (vm_id < 0 || vm_id >= LUAT_VMX_COUNT || vms[vm_id].L == NULL) {
        lua_pushboolean(L, 0);
        lua_pushliteral(L, "invaild vm id");
        return 2;
    }
    lua_settop(vms[vm_id].L, 0);
    int ret = luaL_loadbuffer(vms[vm_id].L, buff, sz, "vmx");
    if (ret) {
        lua_pushboolean(L, 0);
        lua_pushstring(L, lua_tostring(L, -1));
        lua_pushinteger(L, ret);
        return 3;
    }
    int top = lua_gettop(L);
    if (top > 2) { // 推入参数,仅支持string/数值/bool
        for (size_t i = 2; i < top; i++)
        {
            if (!vm2vm_copy(i+1, L, vms[vm_id].L)) {
                lua_pushboolean(L, 0);
                lua_pushliteral(L, "only bool/number/string is accepted");
                lua_pushinteger(L, i+1);
                return 3;
            }
        }
    }
    ret = lua_pcall(vms[vm_id].L, top - 2, 1, 0);
    if (ret) {
        lua_pushboolean(L, 0);
        lua_pushstring(L, lua_tostring(vms[vm_id].L, -1));
        lua_pushinteger(L, ret);
        return 3;
    }
    else if (lua_gettop(vms[vm_id].L) > 0) {
        lua_pushboolean(L, 1);
        if (vm2vm_copy(1, vms[vm_id].L, L)) {
            return 2;
        }
        else {
            return 1;
        }
    }
    lua_pushboolean(L, 1);
    return 1;
}

static int l_vmx_bind(lua_State *L) {
    return 0;
}

static int l_vmx_close(lua_State *L) {
    return 0;
}

static int l_vmx_count(lua_State *L) {
    int count = 0;
    for (size_t i = 0; i < LUAT_VMX_COUNT; i++)
    {
        if (vms[i].L)
            count++;
    }
    lua_pushinteger(L, count);
    return 1;
}

#include "rotable.h"
static const rotable_Reg reg_vmx[] =
{
    { "create" ,         l_vmx_create, 0},
    { "bind" ,           l_vmx_bind, 0},
    { "close" ,          l_vmx_close, 0},
    { "count" ,          l_vmx_count, 0},
};

LUAMOD_API int luaopen_vmx( lua_State *L ) {
    luat_newlib(L, reg_vmx);
    return 1;
}
