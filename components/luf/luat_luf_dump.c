/*
** $Id: ldump.c,v 2.37.1.1 2017/04/19 17:20:42 roberto Exp $
** save precompiled Lua chunks
** See Copyright Notice in lua.h
*/

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
#include "lgc.h"

#define LUAT_LOG_TAG "dump"
#include "luat_log.h"

#define white2gray(x)	resetbits(x->marked, WHITEBITS)
#define black2gray(x)	resetbit(x->marked, BLACKBIT)

static size_t fd_offset;

#define LUF_SIGNATURE "\x1cLUF"

typedef struct {
  lua_State *L;
  lua_Writer writer;
  void *data;
  int strip;
  int status;
} DumpState;


/*
** All high-level dumps go through DumpVector; you can change it to
** change the endianness of the result
*/
#define DumpVector(v,n,D)	DumpBlock(v,(n)*sizeof((v)[0]),D)

#define DumpLiteral(s,D)	DumpBlock(s, sizeof(s) - sizeof(char), D)

#define fslen(s) (sizeof(TString) + tsslen(s) + 1)


static void DumpBlock (const void *b, size_t size, DumpState *D) {
  if (D->status == 0 && size > 0) {
    lua_unlock(D->L);
    D->status = (*D->writer)(D->L, b, size, D->data);
    lua_lock(D->L);
  }

  fd_offset +=  size;
}


#define DumpVar(x,D)		DumpVector(&x,1,D);


static void DumpByte (int y, DumpState *D) {
  lu_byte x = (lu_byte)y;
  DumpVar(x, D);
}


static void DumpInt (int x, DumpState *D) {
  DumpVar(x, D);
}


static void DumpNumber (lua_Number x, DumpState *D) {
  DumpVar(x, D);
}


static void DumpInteger (lua_Integer x, DumpState *D) {
  DumpVar(x, D);
}


static void DumpString (const TString *s, DumpState *D) {
  size_t size = 0;
  if (s == NULL) {
    DumpByte(0, D);
    return;
  }
  DumpByte(1, D);
  TString ts;
  memcpy(&ts, s, sizeof(TString));
  ts.next = NULL;
  if (ts.tt == LUA_TSHRSTR) {
    ts.u.hnext = NULL;
    ts.u.lnglen = ts.shrlen;
    ts.hash = (getstr(s), ts.shrlen, 0);
    ts.extra = 1;
    ts.tt = LUA_TLNGSTR;
  }
  white2gray((&ts));
  //LLOGD("B>DumpString %d %d", fslen(s), fd_offset);
  DumpBlock(&ts, sizeof(TString), D);
  DumpBlock(getstr(s), tsslen(s)+1, D);
  //LLOGD("A>DumpString %d %d", fslen(s), fd_offset);
}

static void DumpCode (const Proto *f, DumpState *D) {
  DumpInt(f->sizecode, D);
  DumpVector(f->code, f->sizecode, D);
}


static void DumpFunction(const Proto *f, TString *psource, DumpState *D);

static void DumpConstants (const Proto *f, DumpState *D) {
  int i;
  int n = f->sizek;

  //LLOGD("DumpConstants %d %d", n, n * sizeof(TValue));
  DumpInt(n, D);

  size_t init_offset = fd_offset + sizeof(TValue) * n + sizeof(int);
  size_t i_offset = init_offset;
  TValue tmp;
  for (i = 0; i < n; i++) {
    const TValue *o = &f->k[i];
    switch (ttype(o)) {
      case LUA_TSHRSTR:
      case LUA_TLNGSTR:
      // {
        memcpy(&tmp, o, sizeof(TValue));
        tmp.value_.gc = (void*)(init_offset);
      //   o = &tmp;
        init_offset += fslen(tsvalue(o)) + 1;
      //   //break;
      // }
      default:
        DumpBlock(o, sizeof(TValue), D);
        break;
    }
  }
  //LLOGD("DumpConstants1 Strings len %d %d %d %d", init_offset, i_offset, fd_offset, init_offset - i_offset);
  DumpInt(init_offset - i_offset, D);
  for (i = 0; i < n; i++) {
    const TValue *o = &f->k[i];
    switch (ttype(o)) {
      case LUA_TSHRSTR:
      case LUA_TLNGSTR:
      {
        DumpString(tsvalue(o), D);
        break;
      }
    }
  }
  //LLOGD("DumpConstants2 Strings len %d %d %d %d", init_offset, i_offset, fd_offset, init_offset - i_offset);
}


static void DumpProtos (const Proto *f, DumpState *D) {
  int i;
  int n = f->sizep;
  DumpInt(n, D);
  for (i = 0; i < n; i++)
    DumpFunction(f->p[i], f->source, D);
}


static void DumpUpvalues (const Proto *f, DumpState *D) {
  int i, n = f->sizeupvalues;
  DumpInt(n, D);
  //LLOGD("LoadUpvalues %d %d", n, sizeof(Upvaldesc) * n);
  size_t init_offset = fd_offset + sizeof(Upvaldesc) * f->sizeupvalues + sizeof(int);
  size_t i_offset = init_offset;
  Upvaldesc desc;
  for (i = 0; i < n; i++) {
    if (f->upvalues[i].name == NULL)
      desc.name = NULL;
    else
      desc.name = (TString*)(init_offset);
    desc.idx = f->upvalues[i].idx;
    desc.instack = f->upvalues[i].instack;

    DumpBlock(&desc, sizeof(Upvaldesc), D);

    if (f->upvalues[i].name) {
      init_offset += fslen(f->upvalues[i].name) + 1;
      //LLOGD("DumpUpvalues name %s %d %d", getstr(f->upvalues[i].name), i_offset, init_offset);
    }
    else {
      init_offset += 1;
    }
  }
  
  //LLOGD("DumpUpvalues Strings len %d %d %d %d", init_offset, i_offset, fd_offset, init_offset - i_offset);
  DumpInt(init_offset - i_offset, D);
  for (i = 0; i < n; i++) {
    DumpString(f->upvalues[i].name, D);
  }
}


static void DumpDebug (const Proto *f, DumpState *D) {
  int i, n;
  n = (D->strip) ? 0 : f->sizelineinfo;
  DumpInt(n, D);
  DumpVector(f->lineinfo, n, D);
  n = (D->strip) ? 0 : f->sizelocvars;
  DumpInt(n, D);
  size_t init_offset = fd_offset + sizeof(LocVar) * f->sizelocvars + sizeof(int);
  size_t i_offset = init_offset;
  for (i = 0; i < n; i++) {
    DumpInt(f->locvars[i].varname == NULL ? 0 : init_offset, D);
    DumpInt(f->locvars[i].startpc, D);
    DumpInt(f->locvars[i].endpc, D);

    if (f->locvars[i].varname) {
      init_offset += fslen(f->locvars[i].varname) + 1;
    }
    else {
      init_offset += 1;
    }
  }
  //LLOGD("DumpDebug Strings len %d %d %d %d", init_offset, i_offset, fd_offset, init_offset - i_offset);
  DumpInt(init_offset - i_offset, D);
  for (i = 0; i < n; i++) {
    DumpString(f->locvars[i].varname, D);
  }
}


static void DumpFunction (const Proto *f, TString *psource, DumpState *D) {
  DumpString(f->source, D);

  DumpInt(f->linedefined, D);
  DumpInt(f->lastlinedefined, D);
  DumpByte(f->numparams, D);
  DumpByte(f->is_vararg, D);
  DumpByte(f->maxstacksize, D);

  // LLOGD("linedefined %d", f->linedefined);
  // LLOGD("lastlinedefined %d", f->lastlinedefined);
  // LLOGD("numparams %d", f->numparams);
  // LLOGD("is_vararg %d", f->is_vararg);
  // LLOGD("maxstacksize %d", f->maxstacksize);

  DumpCode(f, D);
  DumpConstants(f, D);
  DumpUpvalues(f, D);
  DumpProtos(f, D);
  DumpDebug(f, D);
}


static void DumpHeader (DumpState *D) {
  DumpLiteral(LUF_SIGNATURE, D);
  DumpByte(LUAC_VERSION, D);
  DumpByte(LUAC_FORMAT + 1, D);
  DumpLiteral(LUAC_DATA, D);
  DumpByte(sizeof(int), D);
  DumpByte(sizeof(size_t), D);
  DumpByte(sizeof(Instruction), D);
  DumpByte(sizeof(lua_Integer), D);
  DumpByte(sizeof(lua_Number), D);
  DumpInteger(LUAC_INT, D);
  DumpNumber(LUAC_NUM, D);
}


/*
** dump Lua function as precompiled chunk
*/
int luf_dump(lua_State *L, const Proto *f, lua_Writer w, void *data,
              int strip, int ptroffset) {
  DumpState D;
  D.L = L;
  D.writer = w;
  D.data = data;
  D.strip = strip;
  D.status = 0;

  fd_offset = ptroffset + 1;

  LLOGD("sizeof(Upvaldesc) %d", sizeof(Upvaldesc));
  LLOGD("sizeof(LocVar) %d", sizeof(LocVar));

  DumpHeader(&D);
  DumpByte(f->sizeupvalues, &D);
  // LLOGD("sizeupvalues %d", f->sizeupvalues);
  DumpFunction(f, NULL, &D);
  return D.status;
}

