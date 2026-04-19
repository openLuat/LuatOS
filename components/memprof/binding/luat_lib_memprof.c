#include "luat_base.h"
#include "luat_memprof.h"
#include "lstate.h"   /* G(L), global_State */

#define LUAT_LOG_TAG "memprof"
#include "luat_log.h"

/* Push a stat sub-table {count=N, bytes=N} and set it as t[key] */
static void push_stat(lua_State *L, const char *key, const luat_memprof_stat_t *st) {
    lua_newtable(L);
    lua_pushinteger(L, st->count);
    lua_setfield(L, -2, "count");
    lua_pushinteger(L, (lua_Integer)st->bytes);
    lua_setfield(L, -2, "bytes");
    lua_setfield(L, -2, key);
}

/*
 * memprof.snapshot() -> table
 * Returns a snapshot table:
 *   { str_short={count,bytes}, str_long={count,bytes}, table={count,bytes},
 *     proto={count,bytes}, lclosure={count,bytes}, cclosure={count,bytes},
 *     udata={count,bytes}, thread={count,bytes}, total_bytes=N }
 */
static int l_memprof_snapshot(lua_State *L) {
    luat_memprof_snapshot_t snap;
    luat_memprof_snapshot(L, &snap);

    lua_newtable(L);
    push_stat(L, "str_short", &snap.str_short);
    push_stat(L, "str_long",  &snap.str_long);
    push_stat(L, "table",     &snap.table);
    push_stat(L, "proto",     &snap.proto);
    push_stat(L, "lclosure",  &snap.lclosure);
    push_stat(L, "cclosure",  &snap.cclosure);
    push_stat(L, "udata",     &snap.udata);
    push_stat(L, "thread",    &snap.thread);
    lua_pushinteger(L, (lua_Integer)snap.total_bytes);
    lua_setfield(L, -2, "total_bytes");
    return 1;
}

/*
 * memprof.dump() -> nil
 * Prints a human-readable memory report to the log.
 */
static int l_memprof_dump(lua_State *L) {
    luat_memprof_dump(L);
    return 0;
}

/*
 * memprof.diff(snap_a, snap_b) -> table
 * Compares two snapshots and returns a delta table:
 *   { str_short={count_delta,bytes_delta}, ..., total_bytes_delta=N }
 * snap_b - snap_a (positive means growth).
 */
static int l_memprof_diff(lua_State *L) {
    luaL_checktype(L, 1, LUA_TTABLE);
    luaL_checktype(L, 2, LUA_TTABLE);

    static const char *keys[] = {
        "str_short", "str_long", "table", "proto",
        "lclosure", "cclosure", "udata", "thread", NULL
    };

    lua_newtable(L);  /* result */

    for (int i = 0; keys[i]; i++) {
        /* read count/bytes from snap_a (arg 1) */
        lua_getfield(L, 1, keys[i]);
        lua_getfield(L, -1, "count"); lua_Integer ca = luaL_optinteger(L, -1, 0); lua_pop(L, 1);
        lua_getfield(L, -1, "bytes"); lua_Integer ba = luaL_optinteger(L, -1, 0); lua_pop(L, 1);
        lua_pop(L, 1);

        /* read count/bytes from snap_b (arg 2) */
        lua_getfield(L, 2, keys[i]);
        lua_getfield(L, -1, "count"); lua_Integer cb = luaL_optinteger(L, -1, 0); lua_pop(L, 1);
        lua_getfield(L, -1, "bytes"); lua_Integer bb = luaL_optinteger(L, -1, 0); lua_pop(L, 1);
        lua_pop(L, 1);

        lua_newtable(L);
        lua_pushinteger(L, cb - ca); lua_setfield(L, -2, "count_delta");
        lua_pushinteger(L, bb - ba); lua_setfield(L, -2, "bytes_delta");
        lua_setfield(L, -2, keys[i]);
    }

    /* total_bytes delta */
    lua_getfield(L, 1, "total_bytes"); lua_Integer ta = luaL_optinteger(L, -1, 0); lua_pop(L, 1);
    lua_getfield(L, 2, "total_bytes"); lua_Integer tb = luaL_optinteger(L, -1, 0); lua_pop(L, 1);
    lua_pushinteger(L, tb - ta);
    lua_setfield(L, -2, "total_bytes_delta");

    return 1;
}

/*
 * memprof.total() -> number
 * Returns the total bytes tracked by the Lua GC (totalbytes + GCdebt).
 */
static int l_memprof_total(lua_State *L) {
    global_State *g = G(L);
    lua_Integer total = (lua_Integer)(g->totalbytes + g->GCdebt);
    lua_pushinteger(L, total);
    return 1;
}

#include "rotable2.h"
static const rotable_Reg_t reg_memprof[] = {
    { "snapshot", ROREG_FUNC(l_memprof_snapshot) },
    { "dump",     ROREG_FUNC(l_memprof_dump)     },
    { "diff",     ROREG_FUNC(l_memprof_diff)     },
    { "total",    ROREG_FUNC(l_memprof_total)    },
    { NULL, ROREG_FUNC(NULL) }
};

LUAMOD_API int luaopen_memprof(lua_State *L) {
    luat_newlib2(L, reg_memprof);
    return 1;
}


