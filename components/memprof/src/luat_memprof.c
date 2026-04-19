#include "luat_base.h"
#include "luat_memprof.h"

/* Lua internal headers needed to walk the GC lists */
#include "lstate.h"
#include "lobject.h"
#include "lfunc.h"
#include "ltable.h"

#define LUAT_LOG_TAG "memprof"
#include "luat_log.h"

/* ---- size helpers ---- */

static size_t size_of_string(const TString *ts) {
    return sizeof(UTString) + (ts->tt == LUA_TSHRSTR ? (size_t)ts->shrlen : ts->u.lnglen) + 1;
}

static size_t size_of_udata(const Udata *u) {
    return sizeof(UUdata) + u->len;
}

static size_t size_of_table(const Table *t) {
    return sizeof(Table)
         + (size_t)t->sizearray * sizeof(TValue)
         + (size_t)sizenode(t) * sizeof(Node);
}

static size_t size_of_proto(const Proto *p) {
    return sizeof(Proto)
         + (size_t)p->sizek       * sizeof(TValue)
         + (size_t)p->sizecode    * sizeof(Instruction)
         + (size_t)p->sizelineinfo * sizeof(int)
         + (size_t)p->sizelocvars * sizeof(LocVar)
         + (size_t)p->sizeupvalues * sizeof(Upvaldesc)
         + (size_t)p->sizep       * sizeof(Proto *);
}

static size_t size_of_lclosure(const LClosure *cl) {
    return (size_t)sizeLclosure(cl->nupvalues);
}

static size_t size_of_cclosure(const CClosure *cl) {
    return (size_t)sizeCclosure(cl->nupvalues);
}

static size_t size_of_thread(const lua_State *th) {
    return sizeof(lua_State) + (size_t)th->stacksize * sizeof(TValue);
}

/* ---- walk one GC list ---- */

static void walk_gclist(GCObject *obj, luat_memprof_snapshot_t *out) {
    for (; obj != NULL; obj = obj->next) {
        switch (obj->tt) {
        case LUA_TSHRSTR: {
            out->str_short.count++;
            out->str_short.bytes += size_of_string((TString *)obj);
            break;
        }
        case LUA_TLNGSTR: {
            out->str_long.count++;
            out->str_long.bytes += size_of_string((TString *)obj);
            break;
        }
        case LUA_TTABLE: {
            out->table.count++;
            out->table.bytes += size_of_table((Table *)obj);
            break;
        }
        case LUA_TPROTO: {
            out->proto.count++;
            out->proto.bytes += size_of_proto((Proto *)obj);
            break;
        }
        case LUA_TLCL: {
            out->lclosure.count++;
            out->lclosure.bytes += size_of_lclosure((LClosure *)obj);
            break;
        }
        case LUA_TCCL: {
            out->cclosure.count++;
            out->cclosure.bytes += size_of_cclosure((CClosure *)obj);
            break;
        }
        case LUA_TUSERDATA: {
            out->udata.count++;
            out->udata.bytes += size_of_udata((Udata *)obj);
            break;
        }
        case LUA_TTHREAD: {
            out->thread.count++;
            out->thread.bytes += size_of_thread((lua_State *)obj);
            break;
        }
        default:
            break;
        }
    }
}

void luat_memprof_snapshot(lua_State *L, luat_memprof_snapshot_t *out) {
    memset(out, 0, sizeof(*out));
    global_State *g = G(L);
    walk_gclist(g->allgc,   out);
    walk_gclist(g->fixedgc, out);
    out->total_bytes =
        out->str_short.bytes + out->str_long.bytes +
        out->table.bytes     + out->proto.bytes    +
        out->lclosure.bytes  + out->cclosure.bytes +
        out->udata.bytes     + out->thread.bytes;
}

void luat_memprof_dump(lua_State *L) {
    luat_memprof_snapshot_t snap;
    luat_memprof_snapshot(L, &snap);
    LLOGI("=== memprof snapshot ===");
    LLOGI("  str_short : count=%-5d bytes=%d", snap.str_short.count, (int)snap.str_short.bytes);
    LLOGI("  str_long  : count=%-5d bytes=%d", snap.str_long.count,  (int)snap.str_long.bytes);
    LLOGI("  table     : count=%-5d bytes=%d", snap.table.count,     (int)snap.table.bytes);
    LLOGI("  proto     : count=%-5d bytes=%d", snap.proto.count,     (int)snap.proto.bytes);
    LLOGI("  lclosure  : count=%-5d bytes=%d", snap.lclosure.count,  (int)snap.lclosure.bytes);
    LLOGI("  cclosure  : count=%-5d bytes=%d", snap.cclosure.count,  (int)snap.cclosure.bytes);
    LLOGI("  udata     : count=%-5d bytes=%d", snap.udata.count,     (int)snap.udata.bytes);
    LLOGI("  thread    : count=%-5d bytes=%d", snap.thread.count,    (int)snap.thread.bytes);
    LLOGI("  total_bytes=%d", (int)snap.total_bytes);
    LLOGI("========================");
}


