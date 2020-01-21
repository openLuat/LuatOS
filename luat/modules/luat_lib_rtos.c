
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
        luat_printf("luat_msgbus_get!!!\n");
        return msg.handler(L, &msg);
    }
    else {
        luat_printf("timeout!!!\n");
        lua_pushinteger(L, -1);
        return 1;
    }
}

//------------------------------------------------------------------
static int l_timer_handler(lua_State *L, void* ptr) {
    luat_printf("l_timer_handler\n");
    struct luat_timer_t *timer = (struct luat_timer_t *)ptr;
    lua_pushinteger(L, MSG_TIMER);
    lua_pushinteger(L, timer->id);
    lua_pushinteger(L, timer->timeout);
    lua_pushinteger(L, timer->repeat);
    if (timer->repeat == 0) {
        //luat_timer_stop(timer);
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
//------------------------------------------------------------------

static const luaL_Reg reg_rtos[] =
{
    { "timer_start" , l_rtos_timer_start},
    { "timer_stop",   l_rtos_timer_stop},
    { "receive",      l_rtos_receive},
    { "on",           NULL},

    { "INF_TIMEOUT",        NULL},

    { "MSG_TIMER",          NULL},
    { "MSG_GPIO",           NULL},
    { "MSG_UART_RX",        NULL},
    { "MSG_UART_TXDONE",    NULL},
	{ NULL, NULL }
};

LUAMOD_API int luaopen_rtos( lua_State *L ) {
    luaL_newlib(L, reg_rtos);

    // timeout
    lua_pushnumber(L, -1);
    lua_setfield(L, -2, "INF_TIMEOUT");

    // MSG 
    lua_pushnumber(L, MSG_TIMER);
    lua_setfield(L, -2, "MSG_TIMER");
    lua_pushnumber(L, MSG_GPIO);
    lua_setfield(L, -2, "MSG_GPIO");
    lua_pushnumber(L, MSG_UART_RX);
    lua_setfield(L, -2, "MSG_UART_RX");
    lua_pushnumber(L, MSG_UART_TXDONE);
    lua_setfield(L, -2, "MSG_UART_TXDONE");
    return 1;
}
