#include "luat_base.h"
#include "luat_spi.h"
#include "luat_airlink.h"

#include "luat_rtos.h"
#include "luat_debug.h"
#include "luat_spi.h"
#include "luat_pm.h"
#include "luat_gpio.h"
#include "luat_airlink.h"
#include "luat_fota.h"
#include "luat_mem.h"
#include "luat_msgbus.h"

#define LUAT_LOG_TAG "airlink"
#include "luat_log.h"

__USER_FUNC_IN_RAM__ int luat_airlink_cmd_exec_nop(luat_airlink_cmd_t *cmd, void *userdata)
{
    return 0;
}

int luat_airlink_cmd_exec_ping(luat_airlink_cmd_t *cmd, void *userdata)
{
    LLOGD("收到ping指令,返回pong");
    // TODO 返回PONG
    return 0;
}

int luat_airlink_cmd_exec_pong(luat_airlink_cmd_t *cmd, void *userdata)
{
    LLOGD("收到pong指令,检查数据是否匹配!!");
    return 0;
}

int luat_airlink_cmd_exec_reset(luat_airlink_cmd_t *cmd, void *userdata)
{
    LLOGD("收到reset指令!!!");
    luat_pm_reset();
    return 0;
}

int luat_airlink_cmd_exec_fota_init(luat_airlink_cmd_t *cmd, void *userdata)
{
    LLOGD("收到FOTA初始化指令!!!");
    int ret = luat_fota_init(0, 0, NULL, NULL, 0);
    LLOGD("fota_init ret %d", ret);
    return 0;
}

int luat_airlink_cmd_exec_fota_write(luat_airlink_cmd_t *cmd, void *userdata)
{
    // LLOGD("收到FOTA数据, len=%ld %02X%02X%02X%02X", cmd->len, cmd->data[0], cmd->data[1], cmd->data[2], cmd->data[3]);
    int ret = luat_fota_write(cmd->data, cmd->len);
    if (ret) {
        LLOGD("fota_write ret %d", ret);
    }
    return 0;
}

int luat_airlink_cmd_exec_fota_done(luat_airlink_cmd_t *cmd, void *userdata)
{
    LLOGD("收到FOTA传输完毕指令!!!");
    int ret = luat_fota_done();
    LLOGD("fota_done ret %d", ret);
    return 0;
}

int luat_airlink_cmd_exec_fota_end(luat_airlink_cmd_t *cmd, void *userdata)
{
    LLOGD("收到FOTA传输完毕指令!!!");
    int ret = luat_fota_end(1);
    LLOGD("fota_end ret %d", ret);
    return 0;
}

#ifdef __LUATOS__
#include "luat_msgbus.h"

static int sdata_cb(lua_State *L, void *ptr)
{
    rtos_msg_t *msg = (rtos_msg_t *)lua_topointer(L, -1);
    lua_getglobal(L, "sys_pub");
    lua_pushstring(L, "AIRLINK_SDATA");
    lua_pushlstring(L, msg->ptr, msg->arg1);
    luat_heap_opt_free(AIRLINK_MEM_TYPE, msg->ptr);
    lua_call(L, 2, 0);
    return 0;
}

int luat_airlink_cmd_exec_sdata(luat_airlink_cmd_t *cmd, void *userdata)
{
    // LLOGD("收到sdata指令!!! %d", cmd->len);
    rtos_msg_t msg = {0};
    msg.handler = sdata_cb;
    msg.ptr = luat_heap_opt_malloc(AIRLINK_MEM_TYPE, cmd->len);
    if (msg.ptr == NULL)
    {
        LLOGE("sdata_cb malloc fail!!! %d", cmd->len);
        return 0;
    }
    memcpy(msg.ptr, cmd->data, cmd->len);
    msg.arg1 = cmd->len;
    luat_msgbus_put(&msg, 0);
    return 0;
}
#endif

int luat_airlink_cmd_exec_notify_log(luat_airlink_cmd_t *cmd, void *userdata) {
    if (cmd->len < 9) {
        return 0;
    }
    uint8_t level = cmd->data[0];
    uint8_t tag_len = cmd->data[1];
    char tag[16] = {0};
    memcpy(tag, cmd->data + 2, tag_len);
    luat_log_log(level, tag, "%.*s", cmd->len - 2 - tag_len, cmd->data + 2 + tag_len);
    return 0;
}

static int push_args(lua_State *L, uint8_t* ptr, uint32_t* limit) {
    uint32_t tmp = *limit;
    if (tmp < 2) {
        return 0;
    }
    uint8_t type = ptr[0];
    uint8_t len = ptr[1];
    uint32_t i = 0;
    uint8_t b = 0;
    float f = 0;
    if (len + 2 > tmp) {
        return -1;
    }
    switch (type)
    {
    case LUA_TSTRING:
        // LLOGD("添加字符串 %.*s", len, ptr + 2);
        lua_pushlstring(L, (const char*)ptr + 2, len);
        break;
    case LUA_TNUMBER:
        memcpy(&f, ptr + 2, 4);
        // LLOGD("添加浮点数 %f", f);
        lua_pushnumber(L, f);
        break;
    case LUA_TINTEGER:
        memcpy(&i, ptr + 2, 4);
        // LLOGD("添加整数 %d", i);
        lua_pushinteger(L, i);
        break;
    case LUA_TBOOLEAN:
        memcpy(&b, ptr + 2, 1);
        // LLOGD("添加bool %d", b);
        lua_pushboolean(L, b);
        break;
    case LUA_TNIL:
        // LLOGD("添加nil");
        lua_pushnil(L);
        break;
    
    default:
        break;
    }
    return len + 2;
}

static int l_airlink_sys_pub(lua_State *L, void* ptr) {
    int ret = 0;
    rtos_msg_t* msg = (rtos_msg_t*)lua_topointer(L, -1);
    if (lua_getglobal(L, "sys_pub") != LUA_TFUNCTION) {
        LLOGE("获取 sys_pub 失败!!!");
        return 0;
    };
    uint32_t limit = msg->arg1;
    uint8_t* tmp = msg->ptr;
    int c = 0;
    while (limit > 0) {
        ret = push_args(L, tmp, &limit);
        if (ret <= 0) {
            break;
        }
        tmp += ret;
        limit -= ret;
        c ++;
    }
    ret = lua_pcall(L, c, 0, 0);
    // LLOGD("pcall args %d ret %d", c, ret);
    return 0;
}

int luat_airlink_cmd_exec_notify_sys_pub(luat_airlink_cmd_t *cmd, void *userdata) {
    // LLOGD("收到sys_pub指令!!! %d", cmd->len);
    if (cmd->len < 12) {
        LLOGD("非法的sys_pub指令,长度不足 %d", cmd->len);
        return 0;
    }
    rtos_msg_t msg = {0};
    msg.handler = l_airlink_sys_pub;
    msg.ptr = luat_heap_opt_malloc(AIRLINK_MEM_TYPE, cmd->len - 8);
    if (msg.ptr == NULL) {
        LLOGE("l_airlink_sys_pub malloc fail!!! %d", cmd->len - 8);
        return 0;
    }
    memcpy(msg.ptr, cmd->data + 8, cmd->len - 8);
    msg.arg1 = cmd->len - 8;
    luat_msgbus_put(&msg, 0);
    return 0;
}

