
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

static char fskv_read_buff[LUAT_FSKV_MAX_SIZE];

/**
初始化kv数据库
@api fskv.init()
@string 数据库名,当前仅支持env
@string FAL分区名,当前仅支持onchip_fdb
@return boolean 成功返回true,否则返回false
@usage
if fskv.init() then
    log.info("fdb", "kv数据库初始化成功")
end

-- 关于清空fdb库
-- 下载工具是没有提供直接清除fdb数据的途径的, 但有有办法解决
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
@api fskv.kv_set(key, value)
@string key的名称,必填,不能空字符串
@string 用户数据,必填,不能nil, 支持字符串/数值/table/布尔值, 数据长度最大255字节
@return boolean 成功返回true,否则返回false
@return number 第二个为返回为flashdb的fdb_kv_set_blob返回详细状态,0：无错误 1:擦除错误 2:读错误 3:些错误 4:未找到 5:kv名字错误 6:kv名字存在 7:已保存 8:初始化错误
@usage
if fskv.kvdb_init("env", "onchip_fdb") then
    log.info("fdb", fskv.kv_set("wendal", "goodgoodstudy"))
end
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
    lua_pushinteger(L, ret);
    return 2;
}

/**
根据key获取对应的数据
@api fskv.kv_get(key, skey)
@string key的名称,必填,不能空字符串
@string 可选的次级key,仅当原始值为table时有效,相当于 fskv.kv_get(key)[skey]
@return any 存在则返回数据,否则返回nil
@usage
if fskv.init() then
    log.info("fdb", fskv.get("wendal"))
end
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
    char* buff = fskv_read_buff;
    size_t read_len = luat_fskv_get(key, buff, LUAT_FSKV_MAX_SIZE);

    if (read_len < 2) {
        return 0;
    }

    lua_Integer *intVal;
    // lua_Number *numVal;

    if (read_len) {
        // LLOGD("KV value T=%02X", buff.b[0]);
        switch(buff[0]) {
        case LUA_TBOOLEAN:
            lua_pushboolean(L, buff[1]);
            break;
        case LUA_TNUMBER:
            lua_getglobal(L, "pack");
            lua_getfield(L, -1, "unpack");
            lua_pushlstring(L, (char*)(buff + 1), read_len - 1);
            lua_pushstring(L, ">f");
            lua_call(L, 2, 2);
            // _, val = pack.unpack(data, ">f")
            break;
        case LUA_TINTEGER:
            intVal = (lua_Integer*)(&buff[1]);
            lua_pushinteger(L, *intVal);
            break;
        case LUA_TSTRING:
            lua_pushlstring(L, (const char*)(buff + 1), read_len - 1);
            break;
        case LUA_TTABLE:
            lua_getglobal(L, "json");
            lua_getfield(L, -1, "decode");
            lua_pushlstring(L, (const char*)(buff + 1), read_len - 1);
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
        return 1;
    }
    lua_pushnil(L);
    return 1;
}

/**
根据key删除数据
@api fskv.kv_del(key)
@string key的名称,必填,不能空字符串
@return bool 成功返回true,否则返回false
@usage
if fskv.kvdb_init("env", "onchip_fdb") then
    log.info("fdb", fskv.kv_del("wendal"))
end
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
@api fskv.kv_clr()
@return bool 成功返回true,否则返回false
@usage
-- 清空
fskv.kv_clr()
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


// /**
// kv数据库迭代器
// @api fskv.kv_iter()
// @return userdata 成功返回迭代器指针,否则返回nil
// @usage
// -- 清空
// local iter = fskv.kv_iter()
// if iter then
//     while 1 do
//         local k = fskv.kv_next(iter)
//         if not k then
//             break
//         end
//         log.info("fdb", k, "value", fskv.kv_get(k))
//     end
// end
//  */
// static int l_fskv_iter(lua_State *L) {
//     if (kvdb_inited == 0) {
//         LLOGE("call fskv.kvdb_init first!!!");
//         return 0;
//     }
//     fdb_kv_iterator_t iter = lua_newuserdata(L, sizeof(struct fdb_kv_iterator));
//     if (iter == NULL) {
//         return 0;
//     }
//     iter = fdb_kv_iterator_init(iter);
//     if (iter != NULL) {
//         return 1;
//     }
//     return 0;
// }

// /**
// kv迭代器获取下一个key
// @api fskv.kv_iter(iter)
// @userdata fskv.kv_iter()返回的指针
// @return string 成功返回字符串key值, 否则返回nil
// @usage
// -- 清空
// local iter = fskv.kv_iter()
// if iter then
//     while 1 do
//         local k = fskv.kv_next(iter)
//         if not k then
//             break
//         end
//         log.info("fdb", k, "value", fskv.kv_get(k))
//     end
// end
//  */
// static int l_fskv_next(lua_State *L) {
//     fdb_kv_t cur_kv = NULL;
//     fdb_kv_iterator_t iter = lua_touserdata(L, 1);
//     if (iter == NULL) {
//         return 0;
//     }
//     bool ret = fdb_kv_iterate(kvdb, iter);
//     if (ret) {
//         cur_kv = &(iter->curr_kv);
//         lua_pushlstring(L, cur_kv->name, cur_kv->name_len);
//         // TODO 把值也返回一下?
//         return 1;
//     }
//     return 0;
// }

/*
获取kv数据库状态
@api fskv.stat()
@return int 已使用的空间,单位字节
@return int 总可用空间, 单位字节
@return int 总kv键值对数量, 单位个
@usage
local used, total,kv_count = fskv.stat()
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
    { "stat",               ROREG_FUNC(l_fskv_stat)},
    // { "kv_iter",            ROREG_FUNC(l_fskv_iter)},
    // { "kv_next",            ROREG_FUNC(l_fskv_next)},
    // { "kv_stat",            ROREG_FUNC(l_fskv_stat)},

    // -- 提供与fdb兼容的API
    { "kvdb_init" ,         ROREG_FUNC(l_fskvdb_init)},
    { "kv_set",             ROREG_FUNC(l_fskv_set)},
    { "kv_get",             ROREG_FUNC(l_fskv_get)},
    { "kv_del",             ROREG_FUNC(l_fskv_del)},
    { "kv_clr",             ROREG_FUNC(l_fskv_clr)},
    { "kv_stat",            ROREG_FUNC(l_fskv_stat)},
    { NULL,                 ROREG_INT(0)}
};

LUAMOD_API int luaopen_fskv( lua_State *L ) {
    luat_newlib2(L, reg_fskv);
    lua_pushvalue(L, -1);
    lua_setglobal(L, "fdb");
    return 1;
}
