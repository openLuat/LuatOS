/*
@module  airlink
@summary AirLink FOTA绑定
@catalog 外设API
@version 1.0
@date    2025.05.30
@tag LUAT_USE_AIRLINK
*/

#include "luat_base.h"
#include "luat_mem.h"
#include "luat_airlink.h"
#include "luat_airlink_fota.h"
#include "luat_zbuff.h"

#define LUAT_LOG_TAG "airlink"
#include "luat_log.h"

static int simple_cmd_nodata(lua_State *L, uint32_t cmd_id) {
    luat_airlink_cmd_t* cmd = luat_airlink_cmd_new(cmd_id, 8);
    if (cmd == NULL) return 0;
    uint64_t pkgid = luat_airlink_get_next_cmd_id();
    memcpy(cmd->data, &pkgid, 8);
    luat_airlink_send2slave(cmd);
    luat_heap_opt_free(AIRLINK_MEM_TYPE, cmd);
    lua_pushboolean(L, 1);
    return 1;
}

int l_airlink_sfota_init(lua_State *L) {
    LLOGD("执行sfota_init");
    return simple_cmd_nodata(L, 0x04);
}

int l_airlink_sfota_done(lua_State *L) {
    LLOGD("执行sfota_done");
    return simple_cmd_nodata(L, 0x06);
}

int l_airlink_sfota_end(lua_State *L) {
    LLOGD("执行sfota_end");
    return simple_cmd_nodata(L, 0x07);
}

int l_airlink_sfota_write(lua_State *L) {
    LLOGD("执行sfota_write");
    size_t len = 0;
    const char* data = NULL;
    if (lua_type(L, 1) == LUA_TSTRING) {
        data = luaL_checklstring(L, 1, &len);
    }
    else if (lua_isuserdata(L, 1)) {
        // zbuff
        luat_zbuff_t* buff = ((luat_zbuff_t *)luaL_checkudata(L, 1, LUAT_ZBUFF_TYPE));
        data = (const char*)buff->addr;
        len = buff->used;
    }
    else {
        LLOGE("无效的参数,只能是字符串或者zbuff");
        return 0;
    }
    if (len > 1500) {
        LLOGE("无效的数据长度,最大1500字节");
        return 0;
    }
    luat_airlink_cmd_t* cmd = luat_heap_opt_malloc(AIRLINK_MEM_TYPE, sizeof(luat_airlink_cmd_t) + len);
    if (cmd == NULL) return 0;
    cmd->cmd = 0x05;
    cmd->len = len;
    memcpy(cmd->data, data, len);
    luat_airlink_send2slave(cmd);
    luat_heap_opt_free(AIRLINK_MEM_TYPE, cmd);
    lua_pushboolean(L, 1);
    return 1;
}

/*
升级从机固件
@api airlink.sfota(path, id, expected_version)
@string 升级文件的路径
@int 可选实例ID；实例模式省略时选择Wi-Fi实例。当前实例OTA支持UART ARQ3。
@int 可选期望的从机版本号；实例模式重启后校验，0表示只检查重新握手
@return bool 请求接受返回true，拒绝返回false；升级结果通过AIRLINK_SFOTA_DONE发布
@usage
-- 注意, 升级过程是异步的, 耗时1~2分钟, 注意观察日志
airlink.sfota("/luadb/air8000s_v5.bin")
-- 实例模式：升级期间暂停目标实例业务发送，其他实例继续工作
-- 先订阅AIRLINK_SFOTA_DONE(result, reason, id)，再提交：
-- airlink.sfota("/luadb/peer.bin", 1, 33)
*/
int l_airlink_sfota(lua_State *L) {
    // 直接发指令是不行了, 需要干预airlink task的执行流程
    // bk72xx的flash擦除很慢, 导致spi master需要等很久才能发下一个包
    const char* path = luaL_checkstring(L, 1);
#ifdef LUAT_USE_AIRLINK_INSTANCE
    if (luat_airlink_instance_enabled()) {
        lua_Integer id = lua_isnoneornil(L, 2) ?
            luat_airlink_feature_route(AIRLINK_FEATURE_WIFI) - AIRLINK_ROUTE_BASE : luaL_checkinteger(L, 2);
        lua_Integer version = luaL_optinteger(L, 3, 0);
        int ret = (id < 0 || id >= AIRLINK_LINK_COUNT || version < 0 || (uint64_t)version > UINT32_MAX) ?
            -1 : luat_airlink_link_sfota((int)id, path, (uint32_t)version);
        lua_pushboolean(L, ret == 0);
        return 1;
    }
#endif
    if (!lua_isnoneornil(L, 2)) { lua_pushboolean(L, 0); return 1; }
    luat_airlink_fota_t ctx = {0};
    if (strlen(path) >= sizeof(ctx.path)) { lua_pushboolean(L, 0); return 1; }
    memcpy(ctx.path, path, strlen(path) + 1);
    int ret = luat_airlink_fota_init(&ctx);
    if (ret) {
        LLOGE("sfota 启动失败!!! %s %d", path, ret);
    }
    lua_pushboolean(L, ret == 0);
    return 1;
}
