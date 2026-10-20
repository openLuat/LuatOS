/* SPDX-License-Identifier: MIT */
#include "luat_base.h"
#include "lua.h"
#include "lauxlib.h"
#include "luat_msgbus.h"
#include "luat_zenoh_pico.h"
#include <stdatomic.h>
#include <string.h>

#define SESSION "zenohpico.session"
#define QUERY "zenohpico.query"
typedef struct { uint32_t generation, next_id; int closed, subscription_count, get_count, queryable_count; } session_t;
typedef struct { uint32_t generation, token; int finished; } query_t;
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
    lua_getuservalue(L, -1);
    lua_newtable(L); lua_setfield(L, -2, "requests");
    lua_newtable(L); lua_setfield(L, -2, "queryables"); lua_pop(L, 1);
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
    return s->next_id + 1;
}
static int l_publish(lua_State *L) {
    session_t *s = check(L); const char *key = key_arg(L, 2);
    size_t n; const char *payload = luaL_checklstring(L, 3, &n);
    luaL_argcheck(L, n <= LUAT_ZP_PAYLOAD_MAX, 3, "payload too large");
    if (s->closed) return result(L, -8, 0);
    uint32_t id = next_id(L, s);
    int rc = luat_zenoh_pico_command(s->generation, LUAT_ZP_PUBLISH, id, key, payload, n);
    if (!rc) s->next_id = id;
    return result(L, rc, id);
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
    else { s->subscription_count++; s->next_id = id; }
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

static uint32_t positive_id(lua_State *L, int index) {
    lua_Integer id = luaL_checkinteger(L, index);
    luaL_argcheck(L, id > 0 && id <= UINT32_MAX, index, "id out of range");
    return (uint32_t)id;
}
static void callback_table(lua_State *L, const char *name) {
    lua_getuservalue(L, 1); lua_getfield(L, -1, name); lua_remove(L, -2);
}
static int l_get(lua_State *L) {
    session_t *s = check(L); const char *key = key_arg(L, 2);
    luaL_checktype(L, 3, LUA_TTABLE); luaL_checktype(L, 4, LUA_TFUNCTION); luaL_checktype(L, 5, LUA_TFUNCTION);
    if (s->closed) return result(L, -8, 0);
    if (s->get_count >= LUAT_ZP_GET_MAX) return result(L, -5, 0);
    lua_getfield(L, 3, "parameters"); size_t pn; const char *parameters = luaL_optlstring(L, -1, "", &pn);
    luaL_argcheck(L, pn <= LUAT_ZP_PARAMETERS_MAX && memchr(parameters, 0, pn) == NULL, 3, "invalid parameters");
    lua_getfield(L, 3, "payload"); size_t n; const char *payload = luaL_optlstring(L, -1, "", &n);
    luaL_argcheck(L, n <= LUAT_ZP_PAYLOAD_MAX, 3, "payload too large");
    lua_getfield(L, 3, "timeout_ms"); lua_Integer ms = luaL_optinteger(L, -1, 3000);
    luaL_argcheck(L, ms >= 100 && ms <= 10000, 3, "timeout out of range");
    uint32_t id = next_id(L, s);
    callback_table(L, "requests"); lua_newtable(L);
    lua_pushvalue(L, 4); lua_setfield(L, -2, "reply"); lua_pushvalue(L, 5); lua_setfield(L, -2, "done");
    lua_rawseti(L, -2, id);
    int rc = luat_zenoh_pico_command_ex(s->generation, LUAT_ZP_GET, id, key, payload, n, parameters, 0, (uint32_t)ms);
    if (rc) { lua_pushnil(L); lua_rawseti(L, -2, id); }
    else { s->next_id = id; s->get_count++; }
    return result(L, rc, id);
}
static int l_cancel_get(lua_State *L) {
    session_t *s = check(L); uint32_t id = positive_id(L, 2);
    if (s->closed) return result(L, -8, 0);
    callback_table(L, "requests"); lua_rawgeti(L, -1, id);
    if (!lua_istable(L, -1)) return result(L, -4, 0);
    return result(L, luat_zenoh_pico_command(s->generation, LUAT_ZP_CANCEL_GET, id, NULL, NULL, 0), id);
}
static int l_queryable(lua_State *L) {
    session_t *s = check(L); const char *key = key_arg(L, 2); luaL_checktype(L, 3, LUA_TFUNCTION);
    if (s->closed) return result(L, -8, 0);
    if (s->queryable_count >= LUAT_ZP_QUERY_MAX) return result(L, -5, 0);
    uint32_t id = next_id(L, s); callback_table(L, "queryables");
    lua_pushvalue(L, 3); lua_rawseti(L, -2, id);
    int rc = luat_zenoh_pico_command(s->generation, LUAT_ZP_QUERYABLE, id, key, NULL, 0);
    if (rc) { lua_pushnil(L); lua_rawseti(L, -2, id); }
    else { s->queryable_count++; s->next_id = id; }
    return result(L, rc, id);
}
static int l_unqueryable(lua_State *L) {
    session_t *s = check(L); uint32_t id = positive_id(L, 2);
    if (s->closed) return result(L, -8, 0);
    callback_table(L, "queryables"); lua_rawgeti(L, -1, id);
    if (!lua_isfunction(L, -1)) return result(L, -4, 0);
    lua_pop(L, 1);
    int rc = luat_zenoh_pico_command_ex(s->generation, LUAT_ZP_UNQUERYABLE, id, NULL, NULL, 0, NULL, id, 0);
    if (!rc) { lua_pushnil(L); lua_rawseti(L, -2, id); s->queryable_count--; }
    return result(L, rc, id);
}
static query_t *query_arg(lua_State *L, session_t *s) {
    query_t *q = luaL_checkudata(L, 2, QUERY);
    luaL_argcheck(L, q->generation == s->generation && !q->finished, 2, "expired/foreign query token");
    return q;
}
static int l_reply(lua_State *L) {
    session_t *s = check(L); query_t *q = query_arg(L, s); const char *key = key_arg(L, 3);
    size_t n; const char *payload = luaL_checklstring(L, 4, &n);
    luaL_argcheck(L, n <= LUAT_ZP_PAYLOAD_MAX, 4, "payload too large");
    if (s->closed) return result(L, -8, 0);
    uint32_t id = next_id(L, s);
    int rc = luat_zenoh_pico_command_ex(s->generation, LUAT_ZP_REPLY, id, key, payload, n, NULL, q->token, 0);
    if (!rc) s->next_id = id;
    return result(L, rc, id);
}
static int l_finish_reply(lua_State *L) {
    session_t *s = check(L); query_t *q = query_arg(L, s);
    if (s->closed) return result(L, -8, 0);
    uint32_t id = next_id(L, s);
    int rc = luat_zenoh_pico_command_ex(s->generation, LUAT_ZP_FINISH_QUERY, id, NULL, NULL, 0, NULL, q->token, 0);
    if (!rc) { s->next_id = id; q->finished = 1; }
    return result(L, rc, id);
}
static int l_query_gc(lua_State *L) {
    query_t *q = luaL_checkudata(L, 1, QUERY);
    if (!q->finished) luat_zenoh_pico_command_ex(q->generation, LUAT_ZP_FINISH_QUERY, 0, NULL, NULL, 0, NULL, q->token, 0);
    q->finished = 1; return 0;
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
    if (s->closed && strcmp(e->kind, "closed") && strcmp(e->kind, "get_done")) return 0;
    int handle = lua_gettop(L);
    lua_getuservalue(L, handle);
    if (!strcmp(e->kind, "error") && e->id) {
        lua_getfield(L, -1, "subscribers"); lua_rawgeti(L, -1, e->id);
        int exists = lua_isfunction(L, -1); lua_pop(L, 1);
        if (exists) { lua_pushnil(L); lua_rawseti(L, -2, e->id); s->subscription_count--; }
        lua_pop(L, 1);
    }
    if (!strcmp(e->kind, "error") && e->id) {
        lua_getfield(L, -1, "queryables"); lua_rawgeti(L, -1, e->id);
        int exists = lua_isfunction(L, -1); lua_pop(L, 1);
        if (exists) { lua_pushnil(L); lua_rawseti(L, -2, e->id); s->queryable_count--; }
        lua_pop(L, 1);
    }
    if (e->request) {
        lua_getfield(L, -1, "requests"); lua_rawgeti(L, -1, e->request);
        if (!lua_istable(L, -1)) return 0;
        lua_getfield(L, -1, !strcmp(e->kind, "get_done") ? "done" : "reply");
        if (!strcmp(e->kind, "get_done")) {
            lua_pushnil(L); lua_rawseti(L, -4, e->request); s->get_count--;
        }
    } else if (!strcmp(e->kind, "query")) {
        lua_getfield(L, -1, "queryables"); lua_rawgeti(L, -1, e->queryable);
    } else if (e->subscriber) {
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
    lua_pushinteger(L, e->request); lua_setfield(L, -2, "request_id");
    lua_pushinteger(L, e->queryable); lua_setfield(L, -2, "queryable_id");
    lua_pushinteger(L, e->query); lua_setfield(L, -2, "query_id");
    if (e->reason) { lua_pushstring(L, e->reason); lua_setfield(L, -2, "reason"); }
    if (!strcmp(e->kind, "query")) {
        query_t *q = lua_newuserdata(L, sizeof(*q)); q->generation = e->generation; q->token = e->query; q->finished = 0;
        luaL_setmetatable(L, QUERY); lua_setfield(L, -2, "query");
        lua_pushlstring(L, e->parameters, e->parameters_len); lua_setfield(L, -2, "parameters");
    }
    if (e->subscriber || !strcmp(e->kind, "query") || !strcmp(e->kind, "get_reply")) {
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
    {"state", l_state}, {"poll", l_poll},
    {"get", l_get}, {"cancel_get", l_cancel_get}, {"queryable", l_queryable},
    {"unqueryable", l_unqueryable}, {"reply", l_reply}, {"finish_reply", l_finish_reply}, {NULL, NULL}
};
int luaopen_zenohpico(lua_State *L) {
    if (luaL_newmetatable(L, QUERY)) { lua_pushcfunction(L, l_query_gc); lua_setfield(L, -2, "__gc"); }
    lua_pop(L, 1);
    if (luaL_newmetatable(L, SESSION)) {
        lua_pushcfunction(L, l_gc); lua_setfield(L, -2, "__gc");
    }
    lua_pop(L, 1);
    lua_newtable(L); lua_newtable(L); lua_pushliteral(L, "v"); lua_setfield(L, -2, "__mode");
    lua_setmetatable(L, -2); lua_rawsetp(L, LUA_REGISTRYINDEX, &sessions_key);
    luaL_newlib(L, functions);
    lua_pushliteral(L, "1.9.0"); lua_setfield(L, -2, "version");
    lua_pushinteger(L, LUAT_ZP_PAYLOAD_MAX); lua_setfield(L, -2, "MAX_PAYLOAD");
    lua_pushliteral(L, "local"); lua_setfield(L, -2, "GET_CANCEL_MODE");
    lua_pushinteger(L, LUAT_ZP_GET_MAX); lua_setfield(L, -2, "MAX_GET_REQUESTS");
    lua_pushinteger(L, LUAT_ZP_QUERY_MAX); lua_setfield(L, -2, "MAX_QUERYABLES");
    lua_pushinteger(L, LUAT_ZP_ONLINE); lua_setfield(L, -2, "ONLINE");
    lua_pushinteger(L, LUAT_ZP_CLOSED); lua_setfield(L, -2, "CLOSED");
    return 1;
}
