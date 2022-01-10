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

// #define fslen(s) (sizeof(TString) + tsslen(s) + 1)
static size_t fslen(TString *ts) {
  size_t t = sizeof(TString) + tsslen(ts) + 1;
  if (t % 0x04 != 0) {
    t += (4 - (t % 0x04));
  }
  return t;
}

#define LUF_SIGNATURE "\x1cLUF"

typedef struct {
  lua_State *L;
  lua_Writer writer;
  void *data;
  int strip;
  int status;
} DumpState;


static void DumpString (const TString *s, DumpState *D);

static size_t fd_offset = 0;
static size_t str_offset = 0;

typedef struct strpool
{
  TString* ts[256];
  void* ptr[256];
  void* next;
}strpool_t;

static strpool_t *spool = NULL;

static void  spool_init(void) {
  spool = luat_heap_malloc(sizeof(strpool_t));
  memset(spool, 0, sizeof(strpool_t));
}
static void  spool_deinit(void) {
  strpool_t *tmp = spool;
  while (tmp != NULL) {
    luat_heap_free(tmp);
    tmp = (strpool_t *)tmp->next;
  }
}
static void spool_dump(DumpState *D) {
  strpool_t *tmp = spool;
  while (tmp != NULL) {
    for (size_t i = 0; i < 256; i++)
    {
      if (tmp->ts[i] == NULL)
        return;
      DumpString(tmp->ts[i], D);
    }
    tmp = (strpool_t *)tmp->next;
  }
}

static TString* spool_add(TString* ts) {
  if (ts == NULL)
    return ts;
  strpool_t *tmp = spool;
  // strpool_t *next = NULL;
  while (tmp != NULL) {
    for (size_t i = 0; i < 256; i++)
    {
      if (tmp->ts[i] == NULL) {
        //LLOGD("add string [%s]", getstr(ts));
        tmp->ts[i] = ts;
        tmp->ptr[i] = (void*)(str_offset);
        str_offset += fslen(ts);

        LLOGD("spool_add new %s %p", getstr(ts), tmp->ptr[i]);
        return tmp->ptr[i];
      }
      if (!strcmp(getstr(ts), getstr(tmp->ts[i]))) {
        LLOGD("spool_add match %s %p", getstr(ts), tmp->ptr[i]);
        return tmp->ptr[i];
      }
    }
    if (tmp->next == NULL)
      break;
    tmp = tmp->next;
  }
  tmp->next = luat_heap_malloc(sizeof(strpool_t));
  memset(tmp->next, 0, sizeof(strpool_t));

  tmp->ts[0] = ts;
  tmp->ptr[0] = (void*)(str_offset);
  str_offset += fslen(ts);
  LLOGD("spool_add new %s %p", getstr(ts), tmp->ptr[0]);
  return tmp->ptr[0];
}

size_t countProtoDumpSize(Proto *f) {
  if (f == NULL)
    return 0;
  size_t count = 0;


  /*
  DumpInt(f->linedefined, D);
  DumpInt(f->lastlinedefined, D);
  DumpByte(f->numparams, D);
  DumpByte(f->is_vararg, D);
  DumpByte(f->maxstacksize, D);
  DumpByte(f->source == NULL ? 0 : 1, D);
  */
  count += sizeof(int) * 2 + sizeof(lu_byte) * 4;

  count += f->sizecode * sizeof(Instruction);
  count += f->sizek * sizeof(TValue);
  count += f->sizeupvalues * sizeof(Upvaldesc);
  count += f->sizelineinfo * sizeof(int);
  count += f->sizelocvars * sizeof(LocVar);

  for (size_t i = 0; i < f->sizep; i++)
  {
    count += countProtoDumpSize(f->p[i]);
  }

  count += sizeof(int) * 6; // sizeX * 6

  return count;
}


/*
** All high-level dumps go through DumpVector; you can change it to
** change the endianness of the result
*/
#define DumpVector(v,n,D)	DumpBlock(v,(n)*sizeof((v)[0]),D)

#define DumpLiteral(s,D)	DumpBlock(s, sizeof(s) - sizeof(char), D)

// static TString* AddMockString(TString* ts) {
//   if (ts == NULL)
//     return ts;
//   TString* t = (TString*) (fd_offset + str_offset);
//   str_offset += (sizeof(TString) + tsslen(ts) + 1);
//   return t;
// }

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
  // size_t size = 0;
  // if (s == NULL) {
  //   DumpByte(0, D);
  //   return;
  // }
  // DumpByte(1, D);
  TString ts;
  memcpy(&ts, s, sizeof(TString));
  ts.next = NULL;
  if (ts.tt == LUA_TSHRSTR) {
    ts.u.hnext = NULL;
    // ts.u.lnglen = ts.shrlen;
    // ts.hash = (getstr(s), ts.shrlen, 0);
    ts.extra = 1;
    // ts.tt = LUA_TLNGSTR;
  }
  white2gray((&ts));
  //LLOGD("B>DumpString %d %d", fslen(s), fd_offset);
  DumpBlock(&ts, sizeof(TString), D);
  DumpBlock(getstr(s), tsslen(s)+1, D);
  if ((tsslen(s) + 1) % 0x04 != 0) {
    for (size_t i = 0; i < (4-((tsslen(s) + 1) % 0x04)); i++)
    {
      DumpByte(0, D);
    }
  }
  //LLOGD("A>DumpString %d %d", fslen(s), fd_offset);
}

static void DumpCode (const Proto *f, DumpState *D) {
  //DumpInt(f->sizecode, D);
  DumpVector(f->code, f->sizecode, D);
  for (size_t i = 0; i < f->sizecode; i++)
  {
    LLOGD("Code %02X -> %08X", i, f->code[i]);
  }
}


static void DumpFunction(const Proto *f, TString *psource, DumpState *D);

static void DumpConstants (const Proto *f, DumpState *D) {
  int i;
  int n = f->sizek;

  //LLOGD("DumpConstants %d %d", n, n * sizeof(TValue));
  //DumpInt(n, D);

  //size_t init_offset = fd_offset + sizeof(TValue) * n + sizeof(int);
  //size_t i_offset = init_offset;
  TValue tmp;
  TString* ts;
  for (i = 0; i < n; i++) {
    const TValue *o = &f->k[i];
    switch (ttype(o)) {
      case LUA_TSHRSTR:
      case LUA_TLNGSTR:
      // {
        //memcpy(&tmp, o, sizeof(TValue));
        ts = spool_add(tsvalue(o));
        tmp.value_.gc = ts;
        tmp.tt_ = ttype(o);
        // tmp.tt_ = LUA_TLNGSTR;
        DumpBlock(&tmp, sizeof(TValue), D);
        break;
      //   o = &tmp;
      //  init_offset += fslen(tsvalue(o)) + 1;
      //   //break;
      // }
      default:
        DumpBlock(o, sizeof(TValue), D);
        break;
    }
  }
  //LLOGD("DumpConstants1 Strings len %d %d %d %d", init_offset, i_offset, fd_offset, init_offset - i_offset);
  // DumpInt(init_offset - i_offset, D);
  // for (i = 0; i < n; i++) {
  //   const TValue *o = &f->k[i];
  //   switch (ttype(o)) {
  //     case LUA_TSHRSTR:
  //     case LUA_TLNGSTR:
  //     {
  //       DumpString(tsvalue(o), D);
  //       break;
  //     }
  //   }
  // }
  //LLOGD("DumpConstants2 Strings len %d %d %d %d", init_offset, i_offset, fd_offset, init_offset - i_offset);
}


static void DumpProtos (const Proto *f, DumpState *D) {
  int i;
  int n = f->sizep;
  // DumpInt(n, D);
  for (i = 0; i < n; i++)
    DumpFunction(f->p[i], f->source, D);
}


static void DumpUpvalues (const Proto *f, DumpState *D) {
  int i, n;
  i = 0;
  n = f->sizeupvalues;
  // DumpInt(n, D);
  //LLOGD("LoadUpvalues %d %d", n, sizeof(Upvaldesc) * n);
  // size_t init_offset = fd_offset + sizeof(Upvaldesc) * f->sizeupvalues + sizeof(int);
  // size_t i_offset = init_offset;
  Upvaldesc desc;
  for (i = 0; i < n; i++) {
    desc.name = spool_add(f->upvalues[i].name);
    desc.idx = f->upvalues[i].idx;
    desc.instack = f->upvalues[i].instack;

    DumpBlock(&desc, sizeof(Upvaldesc), D);

    // if (f->upvalues[i].name) {
    //   init_offset += fslen(f->upvalues[i].name) + 1;
    //   //LLOGD("DumpUpvalues name %s %d %d", getstr(f->upvalues[i].name), i_offset, init_offset);
    // }
    // else {
    //   init_offset += 1;
    // }
  }
  
  //LLOGD("DumpUpvalues Strings len %d %d %d %d", init_offset, i_offset, fd_offset, init_offset - i_offset);
  // DumpInt(init_offset - i_offset, D);
  // for (i = 0; i < n; i++) {
  //   DumpString(f->upvalues[i].name, D);
  // }
}


static void DumpDebug (const Proto *f, DumpState *D) {
  int i, n;
  n = f->sizelineinfo;
  // DumpInt(n, D);
  DumpVector(f->lineinfo, n, D);
  n = f->sizelocvars;
  // DumpInt(n, D);
  // size_t init_offset = fd_offset + sizeof(LocVar) * f->sizelocvars + sizeof(int);
  // size_t i_offset = init_offset;
  LocVar lv;
  for (i = 0; i < n; i++) {
    lv.varname = spool_add(f->locvars[i].varname);
    lv.startpc = f->locvars[i].startpc;
    lv.endpc   = f->locvars[i].endpc;
    DumpBlock(&lv, sizeof(LocVar), D);
  }
  //LLOGD("DumpDebug Strings len %d %d %d %d", init_offset, i_offset, fd_offset, init_offset - i_offset);
  // DumpInt(init_offset - i_offset, D);
  // for (i = 0; i < n; i++) {
  //   DumpString(f->locvars[i].varname, D);
  // }
}


static void DumpFunction (const Proto *f, TString *psource, DumpState *D) {
  //DumpString(f->source, D);
  // LLOGD("<<<<<<<<< DumpFunction");

  DumpInt(f->linedefined, D);
  DumpInt(f->lastlinedefined, D);
  DumpByte(f->numparams, D);
  DumpByte(f->is_vararg, D);
  DumpByte(f->maxstacksize, D);
  DumpByte(f->source == NULL ? 0 : 1, D);

  LLOGD("linedefined %d", f->linedefined);
  LLOGD("lastlinedefined %d", f->lastlinedefined);
  LLOGD("numparams %d", f->numparams);
  LLOGD("is_vararg %d", f->is_vararg);
  LLOGD("maxstacksize %d", f->maxstacksize);

  DumpInt(f->sizecode, D);
  DumpInt(f->sizek, D);
  DumpInt(f->sizeupvalues, D);
  DumpInt(f->sizep, D);
  DumpInt(f->sizelineinfo, D);
  DumpInt(f->sizelocvars, D);

  LLOGD("sizecode %d", f->sizecode);
  LLOGD("sizek %d", f->sizek);
  LLOGD("sizeupvalues %d", f->sizeupvalues);
  LLOGD("sizep %d", f->sizep);
  LLOGD("sizelineinfo %d", f->sizelineinfo);
  LLOGD("sizelocvars %d", f->sizelocvars);

  DumpCode(f, D);
  DumpConstants(f, D);
  DumpUpvalues(f, D);
  DumpProtos(f, D);
  DumpDebug(f, D);

  // LLOGD(">>>>>>>>>>>>> DumpFunction");

  //if (f->source)
  //  DumpString((const TString*)f->source, D);
}


static void DumpHeader (DumpState *D) { // 15+12
  DumpLiteral(LUF_SIGNATURE, D); // 4
  DumpByte(LUAC_VERSION, D); // 1, 5
  DumpByte(LUAC_FORMAT + 1, D); // 1, 6
  DumpLiteral(LUAC_DATA, D); // 6, 12
  DumpByte(sizeof(int), D); // 1, 13
  DumpByte(sizeof(size_t), D); // 1, 14
  DumpByte(sizeof(Instruction), D); // 1, 15
  DumpByte(sizeof(lua_Integer), D); // 1, 16
  DumpByte(sizeof(lua_Number), D); // 1, 17
  DumpInteger(LUAC_INT, D); // 4, 21
  DumpNumber(LUAC_NUM, D);  // 4, 25
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

  fd_offset = ptroffset;
  LLOGD("fd_offset %08X  ptroffset %08X", fd_offset, ptroffset);

  // LLOGD("sizeof(Upvaldesc) %d", sizeof(Upvaldesc));
  // LLOGD("sizeof(LocVar) %d", sizeof(LocVar));

  DumpHeader(&D); // 25
  DumpByte(f->sizeupvalues, &D); // 1, 26

  size_t fill_offset = fd_offset % 0x04;
  LLOGD("fix %d 0x00", fill_offset);
  if (fill_offset != 0) {
    for (size_t i = 0; i < (4 - fill_offset); i++)
    {
      DumpByte(0, &D);
    }
  }
  

  LLOGD("after header + sizeupvalues, fd_offset %08X", fd_offset);

  size_t tcount = countProtoDumpSize(f);
  spool_init();
  str_offset = fd_offset + tcount + 4;
  // LLOGD("sizeupvalues %d", f->sizeupvalues);
  LLOGD("str_offset %08X", str_offset);
  LLOGD("tcount %08X  ptroffset %08X", tcount, ptroffset);
  DumpInt(f->source == NULL ? 0 : str_offset, &D);
  TString* tmp = spool_add(f->source);
  LLOGD("source tmp %p", tmp);
  DumpFunction(f, NULL, &D);
  // LLOGD("after DumpFunction <");
  spool_dump(&D);
  // LLOGD("spool_dump <");
  spool_deinit();
  // LLOGD("spool_deinit <");
  LLOGD("LClosure %d Proto %d Upvaldesc %d LocVal %d", 
      sizeof(LClosure), sizeof(Proto), sizeof(Upvaldesc), sizeof(LocVar));
  return D.status;
}

