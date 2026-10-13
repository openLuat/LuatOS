/* SPDX-License-Identifier: MIT */
#include "luat_base.h"
#include "lua.h"
#include "lauxlib.h"
#include "luat_msgbus.h"
#include "luat_zenoh_pico.h"
#include <stdatomic.h>
#include <string.h>

#define SESSION "zenohpico.session"
typedef struct { uint32_t generation, next_id; int closed, subscription_count; } session_t;
static char sessions_key;
static atomic_uint wake_pending;
static uint32_t callback_errors;
static int poll_events(lua_State *L);

/* msgbus中只有唤醒信号，不携带可能释放的Lua userdata或控制块。 */
static int on_wake(lua_State *L, void *unused) {
    (void)unused;
    atomic_store(&wake_pending, 0);
    poll_events(L);
    return 0;
}
void luat_zenoh_pico_wake(void) {
    unsigned expected = 0;
    if (!atomic_compare_exchange_strong(&wake_pending, &expected, 1)) return;
    rtos_msg_t message = {0}; message.handler = on_wake;
    if (luat_msgbus_put(&message, 0) != 0) atomic_store(&wake_pending, 0);
}
static int result(lua_State *L, int rc, uint32_t id) {
    if (rc) { lua_pushnil(L); lua_pushinteger(L, rc); return 2; }
    lua_pushinteger(L, id); return 1;
}
static session_t *check(lua_State *L) { return luaL_checkudata(L, 1, SESSION); }
static const char *key_arg(lua_State *L, int index) {
    size_t n; const char *key = luaL_checklstring(L, index, &n);
    luaL_argcheck(L, n > 0 && n <= LUAT_ZP_KEY_MAX && memchr(key, 0, n) == NULL, index, "invalid key length/NUL");
    return key;
}

/* 弱值表允许用户释放句柄后触发GC，不以注册表强引用延长会话生命。 */
static int l_open(lua_State *L) {
    size_t n; const char *endpoint = luaL_checklstring(L, 1, &n);
    luaL_argcheck(L, n == strlen(endpoint), 1, "endpoint contains NUL");
    lua_Integer adapter = luaL_checkinteger(L, 2);
    luaL_argcheck(L, adapter >= 0 && adapter <= 126, 2, "adapter out of range");
    luaL_checktype(L, 3, LUA_TFUNCTION);
    session_t *s = lua_newuserdata(L, sizeof(*s)); memset(s, 0, sizeof(*s));
    s->closed = 1;
    luaL_setmetatable(L, SESSION);
    lua_newtable(L); lua_pushvalue(L, 3); lua_setfield(L, -2, "callback");
    lua_newtable(L); lua_setfield(L, -2, "subscribers"); lua_setuservalue(L, -2);
    /* 先建立Lua所有权，任何后续Lua分配失败都可由__gc撤销。 */
    uint32_t gen;
    int rc = luat_zenoh_pico_open(endpoint, (int)adapter, &gen);
    if (rc) { lua_pop(L, 1); return result(L, rc, 0); }
    s->generation = gen; s->closed = 0;
    lua_rawgetp(L, LUA_REGISTRYINDEX, &sessions_key);
    lua_pushvalue(L, -2); lua_rawseti(L, -2, gen); lua_pop(L, 1);
    return 1;
}
static int l_close(lua_State *L) {
    session_t *s = check(L);
    if (!s->closed) { s->closed = 1; luat_zenoh_pico_close(s->generation); }
    lua_pushboolean(L, 1); return 1;
}
static int l_gc(lua_State *L) {
    session_t *s = check(L);
    if (!s->closed) luat_zenoh_pico_close(s->generation);
    s->closed = 1;
    return 0;
}
static uint32_t next_id(lua_State *L, session_t *s) {
    if (s->next_id == UINT32_MAX) luaL_error(L, "command id exhausted");
    return ++s->next_id;
}
static int l_publish(lua_State *L) {
    session_t *s = check(L); const char *key = key_arg(L, 2);
    size_t n; const char *payload = luaL_checklstring(L, 3, &n);
    luaL_argcheck(L, n <= LUAT_ZP_PAYLOAD_MAX, 3, "payload too large");
    if (s->closed) return result(L, -8, 0);
    uint32_t id = next_id(L, s);
    return result(L, luat_zenoh_pico_command(s->generation, LUAT_ZP_PUBLISH, id, key, payload, n), id);
}
static int l_subscribe(lua_State *L) {
    session_t *s = check(L); const char *key = key_arg(L, 2);
    luaL_checktype(L, 3, LUA_TFUNCTION);
    if (s->subscription_count >= LUAT_ZP_SUB_MAX) return result(L, -5, 0);
    if (s->closed) return result(L, -8, 0);
    uint32_t id = next_id(L, s);
    lua_getuservalue(L, 1); lua_getfield(L, -1, "subscribers");
    lua_pushvalue(L, 3); lua_rawseti(L, -2, id);
    int rc = luat_zenoh_pico_command(s->generation, LUAT_ZP_SUBSCRIBE, id, key, NULL, 0);
    if (rc) { lua_pushnil(L); lua_rawseti(L, -2, id); }
    else s->subscription_count++;
    lua_pop(L, 2);
    return result(L, rc, id);
}
static int l_unsubscribe(lua_State *L) {
    session_t *s = check(L);
    lua_Integer number = luaL_checkinteger(L, 2);
    luaL_argcheck(L, number > 0 && number <= UINT32_MAX, 2, "invalid subscriber id");
    if (s->closed) return result(L, -8, 0);
    lua_getuservalue(L, 1); lua_getfield(L, -1, "subscribers"); lua_rawgeti(L, -1, number);
    int exists = lua_isfunction(L, -1); lua_pop(L, 3);
    if (!exists) return result(L, -4, 0);
    int rc = luat_zenoh_pico_command(s->generation, LUAT_ZP_UNSUBSCRIBE, (uint32_t)number, NULL, NULL, 0);
    if (!rc) {
        lua_getuservalue(L, 1); lua_getfield(L, -1, "subscribers");
        lua_pushnil(L); lua_rawseti(L, -2, number); lua_pop(L, 2); s->subscription_count--;
    }
    return result(L, rc, (uint32_t)number);
}
static int l_state(lua_State *L) {
    session_t *s = check(L);
    lua_pushinteger(L, luat_zenoh_pico_state(s->generation));
    lua_pushinteger(L, luat_zenoh_pico_dropped());
    lua_pushinteger(L, callback_errors);
    return 3;
}

/* 翻译与用户回调都位于pcall内，Lua内存错误也不会泄漏C事件。 */
static int dispatch(lua_State *L) {
    luat_zp_event_t *e = lua_touserdata(L, 1);
    lua_rawgetp(L, LUA_REGISTRYINDEX, &sessions_key); lua_rawgeti(L, -1, e->generation);
    session_t *s = luaL_testudata(L, -1, SESSION);
    if (!s || s->generation != e->generation) return 0;
    if (s->closed && strcmp(e->kind, "closed")) return 0;
    int handle = lua_gettop(L);
    lua_getuservalue(L, handle);
    if (!strcmp(e->kind, "error") && e->id) {
        lua_getfield(L, -1, "subscribers"); lua_rawgeti(L, -1, e->id);
        int exists = lua_isfunction(L, -1); lua_pop(L, 1);
        if (exists) { lua_pushnil(L); lua_rawseti(L, -2, e->id); s->subscription_count--; }
        lua_pop(L, 1);
    }
    if (e->subscriber) {
        lua_getfield(L, -1, "subscribers"); lua_rawgeti(L, -1, e->subscriber);
    } else {
        lua_getfield(L, -1, "callback");
    }
    if (!lua_isfunction(L, -1)) return 0;
    lua_pushvalue(L, handle);
    lua_newtable(L);
    lua_pushstring(L, e->kind); lua_setfield(L, -2, "kind");
    lua_pushinteger(L, e->id); lua_setfield(L, -2, "id");
    lua_pushinteger(L, e->code); lua_setfield(L, -2, "code");
    lua_pushinteger(L, e->subscriber); lua_setfield(L, -2, "subscriber");
    if (e->subscriber) {
        lua_pushstring(L, e->operation); lua_setfield(L, -2, "operation");
        lua_pushlstring(L, e->key, e->key_len); lua_setfield(L, -2, "key");
        lua_pushlstring(L, (const char *)e->payload, e->payload_len); lua_setfield(L, -2, "payload");
    }
    if (!strcmp(e->kind, "closed")) s->closed = 1;
    lua_call(L, 2, 0);
    return 0;
}
static int poll_events(lua_State *L) {
    int top = lua_gettop(L), count = 0;
    luat_zp_event_t *e;
    while (count < 8 && luat_zenoh_pico_pop(&e) == 0) {
        lua_pushcfunction(L, dispatch); lua_pushlightuserdata(L, e);
        if (lua_pcall(L, 1, 0, 0) != LUA_OK) { lua_pop(L, 1); callback_errors++; }
        luat_zenoh_pico_event_free(e); count++;
    }
    lua_settop(L, top);
    return count;
}
static int l_poll(lua_State *L) { lua_pushinteger(L, poll_events(L)); return 1; }
static const luaL_Reg functions[] = {
    {"open", l_open}, {"close", l_close}, {"publish", l_publish},
    {"subscribe", l_subscribe}, {"unsubscribe", l_unsubscribe},
    {"state", l_state}, {"poll", l_poll}, {NULL, NULL}
};
int luaopen_zenohpico(lua_State *L) {
    if (luaL_newmetatable(L, SESSION)) {
        lua_pushcfunction(L, l_gc); lua_setfield(L, -2, "__gc");
    }
    lua_pop(L, 1);
    lua_newtable(L); lua_newtable(L); lua_pushliteral(L, "v"); lua_setfield(L, -2, "__mode");
    lua_setmetatable(L, -2); lua_rawsetp(L, LUA_REGISTRYINDEX, &sessions_key);
    luaL_newlib(L, functions);
    lua_pushliteral(L, "1.9.0"); lua_setfield(L, -2, "version");
    lua_pushinteger(L, LUAT_ZP_PAYLOAD_MAX); lua_setfield(L, -2, "MAX_PAYLOAD");
    lua_pushinteger(L, LUAT_ZP_ONLINE); lua_setfield(L, -2, "ONLINE");
    lua_pushinteger(L, LUAT_ZP_CLOSED); lua_setfield(L, -2, "CLOSED");
    return 1;
}
