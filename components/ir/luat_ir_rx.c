#include "luat_base.h"
#ifdef LUAT_USE_IR_RX
#include "luat_ir_rx.h"
#include "luat_ir_nec.h"
#include "luat_gpio.h"
#include "luat_mem.h"
#include "luat_msgbus.h"
#define LUAT_LOG_TAG "ir"
#include "luat_log.h"
#ifdef _MSC_VER
#include <intrin.h>
#endif

typedef struct {
    luat_ir_nec_t nec;
    uint32_t generation;
    uint32_t edges;
    uint32_t frames;
    int callback;
} ir_receiver_t;

static ir_receiver_t *receivers[LUAT_GPIO_PIN_MAX];
static uint32_t generation;

/* 中断累加、Lua 任务读取同一计数器；加 0 用于原子读取。 */
static uint32_t counter_add(uint32_t *counter, uint32_t n) {
#ifdef _MSC_VER
    return (uint32_t)_InterlockedExchangeAdd((volatile long *)counter, (long)n) + n;
#else
    return __sync_add_and_fetch(counter, n);
#endif
}

static ir_receiver_t *receiver(lua_Integer pin) {
    return pin >= 0 && pin < LUAT_GPIO_PIN_MAX ? receivers[pin] : NULL;
}

static int dispatch(lua_State *L, void *ptr) {
    (void)ptr;
    rtos_msg_t *msg = (rtos_msg_t *)lua_topointer(L, -1);
    ir_receiver_t *rx = receiver(msg->arg1);
    if (!rx || rx->generation != (uint32_t)(uintptr_t)msg->ptr) return 0;
    uint32_t value = (uint32_t)msg->arg2;
    lua_rawgeti(L, LUA_REGISTRYINDEX, rx->callback);
    lua_pushinteger(L, value & 0xffff);
    lua_pushinteger(L, (value >> 16) & 0xff);
    lua_pushboolean(L, value >> 24);
    if (lua_pcall(L, 3, 0, 0) != LUA_OK) {
        const char *error = lua_tostring(L, -1);
        LLOGE("rx callback: %s", error ? error : "non-string Lua error");
        lua_pop(L, 1);
    }
    return 0;
}

void luat_ir_rx_edge(int pin, uint64_t now_us) {
    ir_receiver_t *rx = receiver(pin);
    if (!rx) return;
    counter_add(&rx->edges, 1);
    luat_ir_event_t event = luat_ir_nec_edge(&rx->nec, now_us);
    if (event == LUAT_IR_NONE) return;
    if (event == LUAT_IR_KEY) counter_add(&rx->frames, 1);
    /* 保存当前帧的快照：低 16 位为地址，接下来 8 位为命令，第 24 位标记重复帧。 */
    uint32_t value = rx->nec.addr | ((uint32_t)rx->nec.cmd << 16)
                   | ((uint32_t)(event == LUAT_IR_REPEAT) << 24);
    /* 消息只保存初始化编号，不持有接收器指针。Lua 任务分发时据此丢弃关闭前的旧消息。 */
    rtos_msg_t msg = {.handler = dispatch, .ptr = (void *)(uintptr_t)rx->generation,
                      .arg1 = pin, .arg2 = (int)value};
    luat_msgbus_put(&msg, 0);
}

static int rx_error(lua_State *L, const char *reason) {
    lua_pushboolean(L, 0);
    lua_pushstring(L, reason);
    return 2;
}

/**
启动 NEC 红外接收
@api ir.rxInit(pin, callback)
@int 接收引脚，需要支持下降沿中断
@function 收到有效帧时调用 callback(addr, cmd, is_repeat)
@return boolean 成功返回 true
@return string 仅失败时返回原因
*/
int luat_ir_rx_init(lua_State *L) {
    lua_Integer pin = luaL_checkinteger(L, 1);
    luaL_checktype(L, 2, LUA_TFUNCTION);
    if (pin < 0 || pin >= LUAT_GPIO_PIN_MAX) return rx_error(L, "invalid pin");
    if (receivers[pin]) return rx_error(L, "pin already initialized");
    lua_pushvalue(L, 2);
    int ref = luaL_ref(L, LUA_REGISTRYINDEX);
    ir_receiver_t *rx = luat_heap_calloc(1, sizeof(*rx));
    if (!rx) {
        luaL_unref(L, LUA_REGISTRYINDEX, ref);
        return rx_error(L, "out of memory");
    }
    rx->callback = ref;
    rx->generation = ++generation;
    /* 先登记接收器，确保启用捕获后到来的第一个中断能找到对应状态。 */
    receivers[pin] = rx;
    if (luat_ir_capture_start((int)pin)) {
        receivers[pin] = NULL;
        luaL_unref(L, LUA_REGISTRYINDEX, ref);
        luat_heap_free(rx);
        return rx_error(L, "GPIO capture unavailable");
    }
    lua_pushboolean(L, 1);
    return 1;
}

/**
读取本次接收统计
@api ir.rxStats(pin)
@int 接收引脚
@return int 下降沿数，未初始化时无返回值
@return int 有效完整帧数，不含重复帧
*/
int luat_ir_rx_stats(lua_State *L) {
    ir_receiver_t *rx = receiver(luaL_checkinteger(L, 1));
    if (!rx) return 0;
    uint32_t frames = counter_add(&rx->frames, 0);
    uint32_t edges = counter_add(&rx->edges, 0);
    lua_pushinteger(L, edges);
    lua_pushinteger(L, frames);
    return 2;
}

/**
停止 NEC 红外接收并释放引脚
@api ir.rxClose(pin)
@int 接收引脚
@return boolean 成功返回 true，未初始化返回 false
*/
int luat_ir_rx_close(lua_State *L) {
    lua_Integer pin = luaL_checkinteger(L, 1);
    ir_receiver_t *rx = receiver(pin);
    int was_open = rx != NULL;
    if (rx) {
        luat_ir_capture_stop((int)pin);
        receivers[pin] = NULL;
        luaL_unref(L, LUA_REGISTRYINDEX, rx->callback);
        luat_heap_free(rx);
    }
    lua_pushboolean(L, was_open);
    return 1;
}
#endif
