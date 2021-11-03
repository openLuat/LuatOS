
/*
@module  fdb
@summary 基于FlashDB的kv数据库和时序数据库
@version 1.0
@date    2021.11.03
*/

#include "luat_base.h"
#include "luat_msgbus.h"

#include "flashdb.h"

static struct fdb_kvdb kvdb;

/**
初始化kv数据库
@api fdb.kvdb_init(name, partition)
@string 数据库名,当前仅支持env
@string FAL分区名,当前仅支持onchip_fdb
@return boolean 成功返回true,否则返回false
@usage
if fdb.kvdb_init("env", "onchip_fdb") then
    log.info("fdb", "kv数据库初始化成功")
end
 */
static int l_fdb_kvdb_init(lua_State *L) {
    fdb_err_t ret = fdb_kvdb_init(&kvdb, "env", "onchip_fdb", NULL, NULL);
    if (ret) {
        LLOGD("fdb_kvdb_init ret=%d", ret);
    }
    lua_pushboolean(L, ret == 0 ? 1 : 0);
    return 1;
}

// 暂时对外公开
static int l_fdb_kvdb_deinit(lua_State *L) {
    fdb_err_t ret = fdb_kvdb_deinit(&kvdb);
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
@string 用户数据,必填,不能空字符串,长度不超过512字节
@return boolean 成功返回true,否则返回false
@usage
if fdb.kvdb_init("env", "onchip_fdb") then
    log.info("fdb", fdb.kv_set("wendal", "goodgoodstudy"))
end
 */
static int l_fdb_kv_set(lua_State *L) {
    size_t len;
    struct fdb_blob blob = {0};
    const char* key = luaL_checkstring(L, 1);
    const char* val = luaL_checklstring(L, 2, &len);
    blob.buf = val;
    blob.size = len;
    fdb_err_t ret = fdb_kv_set_blob(&kvdb, key, &blob);
    lua_pushboolean(L, ret == FDB_NO_ERR ? 1 : 0);
    return 1;
}

/**
根据key获取对应的数据
@api fdb.kv_get(key)
@string key的名称,必填,不能空字符串
@return string 存在则返回数据,否则返回nil
@usage
if fdb.kvdb_init("env", "onchip_fdb") then
    log.info("fdb", fdb.kv_get("wendal"))
end
 */
static int l_fdb_kv_get(lua_State *L) {
    size_t len;
    luaL_Buffer buff;
    struct fdb_blob blob = {0};
    const char* key = luaL_checkstring(L, 1);
    luaL_buffinit(L, &buff);
    blob.buf = buff.b;
    blob.size = buff.size;
    size_t read_len = fdb_kv_get_blob(&kvdb, key, &blob);
    //LLOGD("fdb_kv_get_blob ret=%d", read_len);
    if (read_len) {
        luaL_pushresultsize(&buff, read_len);
        return 1;
    }
    return 0;
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
    const char* key = luaL_checkstring(L, 1);
    fdb_err_t ret = fdb_kv_del(&kvdb, key);
    lua_pushboolean(L, ret == FDB_NO_ERR ? 1 : 0);
    return 1;
}

#include "rotable.h"
static const rotable_Reg reg_fdb[] =
{
    { "kvdb_init" ,         l_fdb_kvdb_init ,     0},
    { "kvdb_deinit" ,       l_fdb_kvdb_deinit,    0},
    { "kv_set",             l_fdb_kv_set, 0},
    { "kv_get",             l_fdb_kv_get, 0},
    { "kv_del",             l_fdb_kv_del, 0},
};

LUAMOD_API int luaopen_fdb( lua_State *L ) {
    luat_newlib(L, reg_fdb);
    return 1;
}
