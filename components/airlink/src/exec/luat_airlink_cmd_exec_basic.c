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

#define LUAT_LOG_TAG "airlink"
#include "luat_log.h"

int luat_airlink_cmd_exec_nop(luat_airlink_cmd_t *cmd, void *userdata)
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
    LLOGD("收到FOTA数据!!!");
    int ret = luat_fota_write(cmd->data, cmd->len);
    LLOGD("fota_write ret %d", ret);
    return 0;
}

int luat_airlink_cmd_exec_fota_done(luat_airlink_cmd_t *cmd, void *userdata)
{
    LLOGD("收到FOTA传输完毕指令!!!");
    int ret = luat_fota_done();
    LLOGD("fota_write ret %d", ret);
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
    LLOGD("收到sdata指令!!!");
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
