
/*
@module  fdb
@summary kv数据库,掉电不丢数据
@version 1.0
@date    2021.11.03
@demo fdb
@tag LUAT_USE_FDB
*/

#include "luat_base.h"
#include "luat_msgbus.h"
#include "luat_malloc.h"

#include "flashdb.h"

#ifndef LUAT_LOG_TAG
#define LUAT_LOG_TAG "fdb"
#include "luat_log.h"
#endif

static struct fdb_kvdb* kvdb;
static uint32_t kvdb_inited = 0;

/**
初始化kv数据库
@api fdb.kvdb_init(name, partition)
@string 数据库名,当前仅支持env
@string FAL分区名,当前仅支持onchip_fdb
@return boolean 成功返回true,否则返回false
@usage
-- fdb库基于 flashdb , 再次表示感谢.
if fdb.kvdb_init("env", "onchip_fdb") then
    log.info("fdb", "kv数据库初始化成功")
end

-- 关于清空fdb库
-- 下载工具是没有提供直接清除fdb数据的途径的, 但有有办法解决
-- 写一个main.lua, 执行 fdb.kvdb_init 后 执行 fdb.clear() 即可全清fdb数据.
 */
static int l_fdb_kvdb_init(lua_State *L) {
    if (kvdb == NULL) {
        kvdb = luat_heap_malloc(sizeof(struct fdb_kvdb));
        if (kvdb == NULL) {
            LLOGE("malloc kvdb failed!!!!");
            lua_pushboolean(L, 0);
            return 1;
        }
    }
    if (kvdb_inited == 0) {
        memset(kvdb, 0, sizeof(struct fdb_kvdb));
        fdb_err_t ret = fdb_kvdb_init(kvdb, "env", "onchip_fdb", NULL, NULL);
        if (ret) {
            LLOGE("fdb_kvdb_init ret=%d", ret);
        }
        else {
            kvdb_inited = 1;
        }
        lua_pushboolean(L, ret == 0 ? 1 : 0);
    }
    else {
        lua_pushboolean(L, 1);
    }
    return 1;
}

// 暂时对外公开
static int l_fdb_kvdb_deinit(lua_State *L) {
    if (kvdb_inited == 0) {
        LLOGE("call fdb.kvdb_init first!!!");
        return 0;
    }
    fdb_err_t ret = fdb_kvdb_deinit(kvdb);
    if (ret) {
        LLOGD("fdb_kvdb_deinit ret=%d", ret);
    }
    lua_pushboolean(L, ret == FDB_NO_ERR ? 1 : 0);
    return 1;
}

/**
设置一对kv数据
@api fdb.kv_set(key, value)
@string key的名称,必填,不能空字符串
@string 用户数据,必填,不能nil, 支持字符串/数值/table/布尔值, 数据长度最大255字节
@return boolean 成功返回true,否则返回false
@return number 第二个为返回为flashdb的fdb_kv_set_blob返回详细状态,0：无错误 1:擦除错误 2:读错误 3:些错误 4:未找到 5:kv名字错误 6:kv名字存在 7:已保存 8:初始化错误
@usage
if fdb.kvdb_init("env", "onchip_fdb") then
    log.info("fdb", fdb.kv_set("wendal", "goodgoodstudy"))
end
 */
static int l_fdb_kv_set(lua_State *L) {
    if (kvdb_inited == 0) {
        LLOGE("call fdb.kvdb_init first!!!");
        return 0;
    }
    size_t len;
    struct fdb_blob blob = {0};
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
    blob.buf = buff.b;
    blob.size = buff.n;
    fdb_err_t ret = fdb_kv_set_blob(kvdb, key, &blob);
    lua_pushboolean(L, ret == FDB_NO_ERR ? 1 : 0);
    lua_pushinteger(L, ret);
    return 2;
}

/**
根据key获取对应的数据
@api fdb.kv_get(key, skey)
@string key的名称,必填,不能空字符串
@string 可选的次级key,仅当原始值为table时有效,相当于 fdb.kv_get(key)[skey]
@return any 存在则返回数据,否则返回nil
@usage
if fdb.kvdb_init("env", "onchip_fdb") then
    log.info("fdb", fdb.kv_get("wendal"))
end
 */
static int l_fdb_kv_get(lua_State *L) {
    if (kvdb_inited == 0) {
        LLOGE("call fdb.kvdb_init first!!!");
        return 0;
    }
    luaL_Buffer buff;
    struct fdb_blob blob = {0};
    const char* key = luaL_checkstring(L, 1);
    const char* skey = luaL_optstring(L, 2, "");
    luaL_buffinit(L, &buff);
    blob.buf = buff.b;
    blob.size = buff.size;
    size_t read_len = fdb_kv_get_blob(kvdb, key, &blob);

    lua_Integer *intVal;
    // lua_Number *numVal;

    if (read_len) {
        // LLOGD("KV value T=%02X", buff.b[0]);
        switch(buff.b[0]) {
        case LUA_TBOOLEAN:
            lua_pushboolean(L, buff.b[1]);
            break;
        case LUA_TNUMBER:
            lua_getglobal(L, "pack");
            lua_getfield(L, -1, "unpack");
            lua_pushlstring(L, (char*)(buff.b + 1), read_len - 1);
            lua_pushstring(L, ">f");
            lua_call(L, 2, 2);
            // _, val = pack.unpack(data, ">f")
            break;
        case LUA_TINTEGER:
            intVal = (lua_Integer*)(&buff.b[1]);
            lua_pushinteger(L, *intVal);
            break;
        case LUA_TSTRING:
            lua_pushlstring(L, (const char*)(buff.b + 1), read_len - 1);
            break;
        case LUA_TTABLE:
            lua_getglobal(L, "json");
            lua_getfield(L, -1, "decode");
            lua_pushlstring(L, (const char*)(buff.b + 1), read_len - 1);
            lua_call(L, 1, 1);
            if (strlen(skey) > 0 && lua_istable(L, -1)) {
                lua_getfield(L, -1, skey);
            }
            break;
        default :
            LLOGW("bad value prefix %02X", buff.b[0]);
            lua_pushnil(L);
            break;
        }
        return 1;
    }
    lua_pushnil(L);
    return 1;
}

/**
根据key删除数据
@api fdb.kv_del(key)
@string key的名称,必填,不能空字符串
@return bool 成功返回true,否则返回false
@usage
if fdb.kvdb_init("env", "onchip_fdb") then
    log.info("fdb", fdb.kv_del("wendal"))
end
 */
static int l_fdb_kv_del(lua_State *L) {
    if (kvdb_inited == 0) {
        LLOGE("call fdb.kvdb_init first!!!");
        return 0;
    }
    const char* key = luaL_checkstring(L, 1);
    if (key == NULL) {
        lua_pushboolean(L, 0);
        return 1;
    }
    fdb_err_t ret = fdb_kv_del(kvdb, key);
    lua_pushboolean(L, ret == FDB_NO_ERR ? 1 : 0);
    return 1;
}

/**
清空整个kv数据库
@api fdb.kv_clr()
@return bool 成功返回true,否则返回false
@usage
-- 清空
fdb.kv_clr()
 */
static int l_fdb_kv_clr(lua_State *L) {
    if (kvdb_inited == 0) {
        LLOGE("call fdb.kvdb_init first!!!");
        return 0;
    }
    fdb_err_t ret = fdb_kv_set_default(kvdb);
    lua_pushboolean(L, ret == FDB_NO_ERR ? 1 : 0);
    lua_pushinteger(L, ret);
    return 2;
}


/**
kv数据库迭代器
@api fdb.kv_iter()
@return userdata 成功返回迭代器指针,否则返回nil
@usage
-- 清空
local iter = fdb.kv_iter()
if iter then
    while 1 do
        local k = fdb.kv_next(iter)
        if not k then
            break
        end
        log.info("fdb", k, "value", fdb.kv_get(k))
    end
end
 */
static int l_fdb_kv_iter(lua_State *L) {
    if (kvdb_inited == 0) {
        LLOGE("call fdb.kvdb_init first!!!");
        return 0;
    }
    fdb_kv_iterator_t iter = lua_newuserdata(L, sizeof(struct fdb_kv_iterator));
    if (iter == NULL) {
        return 0;
    }
    iter = fdb_kv_iterator_init(iter);
    if (iter != NULL) {
        return 1;
    }
    return 0;
}

/**
kv迭代器获取下一个key
@api fdb.kv_iter(iter)
@userdata fdb.kv_iter()返回的指针
@return string 成功返回字符串key值, 否则返回nil
@usage
-- 清空
local iter = fdb.kv_iter()
if iter then
    while 1 do
        local k = fdb.kv_next(iter)
        if not k then
            break
        end
        log.info("fdb", k, "value", fdb.kv_get(k))
    end
end
 */
static int l_fdb_kv_next(lua_State *L) {
    fdb_kv_t cur_kv = NULL;
    fdb_kv_iterator_t iter = lua_touserdata(L, 1);
    if (iter == NULL) {
        return 0;
    }
    bool ret = fdb_kv_iterate(kvdb, iter);
    if (ret) {
        cur_kv = &(iter->curr_kv);
        lua_pushlstring(L, cur_kv->name, cur_kv->name_len);
        // TODO 把值也返回一下?
        return 1;
    }
    return 0;
}

/*
获取kv数据库状态
@api fdb.kv_stat()
@return int 已使用的空间,单位字节
@return int 总可用空间, 单位字节
@return int 总kv键值对数量, 单位个
@usage
-- 本API于2022.07.23 添加
local used,maxs,kv_count = fdb.kv_stat()
log.info("fdb", "kv", used,maxs,kv_count)
*/
static int l_fdb_kv_stat(lua_State *L) {
    uint32_t using_sz = 0;
    uint32_t max_sz = 0;
    uint32_t kv_count = 0;
    if (kvdb_inited == 0) {
        LLOGE("call fdb.kvdb_init first!!!");
        return 0;
    }
    fdb_kv_stat(kvdb, &using_sz, &max_sz, &kv_count);
    lua_pushinteger(L, using_sz);
    lua_pushinteger(L, max_sz);
    lua_pushinteger(L, kv_count);
    return 3;
}

#include "rotable2.h"
static const rotable_Reg_t reg_fdb[] =
{
    { "kvdb_init" ,         ROREG_FUNC(l_fdb_kvdb_init)},
    { "kvdb_deinit" ,       ROREG_FUNC(l_fdb_kvdb_deinit)},
    { "kv_set",             ROREG_FUNC(l_fdb_kv_set)},
    { "kv_get",             ROREG_FUNC(l_fdb_kv_get)},
    { "kv_del",             ROREG_FUNC(l_fdb_kv_del)},
    { "kv_clr",             ROREG_FUNC(l_fdb_kv_clr)},
    { "kv_iter",            ROREG_FUNC(l_fdb_kv_iter)},
    { "kv_next",            ROREG_FUNC(l_fdb_kv_next)},
    { "kv_stat",            ROREG_FUNC(l_fdb_kv_stat)},
    { NULL,                 ROREG_INT(0)}
};

LUAMOD_API int luaopen_fdb( lua_State *L ) {
    luat_newlib2(L, reg_fdb);
    return 1;
}
