/*
@module  ndk
@summary 在沙盒化的RV32环境中运行MiniRV32IMA镜像
@version 1.0
@date    2025.12.25
@tag LUAT_USE_NDK
@usage
-- 载入一个RV32镜像并执行若干步
local ctx, err = ndk.rv32i("/luadb/app.bin", 32 * 1024, 1024)
if not ctx then
    log.error("ndk", err)
    return
end
local ok, ret = ndk.exec(ctx, {steps = 100000, elapsed = 500})
if ok then
    log.info("ndk", "retval", ret)
end
*/
#include "luat_base.h"
#include "luat_mem.h"
#include "luat_log.h"
#include "luat_ndk.h"
#include "luat_zbuff.h"

#define LUAT_LOG_TAG "ndk"
#include "luat_log.h"

#include "rotable2.h"

#define LUAT_NDK_META "ndk.ctx"

static const char *ndk_errstr(int err) {
    switch (err) {
    case LUAT_NDK_OK: return "ok";
    case LUAT_NDK_ERR_PARAM: return "invalid param";
    case LUAT_NDK_ERR_NOMEM: return "no memory";
    case LUAT_NDK_ERR_IO: return "io error";
    case LUAT_NDK_ERR_IMAGE_TOO_LARGE: return "image too large";
    case LUAT_NDK_ERR_BUSY: return "busy";
    case LUAT_NDK_ERR_TRAP: return "trap";
    case LUAT_NDK_ERR_TIMEOUT: return "timeout";
    default: return "unknown";
    }
}

static luat_ndk_t *ndk_check(lua_State *L, int idx) {
    return (luat_ndk_t *)luaL_checkudata(L, idx, LUAT_NDK_META);
}

static int l_ndk_gc(lua_State *L) {
    luat_ndk_t *ndk = (luat_ndk_t *)luaL_testudata(L, 1, LUAT_NDK_META);
    if (ndk) {
        luat_ndk_deinit(ndk);
    }
    return 0;
}

/*
创建并加载一个RV32镜像
@api ndk.rv32i(path, mem_size, exchange_size)
@string path 镜像路径
@int mem_size 可选，沙盒RAM大小，默认 LUAT_NDK_DEFAULT_RAM_SIZE
@int exchange_size 可选，交换区大小，默认 LUAT_NDK_DEFAULT_EXCHANGE_SIZE
@return userdata ctx 成功返回上下文，失败返回 nil,err
*/
static int l_ndk_create(lua_State *L) {
    const char *path = luaL_checkstring(L, 1);
    size_t mem_size = luaL_optinteger(L, 2, 0);
    size_t exch_size = luaL_optinteger(L, 3, 0);

    luat_ndk_t *ndk = (luat_ndk_t *)lua_newuserdata(L, sizeof(luat_ndk_t));
    if (!ndk) {
        lua_pushnil(L);
        lua_pushliteral(L, "no memory");
        return 2;
    }
    luaL_setmetatable(L, LUAT_NDK_META);

    int rc = luat_ndk_init(ndk, path, mem_size, exch_size);
    if (rc != LUAT_NDK_OK) {
        lua_pushnil(L);
        lua_pushstring(L, ndk_errstr(rc));
        return 2;
    }
    return 1;
}

/*
向交换区写入数据
@api ndk.setData(ctx, data, offset)
@userdata ctx ndk.rv32i 返回的上下文
@string|userdata data 字符串或zbuff，写入交换区
@int offset 可选，起始偏移，默认0
@return int 写入的字节数，失败返回 false,err
*/
static int l_ndk_set_data(lua_State *L) {
    luat_ndk_t *ndk = ndk_check(L, 1);
    size_t offset = luaL_optinteger(L, 3, 0);
    size_t len = 0;
    const void *ptr = NULL;
    luat_zbuff_t *buff = NULL;
    if (lua_isuserdata(L, 2)) {
        buff = (luat_zbuff_t *)luaL_testudata(L, 2, LUAT_ZBUFF_TYPE);
    }
    if (buff) {
        ptr = buff->addr;
        len = buff->len;
    } else {
        ptr = luaL_checklstring(L, 2, &len);
    }
    int rc = luat_ndk_set_data(ndk, ptr, len, offset);
    if (rc < 0) {
        lua_pushboolean(L, 0);
        lua_pushstring(L, ndk_errstr(rc));
        return 2;
    }
    lua_pushinteger(L, rc);
    return 1;
}

/*
从交换区读取数据
@api ndk.getData(ctx, buff, len, offset)
@userdata ctx ndk.rv32i 返回的上下文
@userdata buff 可选，zbuff输出缓冲
@int len 可选，读取长度，默认交换区大小或buff长度
@int offset 可选，起始偏移，默认0
@return string|int 默认返回字符串，传入buff时返回读取字节数；失败返回 false,err
*/
static int l_ndk_get_data(lua_State *L) {
    luat_ndk_t *ndk = ndk_check(L, 1);
    size_t offset = 0;
    size_t len = ndk->exchange_size;
    size_t arg2 = 2;

    luat_zbuff_t *buff = NULL;
    if (lua_isuserdata(L, arg2)) {
        buff = (luat_zbuff_t *)luaL_testudata(L, arg2, LUAT_ZBUFF_TYPE);
        arg2++;
    }
    if (lua_isinteger(L, arg2)) {
        len = luaL_checkinteger(L, arg2);
        arg2++;
    }
    if (lua_isinteger(L, arg2)) {
        offset = luaL_checkinteger(L, arg2);
    }

    if (buff) {
        if (len > buff->len) len = buff->len;
        size_t out = 0;
        int rc = luat_ndk_get_data(ndk, buff->addr, len, offset, &out);
        if (rc != LUAT_NDK_OK) {
            lua_pushboolean(L, 0);
            lua_pushstring(L, ndk_errstr(rc));
            return 2;
        }
        lua_pushinteger(L, (lua_Integer)out);
        return 1;
    }

    luaL_Buffer b;
    luaL_buffinitsize(L, &b, len);
    size_t out = 0;
    int rc = luat_ndk_get_data(ndk, b.b, len, offset, &out);
    if (rc != LUAT_NDK_OK) {
        lua_pushboolean(L, 0);
        lua_pushstring(L, ndk_errstr(rc));
        return 2;
    }
    luaL_pushresultsize(&b, out);
    return 1;
}

/*
同步执行镜像指令
@api ndk.exec(ctx, opts, elapsed_us)
@userdata ctx ndk.rv32i 返回的上下文
@int|table opts 步数或表 {steps=步数, elapsed=每步时间us}，步数为0使用默认预算
@int elapsed_us 可选，opts为数字时的步时间us
@return boolean,int 成功返回 true,retval；失败返回 false,err,mcause,mtval
*/
static int l_ndk_exec(lua_State *L) {
    luat_ndk_t *ndk = ndk_check(L, 1);
    uint32_t steps = 0;
    uint32_t elapsed = 0;
    if (lua_istable(L, 2)) {
        lua_getfield(L, 2, "steps");
        if (lua_isinteger(L, -1)) steps = lua_tointeger(L, -1);
        lua_pop(L, 1);
        lua_getfield(L, 2, "elapsed");
        if (lua_isinteger(L, -1)) elapsed = lua_tointeger(L, -1);
        lua_pop(L, 1);
    } else {
        steps = luaL_optinteger(L, 2, 0);
        elapsed = luaL_optinteger(L, 3, 0);
    }
    int32_t retval = 0;
    int rc = luat_ndk_exec(ndk, steps, elapsed, &retval);
    if (rc == LUAT_NDK_OK) {
        lua_pushboolean(L, 1);
        lua_pushinteger(L, retval);
        return 2;
    }
    lua_pushboolean(L, 0);
    lua_pushstring(L, ndk_errstr(rc));
    lua_pushinteger(L, ndk->last_mcause);
    lua_pushinteger(L, ndk->last_mtval);
    return 4;
}

/*
重置沙箱并重新加载镜像
@api ndk.reset(ctx)
@userdata ctx ndk.rv32i 返回的上下文
@return boolean 成功返回 true，失败返回 false,err
*/
static int l_ndk_reset(lua_State *L) {
    luat_ndk_t *ndk = ndk_check(L, 1);
    int rc = luat_ndk_reset(ndk);
    lua_pushboolean(L, rc == LUAT_NDK_OK);
    if (rc != LUAT_NDK_OK) {
        lua_pushstring(L, ndk_errstr(rc));
        return 2;
    }
    return 1;
}

/*
在独立线程异步执行镜像
@api ndk.thread(ctx, opts, elapsed_us)
@userdata ctx ndk.rv32i 返回的上下文
@int|table opts 步数或表 {steps=步数, elapsed=每步时间us}
@int elapsed_us 可选，opts为数字时的步时间us
@return int 线程ID，失败返回 nil,err
*/
static int l_ndk_thread(lua_State *L) {
    luat_ndk_t *ndk = ndk_check(L, 1);
    uint32_t steps = 0;
    uint32_t elapsed = 0;
    if (lua_istable(L, 2)) {
        lua_getfield(L, 2, "steps");
        if (lua_isinteger(L, -1)) steps = lua_tointeger(L, -1);
        lua_pop(L, 1);
        lua_getfield(L, 2, "elapsed");
        if (lua_isinteger(L, -1)) elapsed = lua_tointeger(L, -1);
        lua_pop(L, 1);
    } else {
        steps = luaL_optinteger(L, 2, 0);
        elapsed = luaL_optinteger(L, 3, 0);
    }
    int rc = luat_ndk_start_thread(ndk, steps, elapsed);
    if (rc < 0) {
        lua_pushnil(L);
        lua_pushstring(L, ndk_errstr(rc));
        return 2;
    }
    lua_pushinteger(L, rc);
    return 1;
}

/*
请求停止异步线程
@api ndk.stop(ctx, wait_ms)
@userdata ctx ndk.rv32i 返回的上下文
@int wait_ms 可选，等待超时时间，默认1000
@return boolean 成功返回 true，失败返回 false,err
*/
static int l_ndk_stop(lua_State *L) {
    luat_ndk_t *ndk = ndk_check(L, 1);
    uint32_t wait_ms = luaL_optinteger(L, 2, 1000);
    int rc = luat_ndk_stop_thread(ndk, wait_ms);
    lua_pushboolean(L, rc == LUAT_NDK_OK);
    if (rc != LUAT_NDK_OK) {
        lua_pushstring(L, ndk_errstr(rc));
        return 2;
    }
    return 1;
}

/*
获取当前运行状态
@api ndk.info(ctx)
@userdata ctx ndk.rv32i 返回的上下文
@return table 包含 mem/exchange/exchange_addr/image/running/mcause/mtval
*/
static int l_ndk_info(lua_State *L) {
    luat_ndk_t *ndk = ndk_check(L, 1);
    lua_newtable(L);
    lua_pushinteger(L, ndk->ram_limit);
    lua_setfield(L, -2, "mem");
    lua_pushinteger(L, ndk->exchange_size);
    lua_setfield(L, -2, "exchange");
    lua_pushinteger(L, luat_ndk_exchange_addr(ndk));
    lua_setfield(L, -2, "exchange_addr");
    lua_pushinteger(L, ndk->image_size);
    lua_setfield(L, -2, "image");
    lua_pushboolean(L, ndk->running);
    lua_setfield(L, -2, "running");
    lua_pushinteger(L, ndk->last_mcause);
    lua_setfield(L, -2, "mcause");
    lua_pushinteger(L, ndk->last_mtval);
    lua_setfield(L, -2, "mtval");
    return 1;
}

static const luaL_Reg ndk_meta[] = {
    {"__gc", l_ndk_gc},
    {NULL, NULL}
};

static const rotable_Reg_t reg_ndk[] = {
    {"rv32i", ROREG_FUNC(l_ndk_create)},
    {"setData", ROREG_FUNC(l_ndk_set_data)},
    {"getData", ROREG_FUNC(l_ndk_get_data)},
    {"exec", ROREG_FUNC(l_ndk_exec)},
    {"reset", ROREG_FUNC(l_ndk_reset)},
    {"thread", ROREG_FUNC(l_ndk_thread)},
    {"stop", ROREG_FUNC(l_ndk_stop)},
    {"info", ROREG_FUNC(l_ndk_info)},
    {NULL, ROREG_INT(0)}
};

LUAMOD_API int luaopen_ndk(lua_State *L) {
    luaL_newmetatable(L, LUAT_NDK_META);
    luaL_setfuncs(L, ndk_meta, 0);
    lua_pop(L, 1);
    luat_newlib2(L, reg_ndk);
    return 1;
}
