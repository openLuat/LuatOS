
#include "luat_base.h"
#include "luat_log.h"
#include "luat_sys.h"
#include "luat_msgbus.h"
#include "luat_timer.h"
#include "luat_malloc.h"


//------------------------------------------------------------------
static int l_rtos_receive(lua_State *L) {
    rtos_msg_t msg;
    int re;
    re = luat_msgbus_get(&msg, luaL_checkinteger(L, 1));
    if (!re) {
        // luat_print("luat_msgbus_get msg!!!\n");
        return msg.handler(L, msg.ptr);
    }
    else {
        // luat_print("luat_msgbus_get timeout!!!\n");
        lua_pushinteger(L, -1);
        return 1;
    }
}

//------------------------------------------------------------------
static int l_timer_handler(lua_State *L, void* ptr) {
    luat_timer_t *timer = (luat_timer_t *)ptr;
    // luat_printf("l_timer_handler id=%ld\n", timer->id);
    lua_pushinteger(L, MSG_TIMER);
    lua_pushinteger(L, timer->id);
    lua_pushinteger(L, timer->timeout);
    lua_pushinteger(L, timer->repeat);
    if (timer->repeat == 0) {
        luat_timer_stop(timer);
        luat_heap_free(timer);
    }
    else if (timer->repeat > 0) {
        timer->repeat --;
    }
    return 4;
}

static int l_rtos_timer_start(lua_State *L) {
    lua_gettop(L);
    size_t id = (size_t)luaL_checkinteger(L, 1) / 1;
    size_t timeout = (size_t)luaL_checkinteger(L, 2);
    size_t repeat = (size_t)luaL_optinteger(L, 3, 0);
    // luat_printf("timer id=%ld\n", id);
    // luat_printf("timer timeout=%ld\n", timeout);
    // luat_printf("timer repeat=%ld\n", repeat);
    if (timeout < 1) {
        lua_pushinteger(L, 0);
        return 1;
    }
    luat_timer_t *timer = (luat_timer_t*)luat_heap_malloc(sizeof(luat_timer_t));
    timer->id = id;
    timer->timeout = timeout;
    timer->repeat = repeat;
    timer->func = &l_timer_handler;

    luat_timer_start(timer);
    //lua_pushlightuserdata(L, timer);
    lua_pushinteger(L, 1);

    return 1;
}

static int l_rtos_timer_stop(lua_State *L) {
    if (lua_islightuserdata(L, 1)) {
        luat_timer_t *timer = (luat_timer_t *)lua_touserdata(L, 1);
        luat_timer_stop(timer);
        luat_heap_free(timer);
    }
    return 0;
}

static int l_rtos_reboot(lua_State *L) {
    rt_hw_cpu_reset();
}

//------------------------------------------------------------------
#include "rotable.h"
static const rotable_Reg reg_rtos[] =
{
    { "timer_start" ,      l_rtos_timer_start, 0},
    { "timer_stop",        l_rtos_timer_stop,  0},
    { "receive",           l_rtos_receive,     0},
    { "reboot",            l_rtos_reboot,      0},

    { "INF_TIMEOUT",        NULL,              -1},

    { "MSG_TIMER",          NULL,              MSG_TIMER},
    { "MSG_GPIO",           NULL,              MSG_GPIO},
    { "MSG_UART_RX",        NULL,              MSG_UART_RX},
    { "MSG_UART_TXDONE",    NULL,              MSG_UART_TXDONE},
	{ NULL,                 NULL,              0}
};

LUAMOD_API int luaopen_rtos( lua_State *L ) {
    rotable_newlib(L, reg_rtos);
    return 1;
}
