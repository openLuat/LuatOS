/* SPDX-License-Identifier: MIT */
#include "luat_base.h"
#include "lua.h"
#include "lauxlib.h"
#include "lualib.h"
#include "luat_msgbus.h"
#include "luat_rtos.h"
#include <stdio.h>
#include <stdlib.h>
extern int host_race_arm(int point);
extern int host_race_arrived(void);
extern void host_race_release(void);
extern int host_race_closed(void);
static int race_arm(lua_State *L) { lua_pushboolean(L, host_race_arm((int)luaL_checkinteger(L, 1)) == 0); return 1; }
static int race_arrived(lua_State *L) { lua_pushboolean(L, host_race_arrived()); return 1; }
static int race_release(lua_State *L) { (void)L; host_race_release(); return 0; }
static int race_closed(lua_State *L) { lua_pushboolean(L, host_race_closed()); return 1; }
int luaopen_zenohpico(lua_State *L);
int host_message(rtos_msg_t *out);
long host_allocations(void);
void host_fail_after(long n);
int host_disconnect(void);
unsigned host_short_reads(void);
unsigned host_short_writes(void);
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
    lua_pushinteger(L, host_short_reads()); lua_pushinteger(L, host_short_writes()); return 2;
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
    luaL_openlibs(L); luaL_requiref(L, "zenohpico", luaopen_zenohpico, 1); lua_pop(L, 1);
    lua_pushcfunction(L, pump); lua_setglobal(L, "host_pump");
    lua_pushcfunction(L, race_arm); lua_setglobal(L, "host_race_arm");
    lua_pushcfunction(L, race_arrived); lua_setglobal(L, "host_race_arrived");
    lua_pushcfunction(L, race_release); lua_setglobal(L, "host_race_release");
    lua_pushcfunction(L, race_closed); lua_setglobal(L, "host_race_closed");
    lua_pushcfunction(L, allocated); lua_setglobal(L, "host_allocations");
    lua_pushcfunction(L, failure); lua_setglobal(L, "host_fail_after");
    lua_pushcfunction(L, sleep_without_pump); lua_setglobal(L, "host_sleep");
    lua_pushcfunction(L, disconnect_socket); lua_setglobal(L, "host_disconnect");
    lua_pushcfunction(L, network_stats); lua_setglobal(L, "host_network_stats");
    lua_pushcfunction(L, write_failure); lua_setglobal(L, "host_write_failure_after");
    lua_pushcfunction(L, write_release); lua_setglobal(L, "host_write_release");
    lua_pushcfunction(L, failure_stats); lua_setglobal(L, "host_write_failure_stats");
    lua_pushstring(L, argv[2]); lua_setglobal(L, "ENDPOINT");
    lua_pushstring(L, argv[3]); lua_setglobal(L, "PREFIX");
    int rc = luaL_dofile(L, argv[1]);
    if (rc) fprintf(stderr, "%s\n", lua_tostring(L, -1));
    lua_close(L); return rc ? 1 : 0;
}
