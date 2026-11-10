/* SPDX-License-Identifier: MIT */
#include "luat_base.h"
#include "lua.h"
#include "lauxlib.h"
#include "lualib.h"
#include "luat_msgbus.h"
#include "luat_rtos.h"
#include "zenoh-pico/session/query.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
extern int host_race_arm(int point);
extern int host_race_arrived(void);
extern void host_race_release(void);
extern int host_race_closed(void);
extern unsigned host_race_command_id(void);
extern unsigned host_race_command_op(void);
static int race_command(lua_State *L) {
    lua_pushinteger(L, host_race_command_id()); lua_pushinteger(L, host_race_command_op()); return 2;
}
/* 真实Lua分配器连续拒绝初次申请与GC后的重试，不伪造模块事件。 */
static size_t lua_fail_size;
static unsigned lua_fail_remaining, lua_fail_count;
static int lua_fail_terminal;
static lua_Alloc original_lua_alloc;
static void *original_lua_ud;
static void *test_lua_alloc(void *ud, void *ptr, size_t old, size_t n) {
    (void)ud;
    if (n && lua_fail_remaining && (!lua_fail_size || (n >= lua_fail_size && n < lua_fail_size + 128))) {
        --lua_fail_remaining; ++lua_fail_count; return NULL;
    }
    return original_lua_alloc(original_lua_ud, ptr, old, n);
}
static int fail_lua(lua_State *L) {
    lua_fail_size = (size_t)luaL_checkinteger(L, 1); lua_fail_remaining = 2; lua_fail_count = 0; return 0;
}
static int fail_lua_count(lua_State *L) { lua_pushinteger(L, lua_fail_count); return 1; }
static int fail_terminal(lua_State *L) { (void)L; lua_fail_terminal = 1; lua_fail_count = 0; return 0; }
void luat_zp_test_dispatch(const char *kind) {
    if (lua_fail_terminal && !strcmp(kind, "get_done")) {
        lua_fail_terminal = 0; lua_fail_size = 0; lua_fail_remaining = 2;
    }
}
static int race_arm(lua_State *L) { lua_pushboolean(L, host_race_arm((int)luaL_checkinteger(L, 1)) == 0); return 1; }
static int race_arrived(lua_State *L) { lua_pushboolean(L, host_race_arrived()); return 1; }
static int race_release(lua_State *L) { (void)L; host_race_release(); return 0; }
static int race_closed(lua_State *L) { lua_pushboolean(L, host_race_closed()); return 1; }
int luaopen_zenohpico(lua_State *L);
int host_message(rtos_msg_t *out);
long host_allocations(void);
size_t host_allocation_bytes(void);
size_t host_allocation_peak(void);
void host_fail_rx_payload(size_t n);
static int heap_stats(lua_State *L) {
    lua_pushinteger(L, (lua_Integer)host_allocation_bytes());
    lua_pushinteger(L, (lua_Integer)host_allocation_peak()); return 2;
}
static int fail_rx(lua_State *L) { host_fail_rx_payload((size_t)luaL_checkinteger(L, 1)); return 0; }
void host_fail_after(long n);
static void pending_query_dropped(void *arg) { ++*(unsigned *)arg; }
static int pending_query_oom(lua_State *L) {
    int occupied = lua_toboolean(L, 1);
    _z_session_t session = {0};
    unsigned drops = 0;
    _z_pending_query_t *existing = NULL;
    if (occupied) {
        existing = _z_unsafe_register_pending_query(&session);
        if (!existing) return luaL_error(L, "fixture allocation failed");
        memset(existing, 0, sizeof(*existing));
        existing->_dropper = pending_query_dropped;
        existing->_arg = &drops;
    }
    _z_pending_query_slist_t *head = session._pending_queries;
    _z_zint_t next_id = session._query_id;
    _z_zint_t existing_id = existing ? existing->_id : 0;
    /* 下一次申请就是实际SDK链表节点，不依赖整条z_get的分配顺序。 */
    host_fail_after(0);
    _z_pending_query_t *failed = _z_unsafe_register_pending_query(&session);
    int preserved = !failed && session._pending_queries == head && session._query_id == next_id &&
        (!existing || (existing->_id == existing_id && existing->_dropper == pending_query_dropped &&
                       existing->_arg == &drops)) && drops == 0;
    _z_pending_query_slist_free(&session._pending_queries);
    if (!preserved || drops != (unsigned)occupied) return luaL_error(L, "pending Get changed on OOM");
    return 0;
}
int host_disconnect(void);
unsigned host_short_reads(void);
unsigned host_short_writes(void);
unsigned host_rx_bytes(void);
unsigned host_tx_bytes(void);
unsigned host_sample_entries(void);
void host_network_chunks(unsigned read_size, unsigned write_size);
static int network_chunks(lua_State *L) {
    lua_Integer r = luaL_checkinteger(L, 1), w = luaL_checkinteger(L, 2);
    luaL_argcheck(L, r > 0 && r < 2048 && w > 0 && w < 2048, 1, "invalid short I/O sizes");
    host_network_chunks((unsigned)r, (unsigned)w); return 0;
}
void host_write_failure_after(int n);
void host_write_release(void);
unsigned host_writes_after_fault(void);
unsigned host_failure_bytes(void);
static int write_failure(lua_State *L) { host_write_failure_after((int)luaL_checkinteger(L, 1)); return 0; }
static int write_release(lua_State *L) { (void)L; host_write_release(); return 0; }
static int failure_stats(lua_State *L) {
    lua_pushinteger(L, host_failure_bytes()); lua_pushinteger(L, host_writes_after_fault()); return 2;
}
static int disconnect_socket(lua_State *L) { lua_pushboolean(L, host_disconnect() == 0); return 1; }
static int network_stats(lua_State *L) {
    lua_pushinteger(L, host_short_reads()); lua_pushinteger(L, host_short_writes());
    lua_pushinteger(L, host_rx_bytes()); lua_pushinteger(L, host_tx_bytes());
    lua_pushinteger(L, host_sample_entries()); return 5;
}
static int pump(lua_State *L) {
    lua_Integer ms = luaL_optinteger(L, 1, 1);
    luaL_argcheck(L, ms >= 0 && ms <= 10000, 1, "invalid wait");
    for (lua_Integer i = 0; i <= ms; ++i) {
        rtos_msg_t message;
        int budget = 8;
        while (budget-- && host_message(&message)) {
            int top = lua_gettop(L); lua_pushlightuserdata(L, &message);
            message.handler(L, &message); lua_settop(L, top);
        }
        if (i < ms) luat_rtos_task_sleep(1);
    }
    return 0;
}
static int allocated(lua_State *L) { lua_pushinteger(L, host_allocations()); return 1; }
static int failure(lua_State *L) { host_fail_after(luaL_checkinteger(L, 1)); return 0; }
static int sleep_without_pump(lua_State *L) { luat_rtos_task_sleep((uint32_t)luaL_checkinteger(L, 1)); return 0; }
int main(int argc, char **argv) {
    if (argc != 4) { fprintf(stderr, "usage: host_test test.lua endpoint prefix\n"); return 2; }
    lua_State *L = luaL_newstate(); if (!L) return 2;
    original_lua_alloc = lua_getallocf(L, &original_lua_ud); lua_setallocf(L, test_lua_alloc, NULL);
    luaL_openlibs(L); luaL_requiref(L, "zenohpico", luaopen_zenohpico, 1); lua_pop(L, 1);
    lua_pushcfunction(L, pump); lua_setglobal(L, "host_pump");
    lua_pushcfunction(L, race_arm); lua_setglobal(L, "host_race_arm");
    lua_pushcfunction(L, race_arrived); lua_setglobal(L, "host_race_arrived");
    lua_pushcfunction(L, race_release); lua_setglobal(L, "host_race_release");
    lua_pushcfunction(L, race_closed); lua_setglobal(L, "host_race_closed");
    lua_pushcfunction(L, race_command); lua_setglobal(L, "host_race_command");
    lua_pushcfunction(L, fail_lua); lua_setglobal(L, "host_fail_lua_payload");
    lua_pushcfunction(L, fail_lua_count); lua_setglobal(L, "host_lua_failures");
    lua_pushcfunction(L, fail_terminal); lua_setglobal(L, "host_fail_lua_terminal");
    lua_pushcfunction(L, allocated); lua_setglobal(L, "host_allocations");
    lua_pushcfunction(L, heap_stats); lua_setglobal(L, "host_heap_stats");
    lua_pushcfunction(L, fail_rx); lua_setglobal(L, "host_fail_rx_payload");
    lua_pushcfunction(L, failure); lua_setglobal(L, "host_fail_after");
    lua_pushcfunction(L, pending_query_oom); lua_setglobal(L, "host_pending_query_oom");
    lua_pushcfunction(L, sleep_without_pump); lua_setglobal(L, "host_sleep");
    lua_pushcfunction(L, disconnect_socket); lua_setglobal(L, "host_disconnect");
    lua_pushcfunction(L, network_stats); lua_setglobal(L, "host_network_stats");
    lua_pushcfunction(L, network_chunks); lua_setglobal(L, "host_network_chunks");
    lua_pushcfunction(L, write_failure); lua_setglobal(L, "host_write_failure_after");
    lua_pushcfunction(L, write_release); lua_setglobal(L, "host_write_release");
    lua_pushcfunction(L, failure_stats); lua_setglobal(L, "host_write_failure_stats");
    lua_pushstring(L, argv[2]); lua_setglobal(L, "ENDPOINT");
    lua_pushstring(L, argv[3]); lua_setglobal(L, "PREFIX");
    int rc = luaL_dofile(L, argv[1]);
    if (rc) fprintf(stderr, "%s\n", lua_tostring(L, -1));
    lua_close(L); return rc ? 1 : 0;
}
