#ifndef LUAT_MEMPROF_H
#define LUAT_MEMPROF_H

#include "lua.h"
#include <stddef.h>

/* Per-type memory statistics */
typedef struct {
    int    count;
    size_t bytes;
} luat_memprof_stat_t;

/* Snapshot: memory usage broken down by Lua object type */
typedef struct {
    luat_memprof_stat_t str_short;  /* short strings (interned) */
    luat_memprof_stat_t str_long;   /* long strings */
    luat_memprof_stat_t table;      /* tables */
    luat_memprof_stat_t proto;      /* function prototypes */
    luat_memprof_stat_t lclosure;   /* Lua closures */
    luat_memprof_stat_t cclosure;   /* C closures */
    luat_memprof_stat_t udata;      /* full userdata */
    luat_memprof_stat_t thread;     /* coroutines / lua_State */
    size_t              total_bytes; /* sum of all above */
} luat_memprof_snapshot_t;

/*
 * Walk the GC lists (allgc + fixedgc) of the Lua state and fill *out.
 * Safe to call at any time; does not trigger GC or modify any state.
 */
void luat_memprof_snapshot(lua_State *L, luat_memprof_snapshot_t *out);

/*
 * Print a human-readable memory report to the log.
 */
void luat_memprof_dump(lua_State *L);

#endif /* LUAT_MEMPROF_H */
