#include "luat_base.h"
#include "luat_malloc.h"

#define ldump_c
#define LUA_CORE

#include "lprefix.h"


#include <stddef.h>

#include "lua.h"

#include "lobject.h"
#include "lstate.h"
#include "lundump.h"
#include "lstring.h"

#define LUAT_LOG_TAG "cmp"
#include "luat_log.h"

static void cmpProto(const Proto* p1, const Proto *p2);

static void cmpCode(const Proto* p1, const Proto *p2) {
    LLOGD("code %d", memcmp(p1->code, p2->code, sizeof(Instruction)*p1->sizecode));
}


static void cmpConstants(const Proto* p1, const Proto *p2) {
    for (size_t i = 0; i < p1->sizek; i++)
    {
        TValue* o1 = &p1->k[i];
        TValue* o2 = &p2->k[i];
        if (ttype(o1) != ttype(o2)) {
            LLOGD("Constants Not Match %d %d %d", i, ttype(o1), ttype(o2));
            continue;
        }
        switch (p1->k[i].tt_)
        {
        case LUA_TSHRSTR:
        case LUA_TLNGSTR:
            if (tsslen(tsvalue(o1)) != tsslen(tsvalue(o2))) {
                LLOGE("strlen NOT match %d %d", tsslen(tsvalue(o1)), tsslen(tsvalue(o2)));
            }
            if (!strcmp(getstr(tsvalue(o1)), getstr(tsvalue(o2)))) {
                LLOGE("str value NOT match %s %s", getstr(tsvalue(o1)), getstr(tsvalue(o2)));
            }
            break;
        
        default:
            break;
        }
    }
    
}
static void cmpUpvalues(const Proto* p1, const Proto *p2) {
    for (size_t i = 0; i < p1->sizeupvalues; i++)
    {
        Upvaldesc* u1 = &p1->upvalues[i];
        Upvaldesc* u2 = &p2->upvalues[i];

        if (u1->idx != u2->idx) {
            LLOGE("upvalues idx NOT match %d %d", u1->idx, u2->idx);
        }
        if (u1->instack != u2->instack) {
            LLOGE("upvalues instack NOT match %d %d", u1->instack, u2->instack);
        }
        if (u1->name == NULL || u2->name == NULL) {
            LLOGE("upvalues NULL name %d", i);
        }
        if (strcmp(getstr(u1->name), getstr(u2->name))) {
            LLOGE("upvalues name NOT match %s %s", getstr(u1->name), getstr(u2->name));
        }
    }
    
}
static void cmpProtos(const Proto* p1, const Proto *p2) {
    LLOGD("protos %d", p1->sizep == p2->sizep);
    if (p1->sizep == p2->sizep) {
        for (size_t i = 0; i < p1->sizep; i++)
        {
            cmpProto(p1->p[i], p2->p[i]);
        }
    }
}
static void cmpDebug(const Proto* p1, const Proto *p2) {
    LLOGD("linenumbers %d", memcmp(p1->lineinfo, p2->lineinfo, sizeof(int) * p1->sizelineinfo));
    for (size_t i = 0; i < p1->sizelineinfo; i++)
    {
        /* code */
    }
    
}

static void cmpProto(const Proto* p1, const Proto *p2) {
    if (p1 == NULL || p2 == NULL) {
        LLOGD("p1/p2 is null");
        return;
    }
    if (p1 == p2) {
        LLOGD("p1 == p2, in pointer form");
        return;
    }

    LLOGD("source %s %s %d", getstr(p1->source), getstr(p2->source), strcmp(getstr(p1->source), getstr(p2->source)));

    // 对比几个属性
    LLOGD("linedefined %d %d %d", p1->linedefined, p2->linedefined, p1->linedefined == p2->linedefined);
    LLOGD("lastlinedefined %d %d %d", p1->lastlinedefined, p2->lastlinedefined, p1->lastlinedefined == p2->lastlinedefined);
    LLOGD("is_vararg %d %d %d", p1->is_vararg, p2->is_vararg, p1->is_vararg == p2->is_vararg);
    LLOGD("numparams %d %d %d", p1->numparams, p2->numparams, p1->numparams == p2->numparams);
    LLOGD("sizecode %d %d %d", p1->sizecode, p2->sizecode, p1->sizecode == p2->sizecode);
    LLOGD("sizek %d %d %d", p1->sizek, p2->sizek, p1->sizek == p2->sizek);
    LLOGD("sizelineinfo %d %d %d", p1->sizelineinfo, p2->sizelineinfo, p1->sizelineinfo == p2->sizelineinfo);
    LLOGD("sizelocvars %d %d %d", p1->sizelocvars, p2->sizelocvars, p1->sizelocvars == p2->sizelocvars);
    LLOGD("sizeupvalues %d %d %d", p1->sizeupvalues, p2->sizeupvalues, p1->sizeupvalues == p2->sizeupvalues);

    cmpCode(p1, p2);
    cmpConstants(p1, p2);
    cmpUpvalues(p1, p2);
    cmpProtos(p1, p2);
    cmpDebug(p1, p2);
}

void luat_luf_cmp(lua_State *L, const Proto* p1, const Proto *p2) {
    if (p1 == NULL || p2 == NULL)
        return;
    cmpProto(p1, p2);
}
