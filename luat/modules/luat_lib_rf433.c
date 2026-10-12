/*
@module  rf433
@summary 433MHz 遥控接收与 EV1527 解码
@catalog 外设API
@version 1.0
@date    2026.10.12
@tag LUAT_USE_RF433

GPIO 双边沿中断在 C 层采集脉宽并解码，CSDK 和 Lua 共用同一套接收服务。
Lua 回调只收到接收器句柄，应用通过 rf433.read(handle) 读取结果 FIFO。
中断内只采集、解码和投递通知，不执行 Lua、不动态分配内存。
接收服务不创建轮询定时器或专用接收任务。
*/
#include "luat_base.h"

#ifdef LUAT_USE_RF433
#include "luat_common_api.h"
#include "luat_rf433.h"
#include "luat_msgbus.h"
#include "rotable2.h"
#define LUAT_LOG_TAG "rf433"
#include "luat_log.h"

typedef struct {
    luat_rf433_handle_t handle;
    int callback_ref;
} rf433_lua_receiver_t;

/* 句柄与 Lua 回调的对应关系只在 Lua 虚拟机线程中访问。
 * 中断消息只传递带有代数信息的句柄值，不传接收器或 Lua 状态的指针。
 * 关闭后重新开启会得到新句柄，可以据此丢弃旧实例尚未处理的通知。
 */
static rf433_lua_receiver_t receivers[LUAT_RF433_MAX_RECEIVERS];

static rf433_lua_receiver_t *rf433_find(luat_rf433_handle_t handle)
{
    unsigned i;
    for (i = 0; i < LUAT_RF433_MAX_RECEIVERS; i++) {
        if (receivers[i].handle == handle && receivers[i].callback_ref != 0)
            return &receivers[i];
    }
    return NULL;
}

static int l_rf433_ready(lua_State *L, void *ptr)
{
    rtos_msg_t *msg = (rtos_msg_t *)lua_topointer(L, -1);
    luat_rf433_handle_t handle;
    rf433_lua_receiver_t *receiver;
    int callback_ref;
    (void)ptr;
    if (!msg) return 0;
    handle = (luat_rf433_handle_t)(uint32_t)msg->arg1;
    lua_pop(L, 1);
    receiver = rf433_find(handle);
    if (!receiver) return 0; /* 接收器已关闭，或通知属于重新开启前的旧实例。 */
    callback_ref = receiver->callback_ref;
    lua_rawgeti(L, LUA_REGISTRYINDEX, callback_ref);
    if (!lua_isfunction(L, -1)) {
        lua_pop(L, 1);
        return 0;
    }
    lua_pushinteger(L, (lua_Integer)handle);
    /* 用户可能在回调中关闭或重新开启接收器。
     * 调用回调后不再访问原来的注册表引用和对应关系，避免使用已经失效的实例。
     */
    if (lua_pcall(L, 1, 0, 0) != LUA_OK) {
        const char *error = lua_tostring(L, -1);
        LLOGE("data-ready callback failed: %s", error ? error : "non-string error");
        lua_pop(L, 1);
    }
    return 0;
}

static int rf433_notify_isr(luat_rf433_handle_t handle, void *userdata)
{
    rtos_msg_t msg = {0};
    (void)userdata;
    msg.handler = l_rf433_ready;
    msg.arg1 = (int)handle;
    /* C 接收服务在 GPIO 原始边沿中断中调用此通知函数，只向消息总线投递句柄。
     * 消息总线已满时返回失败，让接收服务保留通知标志，在后续边沿再次尝试。
     */
    return luat_msgbus_put(&msg, 0) == 0u ? 0 : -1;
}

static uint32_t rf433_option_integer(lua_State *L, const char *name, uint32_t default_value, uint32_t maximum)
{
    lua_Integer value;
    lua_getfield(L, 1, name);
    if (lua_isnil(L, -1)) {
        lua_pop(L, 1);
        return default_value;
    }
    if (!lua_isinteger(L, -1))
        luaL_error(L, "rf433 option '%s' must be an integer", name);
    value = lua_tointeger(L, -1);
    if (value < 0 || (uint64_t)value > maximum)
        luaL_error(L, "rf433 option '%s' is out of range", name);
    lua_pop(L, 1);
    return (uint32_t)value;
}

static void rf433_check_options(lua_State *L)
{
    static const char *const names[] = {
        "pin", "sync_level", "sync_min_us", "sync_max_us",
        "pulse_min_us", "pulse_max_us", "pulse_mid_us", "glitch_us",
        "repeat_window_us"
    };
    lua_pushnil(L);
    while (lua_next(L, 1)) {
        const char *name;
        unsigned i;
        if (lua_type(L, -2) != LUA_TSTRING)
            luaL_error(L, "rf433 option names must be strings");
        name = lua_tostring(L, -2);
        for (i = 0; i < sizeof(names) / sizeof(names[0]); i++) {
            if (strcmp(name, names[i]) == 0) break;
        }
        if (i == sizeof(names) / sizeof(names[0]))
            luaL_error(L, "unknown rf433 option '%s'", name);
        lua_pop(L, 1);
    }
}

static luat_rf433_handle_t rf433_check_handle(lua_State *L)
{
    lua_Integer value = luaL_checkinteger(L, 1);
    if (value <= 0 || (uint64_t)value > UINT32_MAX)
        luaL_argerror(L, 1, "expected a valid rf433 handle");
    return (luat_rf433_handle_t)value;
}

/*
开启一个 433MHz 接收器
所有时间参数的单位都是微秒，同步和数据阶段共用普通毛刺过滤。
同步码按过滤后的连续电平识别，不拼接被较长反向脉冲打断的多段同步。
sync_level 只选择同步电平，数据仍按物理高电平解码：短高电平为 1，长高电平为 0。
完整帧通过帧尾检查后，还需在重复窗口内再次收到同码才输出；继续按住时，后续同码帧继续输出。
FIFO 从空变为非空时通知 Lua。回调只收到句柄，应循环读取到 nil，保证下一批数据能再次通知。
FIFO 容量为 rf433.FIFO_CAPACITY，满时丢弃新结果；最多同时开启 rf433.MAX_RECEIVERS 个接收器。
参数类型错误、缺少 pin 或包含未知配置项时会抛出 Lua 错误。
@api rf433.open(config, callback)
@table config 接收配置。pin 必填，为接收模块 DAT 所接的 GPIO 编号，开启期间由本模块独占。其余字段可选：<br>sync_level：同步电平，rf433.LOW 或 rf433.HIGH，默认 LOW。<br>sync_min_us：同步最短时长，默认 6000，必须大于 pulse_max_us。<br>sync_max_us：同步最长时长，默认 18000。<br>pulse_min_us：数据脉宽下限，默认 200。<br>pulse_max_us：数据脉宽上限，默认 1600。<br>pulse_mid_us：长短脉宽分界，默认 600，高电平小于该值为 1，否则为 0。<br>glitch_us：毛刺阈值，默认 150，严格短于该值的反向脉冲才合并，0 表示关闭毛刺合并。<br>repeat_window_us：相同完整帧的重复确认窗口，默认 500000。
@function callback 数据可读回调，形式为 function(handle)，在 Lua 虚拟机线程中执行，只传接收器句柄，不直接传键码。回调内应循环调用 rf433.read(handle) 直到返回 nil，不要调用等待函数。
@return int 接收器句柄，成功返回正整数，失败返回 nil。句柄不是 GPIO 编号。
@return int 错误码，仅 C 接收服务开启失败时返回；Lua 接收器槽位已满时只返回 nil。
@usage
-- GPIO 编号和同步电平请按实际接收模块调整
local handle, err = rf433.open({pin = 26, sync_level = rf433.LOW}, function(handle)
    while true do
        local result = rf433.read(handle)
        if not result then break end
        log.info("rf433", string.format("0x%06X", result.code), result.bits)
    end
end)
if not handle then
    log.error("rf433", "开启失败", err)
end
*/
static int l_rf433_open(lua_State *L)
{
    luat_rf433_cfg_t config;
    luat_rf433_handle_t handle = 0u;
    rf433_lua_receiver_t *slot = NULL;
    unsigned i;
    int callback_ref, status;
    luaL_checktype(L, 1, LUA_TTABLE);
    luaL_checktype(L, 2, LUA_TFUNCTION);
    rf433_check_options(L);
    lua_getfield(L, 1, "pin");
    if (lua_isnil(L, -1)) luaL_error(L, "rf433 option 'pin' is required");
    lua_pop(L, 1);
    luat_rf433_set_default_cfg(&config);
    config.pin = (int)rf433_option_integer(L, "pin", 0u, INT_MAX);
    config.sync_level = (uint8_t)rf433_option_integer(L, "sync_level", config.sync_level, 1u);
    config.sync_min_us = (uint16_t)rf433_option_integer(L, "sync_min_us", config.sync_min_us, UINT16_MAX);
    config.sync_max_us = (uint16_t)rf433_option_integer(L, "sync_max_us", config.sync_max_us, UINT16_MAX);
    config.pulse_min_us = (uint16_t)rf433_option_integer(L, "pulse_min_us", config.pulse_min_us, UINT16_MAX);
    config.pulse_max_us = (uint16_t)rf433_option_integer(L, "pulse_max_us", config.pulse_max_us, UINT16_MAX);
    config.pulse_mid_us = (uint16_t)rf433_option_integer(L, "pulse_mid_us", config.pulse_mid_us, UINT16_MAX);
    config.glitch_us = (uint16_t)rf433_option_integer(L, "glitch_us", config.glitch_us, UINT16_MAX);
    config.repeat_window_us = rf433_option_integer(L, "repeat_window_us", config.repeat_window_us, UINT32_MAX);
    config.notify = rf433_notify_isr;
    config.userdata = NULL;
    for (i = 0; i < LUAT_RF433_MAX_RECEIVERS; i++) {
        if (receivers[i].handle == 0u) {
            slot = &receivers[i];
            break;
        }
    }
    if (!slot) {
        lua_pushnil(L);
        // 当前只返回 nil，未启用错误码返回：lua_pushinteger(L, LUAT_ERROR_PERMISSION_DENIED);
        return 1;
    }
    lua_pushvalue(L, 2);
    callback_ref = luaL_ref(L, LUA_REGISTRYINDEX);
    status = luat_rf433_open(&config, &handle);
    if (status != LUAT_ERROR_NONE) {
        luaL_unref(L, LUA_REGISTRYINDEX, callback_ref);
        lua_pushnil(L);
        lua_pushinteger(L, status);
        return 2;
    }
    /* 此时可能已有中断通知入队，但 Lua 虚拟机要等本次 C 函数返回后才处理通知。
     * 因此先保存句柄和回调引用，通知处理函数就能找到完整的对应关系。
     */
    slot->handle = handle;
    slot->callback_ref = callback_ref;
    lua_pushinteger(L, (lua_Integer)handle);
    return 1;
}

/*
读取一条已确认的完整帧结果
每次调用从 FIFO 取出一条结果，不等待新数据；收到通知后应循环读取，直到返回 nil。
参数不是合法的正整数句柄时会抛出 Lua 错误；已关闭的句柄返回 nil。
@api rf433.read(handle)
@int handle rf433.open 返回的接收器句柄
@return table 接收结果，FIFO 为空、句柄已关闭或读取失败时返回 nil。结果字段：<br>code：24 位原始码，按接收顺序高位在前，未拆分地址和按键。<br>timestamp_us：确认帧的结束同步边沿在中断中的采样时刻，单位微秒，32 位计数会回绕；32 位 Lua 使用浮点数表示，精度由虚拟机决定。<br>bits：有效位数，当前固定为 24。<br>protocol：协议编号，当前为 rf433.EV1527，即数值 1。
@usage
-- handle 为已开启的接收器句柄，通常在数据可读回调中读取
while true do
    local result = rf433.read(handle)
    if not result then break end
    log.info("rf433", string.format("0x%06X", result.code), result.timestamp_us)
end
*/
static int l_rf433_read(lua_State *L)
{
    luat_rf433_result_t result;
    luat_rf433_handle_t handle = rf433_check_handle(L);
    int status;
    if (!rf433_find(handle)) {
        lua_pushnil(L);
        return 1;
    }
    status = luat_rf433_read(handle, &result);
    if (status != LUAT_ERROR_NONE) {
        lua_pushnil(L);
        return 1;
    }
    lua_createtable(L, 0, 4);
    lua_pushinteger(L, (lua_Integer)result.code);
    lua_setfield(L, -2, "code");
    /* 32 位 Lua 的有符号整数无法表示 uint32 时间戳的全部范围，较大值会变成负数。
     * 此时改用 Lua 数值类型保留非负值，精度由该虚拟机的浮点数类型决定。
     * 64 位 Lua 整数可以精确保存整个 uint32 时间戳。
     */
    if (sizeof(lua_Integer) >= sizeof(uint64_t))
        lua_pushinteger(L, (lua_Integer)result.timestamp_us);
    else
        lua_pushnumber(L, (lua_Number)result.timestamp_us);
    lua_setfield(L, -2, "timestamp_us");
    lua_pushinteger(L, result.bits);
    lua_setfield(L, -2, "bits");
    lua_pushinteger(L, result.protocol);
    lua_setfield(L, -2, "protocol");
    return 1;
}

/*
关闭一个 433MHz 接收器
C 接收服务先关闭 GPIO 接收，再由本模块释放 Lua 回调引用。
关闭后原句柄失效；重新开启会生成新句柄，队列中旧句柄的通知会被忽略。
参数不是合法的正整数句柄时会抛出 Lua 错误。
@api rf433.close(handle)
@int handle rf433.open 返回的接收器句柄
@return boolean 关闭结果，成功返回 true，句柄已关闭或关闭失败返回 false
@return int 错误码，仅仍有 Lua 回调记录、但 C 接收器已经关闭时返回；其他失败分支只返回 false
@usage
-- handle 为已开启的接收器句柄
local ok = rf433.close(handle)
log.info("rf433", "关闭结果", ok)
*/
static int l_rf433_close(lua_State *L)
{
    luat_rf433_handle_t handle = rf433_check_handle(L);
    rf433_lua_receiver_t *slot = rf433_find(handle);
    int status;
    if (!slot) {
        lua_pushboolean(L, 0);
        return 1;
    }
    status = luat_rf433_close(handle);
    if (status != LUAT_ERROR_NONE && status != LUAT_ERROR_PERMISSION_DENIED) {
        lua_pushboolean(L, 0);
        return 1;
    }
    /* 如果接收器已经被 C 层其他调用者关闭，也要释放这里保存的 Lua 回调引用。 */
    luaL_unref(L, LUA_REGISTRYINDEX, slot->callback_ref);
    slot->callback_ref = 0;
    slot->handle = 0u;
    lua_pushboolean(L, status == LUAT_ERROR_NONE);
    if (status == LUAT_ERROR_NONE) return 1;
    lua_pushinteger(L, status);
    return 2;
}

static const rotable_Reg_t reg_rf433[] = {
    {"open", ROREG_FUNC(l_rf433_open)},
    {"read", ROREG_FUNC(l_rf433_read)},
    {"close", ROREG_FUNC(l_rf433_close)},
    {"LOW", ROREG_INT(0)},
    {"HIGH", ROREG_INT(1)},
    {"EV1527", ROREG_INT(LUAT_RF433_PROTOCOL_EV1527)},
    {"FIFO_CAPACITY", ROREG_INT(LUAT_RF433_FIFO_CAPACITY)},
    {"MAX_RECEIVERS", ROREG_INT(LUAT_RF433_MAX_RECEIVERS)},
    {NULL, ROREG_INT(0)}
};

LUAMOD_API int luaopen_rf433(lua_State *L)
{
    luat_newlib2(L, reg_rf433);
    return 1;
}
#endif
