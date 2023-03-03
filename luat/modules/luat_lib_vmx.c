#include "luat_base.h"
#include "luat_msgbus.h"
#include "luat_irq.h"
#include "luat_bget.h"
#include "lauxlib.h"

#ifndef LUAT_VMX_COUNT
#define LUAT_VMX_COUNT 4
#endif

#define LUAT_LOG_TAG "vms"
#include "luat_log.h"

typedef struct luat_vmx {
    lua_State* L;
    char* buff;
    luat_bget_t bg;
    int lua_ref_id;
}luat_vmx_t;

static luat_vmx_t vms[LUAT_VMX_COUNT];

static void* vms_alloc(void* ud, void *ptr, unsigned int osize, unsigned int nsize) {
    if (ud == NULL)
        return NULL;
    if (nsize)
    {
    	void* ptmp = luat_bgetr((luat_bget_t*)ud, ptr, nsize);
    	if(ptmp == NULL && osize >= nsize)
    	{
    		return ptr;
    	}
        return ptmp;
    }
    luat_brel((luat_bget_t*)ud, ptr);
    return NULL;
}

static const luaL_Reg loadedlibs[] = {
  {"_G", luaopen_base}, // _G
  //{LUA_LOADLIBNAME, luaopen_package}, // require
  {LUA_TABLIBNAME, luaopen_table},    // table库,操作table类型的数据结构
  {LUA_IOLIBNAME, luaopen_io},        // io库,操作文件
  {LUA_OSLIBNAME, luaopen_os},        // os库,已精简
  {LUA_STRLIBNAME, luaopen_string},   // string库,字符串操作
  {LUA_MATHLIBNAME, luaopen_math},    // math 数值计算
//  {LUA_UTF8LIBNAME, luaopen_utf8},
  {LUA_DBLIBNAME, luaopen_debug},     // debug库,已精简

  {"rtos", luaopen_rtos},             // rtos底层库, 核心功能是队列和定时器
  {"log", luaopen_log},               // 日志库
  {"timer", luaopen_timer},           // 延时库
  {"pack", luaopen_pack},             // pack.pack/pack.unpack
  {"json", luaopen_cjson},             // json
  {"zbuff", luaopen_zbuff},            // 
  {"crypto", luaopen_crypto},
#ifdef LUAT_USE_GPIO
  {"gpio",   luaopen_gpio},
#endif
#ifdef LUAT_USE_I2C
  {"i2c",   luaopen_i2c},
#endif
#ifdef LUAT_USE_SPI
  {"spi",   luaopen_spi},
#endif
#ifdef LUAT_USE_PWM
  {"pwm",   luaopen_pwm},
#endif
#ifdef LUAT_USE_ADC
  {"adc",   luaopen_adc},
#endif
#ifdef LUAT_USE_GMSSL
  {"gmssl",   luaopen_gmssl},
#endif
  {NULL, NULL}
};

// 创建虚拟机
static int l_vmx_create(lua_State *L) {
    // 寻找空位
    int index = -1;
    for (size_t i = 0; i < LUAT_VMX_COUNT; i++)
    {
        if (vms[i].buff == NULL) {
            index = i;
            break;
        }
    }
    if (index == -1) {
        LLOGW("too many Lua VMs");
        return 0;
    }

    // 分配内存
    void* buff = lua_newuserdata(L, 32*1024);
    if (buff == NULL) {
        LLOGD("out of memory");
        return 0;
    }

    int top = lua_gettop(L);

    vms[index].buff = buff;
    luat_bget_init(&vms[index].bg);
    luat_bpool(&vms[index].bg, buff, 32*1024);

    // 创建lua_State
    vms[index].L = lua_newstate(vms_alloc, &vms[index].bg);

    // 加入必要的库
    const luaL_Reg *lib;
    for (lib = loadedlibs; lib->func; lib++) {
        luaL_requiref(vms[index].L, lib->name, lib->func, 1);
        lua_pop(vms[index].L, 1);  /* remove lib */
    }

    // 返回结果
    if (lua_gettop(L) != top)
        lua_settop(L, top);
    vms[index].lua_ref_id = luaL_ref(L, LUA_REGISTRYINDEX);
    lua_pushinteger(L, index);
    return 1;
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
        size_t str_len = 0;
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
                lua_settop(vms[vm_id].L, 0);
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

#include "rotable2.h"
static const rotable_Reg_t reg_vmx[] =
{
    { "create" ,         ROREG_FUNC(l_vmx_create)},
    { "bind" ,           ROREG_FUNC(l_vmx_bind)},
    { "exec",            ROREG_FUNC(l_vmx_exec)},
    { "close" ,          ROREG_FUNC(l_vmx_close)},
    { "count" ,          ROREG_FUNC(l_vmx_count)},
    { NULL,              ROREG_INT(0)}
};

LUAMOD_API int luaopen_vmx( lua_State *L ) {
    luat_newlib2(L, reg_vmx);
    return 1;
}
