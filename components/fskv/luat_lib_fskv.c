
/*
@module  fskv
@summary kv数据库,掉电不丢数据
@version 1.0
@date    2022.12.29
@demo    fskv
@tag     LUAT_USE_FSKV
@usage
-- 本库的目标是替代fdb库
-- 1. 兼容fdb的函数
-- 2. 使用fdb的flash空间,启用时也会替代fdb库
fskv.init()
fskv.set("wendal", 1234)
log.info("fskv", "wendal", fskv.get("wendal"))

--[[ 
fskv与fdb的实现机制导致的差异

                    fskv          fdb
1. value长度        4096           255
2. key长度          63             64
3. 空间利用率(对比)  较低            较高
4. 读取速度         恒定           脏数据影响速度,非恒定
5. 写入数据         恒定           脏数据影响速度,非恒定
]]
*/

#include "luat_base.h"
#include "luat_msgbus.h"
#include "luat_malloc.h"

#include "luat_fskv.h"
#include "luat_sfd.h"

#ifndef LUAT_LOG_TAG
#define LUAT_LOG_TAG "fskv"
#include "luat_log.h"
#endif

#define LUAT_FSKV_MAX_SIZE (4096)

extern sfd_drv_t* sfd_onchip;
extern luat_sfd_lfs_t* sfd_lfs;

// static char fskv_read_buff[LUAT_FSKV_MAX_SIZE];

/**
初始化kv数据库
@api fskv.init()
@return boolean 成功返回true,否则返回false
@usage
if fskv.init() then
    log.info("fdb", "kv数据库初始化成功")
end

-- 关于清空fdb库
-- 下载工具是没有提供直接清除fdb数据的途径的, 但有办法解决
-- 写一个main.lua, 执行 fskv.kvdb_init 后 执行 fskv.clear() 即可全清fdb数据.
 */
static int l_fskvdb_init(lua_State *L) {
    if (sfd_lfs == NULL) {
        if (sfd_onchip == NULL) {
            luat_sfd_onchip_init();
        }
        if (sfd_onchip == NULL) {
            LLOGE("sfd-onchip init failed");
            return 0;
        }
        if (sfd_lfs == NULL) {
            luat_sfd_lfs_init(sfd_onchip);
        }
        if (sfd_lfs == NULL) {
            LLOGE("sfd-onchip lfs int failed");
            return 0;
        }
    }
    lua_pushboolean(L, 1);
    return 1;
}

/**
设置一对kv数据
@api fskv.set(key, value)
@string key的名称,必填,不能空字符串
@string 用户数据,必填,不能nil, 支持字符串/数值/table/布尔值, 数据长度最大4095字节
@return boolean 成功返回true,否则返回false
@usage
-- 设置数据, 字符串,数值,table,布尔值,均可
-- 但不可以是nil, function, userdata, task
log.info("fdb", fskv.set("wendal", "goodgoodstudy"))
log.info("fdb", fskv.set("upgrade", true))
log.info("fdb", fskv.set("timer", 1))
log.info("fdb", fskv.set("bigd", {name="wendal",age=123}))
 */
static int l_fskv_set(lua_State *L) {
    if (sfd_lfs == 0) {
        LLOGE("call fskv.init() first!!!");
        return 0;
    }
    size_t len;
    luaL_Buffer buff;
    luaL_buffinit(L, &buff);
    const char* key = luaL_checkstring(L, 1);
    //luaL_addchar(&buff, 0xA5);
    int type = lua_type(L, 2);
    switch (type)
    {
    case LUA_TBOOLEAN:
        luaL_addchar(&buff, LUA_TBOOLEAN);
        bool val = lua_toboolean(L, 2);
        luaL_addlstring(&buff, (const char*)&val, sizeof(val));
        break;
    case LUA_TNUMBER:
        if (lua_isinteger(L, 2)) {
            luaL_addchar(&buff, LUA_TINTEGER); // 自定义类型
            lua_Integer val = luaL_checkinteger(L, 2);
            luaL_addlstring(&buff, (const char*)&val, sizeof(val));
        }
        else {
            luaL_addchar(&buff, LUA_TNUMBER);
            lua_getglobal(L, "pack");
            if (lua_isnil(L, -1)) {
                LLOGW("float number need pack lib");
                lua_pushboolean(L, 0);
                return 1;
            }
            lua_getfield(L, -1, "pack");
            lua_pushstring(L, ">f");
            lua_pushvalue(L, 2);
            lua_call(L, 2, 1);
            if (lua_isstring(L, -1)) {
                const char* val = luaL_checklstring(L, -1, &len);
                luaL_addlstring(&buff, val, len);
            }
            else {
                LLOGW("kdb store number fail!!");
                lua_pushboolean(L, 0);
                return 1;
            }
        }
        break;
    case LUA_TSTRING:
    {
        luaL_addchar(&buff, LUA_TSTRING);
        const char* val = luaL_checklstring(L, 2, &len);
        luaL_addlstring(&buff, val, len);
        break;
    }
    case LUA_TTABLE:
    {
        lua_settop(L, 2);
        lua_getglobal(L, "json");
        if (lua_isnil(L, -1)) {
            LLOGW("miss json lib, not support table value");
            lua_pushboolean(L, 0);
            return 1;
        }
        lua_getfield(L, -1, "encode");
        if (lua_isfunction(L, -1)) {
            lua_pushvalue(L, 2);
            lua_call(L, 1, 1);
            if (lua_isstring(L, -1)) {
                luaL_addchar(&buff, LUA_TTABLE);
                const char* val = luaL_checklstring(L, -1, &len);
                luaL_addlstring(&buff, val, len);
            }
            else {
                LLOGW("json.encode(val) report error");
                lua_pushboolean(L, 0);
                return 1;
            }
        }
        else {
            LLOGW("miss json.encode, not support table value");
            lua_pushboolean(L, 0);
            return 1;
        }
        break;
    }
    default:
    {
        LLOGW("function/userdata/nil/thread isn't allow");
        lua_pushboolean(L, 0);
        return 1;
    }
    }
    if (buff.n > LUAT_FSKV_MAX_SIZE) {
        LLOGE("value too big %d max %d", buff.n, LUAT_FSKV_MAX_SIZE);
        lua_pushboolean(L, 0);
        return 1;
    }
    int ret = luat_fskv_set(key, buff.b, buff.n);
    lua_pushboolean(L, ret == buff.n ? 1 : 0);
    // lua_pushinteger(L, ret);
    return 1;
}

/**
根据key获取对应的数据
@api fskv.get(key, skey)
@string key的名称,必填,不能空字符串
@string 可选的次级key,仅当原始值为table时有效,相当于 fskv.get(key)[skey]
@return any 存在则返回数据,否则返回nil
@usage
if fskv.init() then
    log.info("fdb", fskv.get("wendal"))
end

-- 若需要"默认值", 对应非bool布尔值, 可以这样写
local v = fskv.get("wendal") or "123"
 */
static int l_fskv_get(lua_State *L) {
    if (sfd_lfs == NULL) {
        LLOGE("call fskv.init() first!!!");
        return 0;
    }
    // luaL_Buffer buff;
    const char* key = luaL_checkstring(L, 1);
    const char* skey = luaL_optstring(L, 2, "");
    // luaL_buffinitsize(L, &buff, 8192);
    char tmp[256] = {0};
    char *buff = NULL;
    char *rbuff = NULL;
    int size = luat_fskv_size(key, tmp);
    if (size < 2) {
        return 0; // 对应的KEY不存在
    }
    if (size >= 256) {
        rbuff = luat_heap_malloc(size);
        if (rbuff == NULL) {
            LLOGW("out of memory when malloc key-value buff");
            return 0;
        }
        size_t read_len = luat_fskv_get(key, rbuff, size);
        if (read_len != size) {
            luat_heap_free(rbuff);
            LLOGW("read key-value fail, ignore as not exist");
            return 0;
        }
        buff = rbuff;
    }
    else {
        buff = tmp;
    }

    lua_Integer intVal;
    // lua_Number *numVal;
    // LLOGD("KV value T=%02X", buff.b[0]);
    switch(buff[0]) {
    case LUA_TBOOLEAN:
        lua_pushboolean(L, buff[1]);
        break;
    case LUA_TNUMBER:
        lua_getglobal(L, "pack");
        lua_getfield(L, -1, "unpack");
        lua_pushlstring(L, (char*)(buff + 1), size - 1);
        lua_pushstring(L, ">f");
        lua_call(L, 2, 2);
        // _, val = pack.unpack(data, ">f")
        break;
    case LUA_TINTEGER:
    	//不能直接赋值，右边指针地址和左边的位宽不一致
    	memcpy(&intVal, &buff[1], sizeof(lua_Integer));
//        intVal = (lua_Integer*)(&buff[1]);
//        lua_pushinteger(L, *intVal);
        lua_pushinteger(L, intVal);
        break;
    case LUA_TSTRING:
        lua_pushlstring(L, (const char*)(buff + 1), size - 1);
        break;
    case LUA_TTABLE:
        lua_getglobal(L, "json");
        lua_getfield(L, -1, "decode");
        lua_pushlstring(L, (const char*)(buff + 1), size - 1);
        lua_call(L, 1, 1);
        if (strlen(skey) > 0 && lua_istable(L, -1)) {
            lua_getfield(L, -1, skey);
        }
        break;
    default :
        LLOGW("bad value prefix %02X", buff[0]);
        lua_pushnil(L);
        break;
    }
    if (rbuff)
        luat_heap_free(rbuff);
    return 1;
}

/**
根据key删除数据
@api fskv.del(key)
@string key的名称,必填,不能空字符串
@return bool 成功返回true,否则返回false
@usage
log.info("fdb", fskv.del("wendal"))
 */
static int l_fskv_del(lua_State *L) {
    if (sfd_lfs == NULL) {
        LLOGE("call fskv.init() first!!!");
        return 0;
    }
    const char* key = luaL_checkstring(L, 1);
    if (key == NULL) {
        lua_pushboolean(L, 0);
        return 1;
    }
    int ret = luat_fskv_del(key);
    lua_pushboolean(L, ret == 0 ? 1 : 0);
    return 1;
}

/**
清空整个kv数据库
@api fskv.clear()
@return bool 成功返回true,否则返回false
@usage
-- 清空
fskv.clear()
 */
static int l_fskv_clr(lua_State *L) {
    if (sfd_lfs == NULL) {
        LLOGE("call fskv.init() first!!!");
        return 0;
    }
    int ret = luat_fskv_clear();
    lua_pushboolean(L, ret == 0 ? 1 : 0);
    return 1;
}


/**
kv数据库迭代器
@api fskv.iter()
@return userdata 成功返回迭代器指针,否则返回nil
@usage
-- 清空
local iter = fskv.iter()
if iter then
    while 1 do
        local k = fskv.next(iter)
        if not k then
            break
        end
        log.info("fdb", k, "value", fskv.kv_get(k))
    end
end
 */
static int l_fskv_iter(lua_State *L) {
    if (sfd_lfs == 0) {
        LLOGE("call fskv.init first!!!");
        return 0;
    }
    size_t *offset = lua_newuserdata(L, sizeof(size_t));
    memset(offset, 0, sizeof(size_t));
    return 1;
}

/**
kv迭代器获取下一个key
@api fskv.iter(iter)
@userdata fskv.iter()返回的指针
@return string 成功返回字符串key值, 否则返回nil
@usage
-- 清空
local iter = fskv.iter()
if iter then
    while 1 do
        local k = fskv.next(iter)
        if not k then
            break
        end
        log.info("fskv", k, "value", fskv.get(k))
    end
end
 */
static int l_fskv_next(lua_State *L) {
    size_t *offset = lua_touserdata(L, 1);
    char buff[256] = {0};
    int ret = luat_fskv_next(buff, *offset);
    // LLOGD("fskv.next %d %d", *offset, ret);
    if (ret == 0) {
        lua_pushstring(L, buff);
        *offset = *offset + 1;
        return 1;
    }
    return 0;
}

/*
获取kv数据库状态
@api fskv.status()
@return int 已使用的空间,单位字节
@return int 总可用空间, 单位字节
@return int 总kv键值对数量, 单位个
@usage
local used, total,kv_count = fskv.status()
log.info("fdb", "kv", used,total,kv_count)
*/
static int l_fskv_stat(lua_State *L) {
    size_t using_sz = 0;
    size_t max_sz = 0;
    size_t kv_count = 0;
    if (sfd_lfs == 0) {
        LLOGE("call fskv.init() first!!!");
        return 0;
    }
    luat_fskv_stat(&using_sz, &max_sz, &kv_count);
    lua_pushinteger(L, using_sz);
    lua_pushinteger(L, max_sz);
    lua_pushinteger(L, kv_count);
    return 3;
}

#include "rotable2.h"
static const rotable_Reg_t reg_fskv[] =
{
    { "init" ,              ROREG_FUNC(l_fskvdb_init)},
    { "set",                ROREG_FUNC(l_fskv_set)},
    { "get",                ROREG_FUNC(l_fskv_get)},
    { "del",                ROREG_FUNC(l_fskv_del)},
    { "clr",                ROREG_FUNC(l_fskv_clr)},
    { "clear",              ROREG_FUNC(l_fskv_clr)},
    { "stat",               ROREG_FUNC(l_fskv_stat)},
    { "status",             ROREG_FUNC(l_fskv_stat)},
    { "iter",               ROREG_FUNC(l_fskv_iter)},
    { "next",               ROREG_FUNC(l_fskv_next)},

    // -- 提供与fdb兼容的API
    { "kvdb_init" ,         ROREG_FUNC(l_fskvdb_init)},
    { "kv_set",             ROREG_FUNC(l_fskv_set)},
    { "kv_get",             ROREG_FUNC(l_fskv_get)},
    { "kv_del",             ROREG_FUNC(l_fskv_del)},
    { "kv_clr",             ROREG_FUNC(l_fskv_clr)},
    { "kv_stat",            ROREG_FUNC(l_fskv_stat)},
    { "kv_iter",            ROREG_FUNC(l_fskv_iter)},
    { "kv_next",            ROREG_FUNC(l_fskv_next)},
    { NULL,                 ROREG_INT(0)}
};

LUAMOD_API int luaopen_fskv( lua_State *L ) {
    luat_newlib2(L, reg_fskv);
    lua_pushvalue(L, -1);
    lua_setglobal(L, "fdb");
    return 1;
}
