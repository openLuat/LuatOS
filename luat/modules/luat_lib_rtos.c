
#include "luat_base.h"
#include "luat_log.h"
#include "luat_sys.h"
#include "luat_msgbus.h"
#include "luat_timer.h"


//------------------------------------------------------------------
static int l_rtos_receive(lua_State *L) {
    struct rtos_msg msg;
    int re;
    re = luat_msgbus_get(&msg, luaL_checkinteger(L, 1));
    if (!re) {
        luat_print("luat_msgbus_get msg!!!\n");
        return msg.handler(L, &msg);
    }
    else {
        luat_print("luat_msgbus_get timeout!!!\n");
        lua_pushinteger(L, -1);
        return 1;
    }
}

//------------------------------------------------------------------
static int l_timer_handler(lua_State *L, void* ptr) {
    luat_print("l_timer_handler\n");
    struct luat_timer_t *timer = (struct luat_timer_t *)ptr;
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
    lua_Integer id = luaL_checkinteger(L, 1);
    lua_Integer timeout = luaL_checkinteger(L, 2);
    lua_Integer repeat = luaL_optinteger(L, 3, 0);
    //luat_printf("timer id=%lld ms=%lld repeat=%lld\n", id, ms, repeat);
    if (timeout < 1)
        return 0;
    struct luat_timer_t *timer = (struct luat_timer_t *)luat_heap_malloc(sizeof(struct luat_timer_t));
    timer->id = id;
    timer->timeout = timeout;
    timer->repeat = repeat;
    timer->func = &l_timer_handler;

    luat_timer_start(timer);
    lua_pushlightuserdata(L, timer);

    return 1;
}

static int l_rtos_timer_stop(lua_State *L) {
    if (lua_islightuserdata(L, 1)) {
        struct luat_timer_t *timer = (struct luat_timer_t *)lua_touserdata(L, 1);
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
    { "timer_start" ,      l_rtos_timer_start, NULL},
    { "timer_stop",        l_rtos_timer_stop,  NULL},
    { "receive",           l_rtos_receive,     NULL},
    { "reboot",            l_rtos_reboot,      NULL},

    { "INF_TIMEOUT",        NULL,              -1},

    { "MSG_TIMER",          NULL,              MSG_TIMER},
    { "MSG_GPIO",           NULL,              MSG_GPIO},
    { "MSG_UART_RX",        NULL,              MSG_UART_RX},
    { "MSG_UART_TXDONE",    NULL,              MSG_UART_TXDONE},
	{ NULL,                 NULL,              NULL}
};

LUAMOD_API int luaopen_rtos( lua_State *L ) {
    rotable_newlib(L, reg_rtos);
    return 1;
}
