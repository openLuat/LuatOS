/*
** $Id: lundump.c,v 2.44.1.1 2017/04/19 17:20:42 roberto Exp $
** load precompiled Lua chunks
** See Copyright Notice in lua.h
*/

#define lundump_c
#define LUA_CORE

#include "lprefix.h"


#include <string.h>

#include "lua.h"

#include "ldebug.h"
#include "ldo.h"
#include "lfunc.h"
#include "lmem.h"
#include "lobject.h"
#include "lstring.h"
#include "lundump.h"
#include "lzio.h"

#include "luat_base.h"
#include "luat_fs.h"

#define LUAT_LOG_TAG "undump"
#include "luat_log.h"

#define LUAT_UNDUMP_DEBUG 0

// 未开启VFS就不能使用mmap
#ifndef LUAT_USE_FS_VFS
#ifdef LUAT_USE_MEMORY_OPTIMIZATION_CODE_MMAP
#undef LUAT_USE_MEMORY_OPTIMIZATION_CODE_MMAP
#endif
#endif


#if !defined(luai_verifycode)
#define luai_verifycode(L,b,f)  /* empty */
#endif

typedef struct {
  lua_State *L;
  ZIO *Z;
  const char *name;
} LoadState;


static l_noret error(LoadState *S, const char *why) {
  luaO_pushfstring(S->L, "%s: %s precompiled chunk", S->name, why);
  luaD_throw(S->L, LUA_ERRSYNTAX);
}


/*
** All high-level loads go through LoadVector; you can change it to
** adapt to the endianness of the input
*/
#define LoadVector(S,b,n)	LoadBlock(S,b,(n)*sizeof((b)[0]))

static void LoadBlock (LoadState *S, void *b, size_t size) {
  if (luaZ_read(S->Z, b, size) != 0)
    error(S, "truncated");
}

static void* DistBlock (LoadState *S, size_t size) {
  char b = 0;
  void* p = S->Z->p;
  for (size_t i = 0; i < size; i++)
  {
    if (luaZ_read(S->Z, &b, 1) != 0)
      error(S, "truncated");
  }
  return p;
}


#define LoadVar(S,x)		LoadVector(S,&x,1)


static lu_byte LoadByte (LoadState *S) {
  lu_byte x;
  LoadVar(S, x);
  return x;
}


static int LoadInt (LoadState *S) {
  int x;
  LoadVar(S, x);
  return x;
}


static lua_Number LoadNumber (LoadState *S) {
  lua_Number x;
  LoadVar(S, x);
  return x;
}


static lua_Integer LoadInteger (LoadState *S) {
  lua_Integer x;
  LoadVar(S, x);
  return x;
}


static TString *LoadString (LoadState *S, Proto *p) {
  lu_byte t = LoadByte(S);
  if (t == 0)
    return NULL;
  TString * ts = S->Z->p;
  // LLOGD("LoadString >> %d %p", tsslen(ts), ts);
  DistBlock(S, sizeof(TString) + tsslen(ts) + 1);
  // LLOGD("LoadString >> %s", getstr(ts));
  return ts;
}

static void LoadCode (LoadState *S, Proto *f) {
  int n = LoadInt(S);
  // LLOGD("LoadCode %d %d", n, sizeof(Instruction) * n);
  f->sizecode = n;
  f->code = DistBlock(S, sizeof(Instruction) * n);
}


static void LoadFunction(LoadState *S, Proto *f, TString *psource);


static void LoadConstants (LoadState *S, Proto *f) {
  int i;
  int n = LoadInt(S);
  // LLOGD("LoadConstants %d %d", n, sizeof(TValue) * n);
  f->sizek = n;
  // 指向常数数组
  f->k = DistBlock(S, sizeof(TValue) * n);
  // 跳过字符串段
  
  // LLOGD("1>>LoadConstants %02X %02X %02X %02X", *(S->Z->p), *(S->Z->p + 1), *(S->Z->p + 2), *(S->Z->p + 3));
  n = LoadInt(S);
  // LLOGD("LoadConstants skip Strings %d", n);
  DistBlock(S, sizeof(char) * n);

  // LLOGD("2>>LoadConstants %02X %02X %02X %02X", *(S->Z->p), *(S->Z->p + 1), *(S->Z->p + 2), *(S->Z->p + 3));
}


static void LoadProtos (LoadState *S, Proto *f) {
  int i;
  int n = LoadInt(S);
  f->p = luaM_newvector(S->L, n, Proto *);
  f->sizep = n;
  for (i = 0; i < n; i++)
    f->p[i] = NULL;
  for (i = 0; i < n; i++) {
    f->p[i] = luaF_newproto(S->L);
    luaC_objbarrier(S->L, f, f->p[i]);
    LoadFunction(S, f->p[i], f->source);
  }
  // LLOGD("LoadProtos %d %d", n, sizeof(Proto *) * n);
}


static void LoadUpvalues (LoadState *S, Proto *f) {
  int i, n;
  n = LoadInt(S);
  f->sizeupvalues = n;
  // LLOGD("LoadUpvalues %d %d", n, sizeof(Upvaldesc) * n);
  f->upvalues = DistBlock(S, sizeof(Upvaldesc) * n);
  // 跳过字符串段
  n = LoadInt(S);
  // LLOGD("LoadUpvalues skip Strings %d", n);
  DistBlock(S, sizeof(char) * n);
}


static void LoadDebug (LoadState *S, Proto *f) {
  int i, n;
  
  n = LoadInt(S);
  f->sizelineinfo = n;
  // LLOGD("LoadDebug sizelineinfo %d %d", n, sizeof(int) * n);
  f->lineinfo = DistBlock(S, sizeof(int) * n);
  
  n = LoadInt(S);
  f->sizelocvars = n;
  // LLOGD("LoadDebug sizelocvars %d %d", n, sizeof(LocVar) * n);
  f->locvars = DistBlock(S, sizeof(LocVar) * n);

  n = LoadInt(S);
  DistBlock(S, sizeof(char) * n);
}


static void LoadFunction (LoadState *S, Proto *f, TString *psource) {
  //LLOGD(">> %02X %02X %02X %02X", *(S->Z->p), *(S->Z->p + 1), *(S->Z->p + 2), *(S->Z->p + 3));
  f->source = LoadString(S, f);
  if (f->source == NULL)  /* no source in dump? */
    f->source = psource;  /* reuse parent's source */

  // if (f->source)
  //   LLOGI("%s %d source %s", __FILE__, __LINE__, getstr(f->source));
  // else
  //   LLOGD("no source ?");

  f->linedefined = LoadInt(S);
  f->lastlinedefined = LoadInt(S);
  f->numparams = LoadByte(S);
  f->is_vararg = LoadByte(S);
  f->maxstacksize = LoadByte(S);

  // LLOGD("linedefined %d", f->linedefined);
  // LLOGD("lastlinedefined %d", f->lastlinedefined);
  // LLOGD("numparams %d", f->numparams);
  // LLOGD("is_vararg %d", f->is_vararg);
  // LLOGD("maxstacksize %d", f->maxstacksize);

  LoadCode(S, f);
  LoadConstants(S, f);
  LoadUpvalues(S, f);
  LoadProtos(S, f);
  LoadDebug(S, f);
}


static void checkliteral (LoadState *S, const char *s, const char *msg) {
  char buff[sizeof(LUA_SIGNATURE) + sizeof(LUAC_DATA)]; /* larger than both */
  size_t len = strlen(s);
  LoadVector(S, buff, len);
  if (memcmp(s, buff, len) != 0)
    error(S, msg);
}


static void fchecksize (LoadState *S, size_t size, const char *tname) {
  if (LoadByte(S) != size)
    error(S, luaO_pushfstring(S->L, "%s size mismatch in", tname));
}


#define checksize(S,t)	fchecksize(S,sizeof(t),#t)

static void checkHeader (LoadState *S) {
  checkliteral(S, LUA_SIGNATURE + 1, "not a");  /* 1st char already checked */
  if (LoadByte(S) != LUAC_VERSION)
    error(S, "version mismatch in");
  if (LoadByte(S) != 1)
    error(S, "format mismatch in");
  checkliteral(S, LUAC_DATA, "corrupted");
  checksize(S, int);
  checksize(S, size_t);
  checksize(S, Instruction);
  checksize(S, lua_Integer);
  checksize(S, lua_Number);
  if (LoadInteger(S) != LUAC_INT)
    error(S, "endianness mismatch in");
  if (LoadNumber(S) != LUAC_NUM)
    error(S, "float format mismatch in");
}

extern void luat_os_print_heapinfo(const char* tag);

/*
** load precompiled chunk
*/
LClosure *luat_luf_undump(lua_State *L, ZIO *Z, const char *name) {
  LoadState S;
  LClosure *cl;

  S.name = name;
  S.L = L;
  S.Z = Z;
  checkHeader(&S);
  cl = luaF_newLclosure(L, LoadByte(&S));
  setclLvalue(L, L->top, cl);
  luaD_inctop(L);
  cl->p = luaF_newproto(L);
  // LLOGD("sizeupvalues %d", cl->nupvalues);
  luaC_objbarrier(L, cl, cl->p); // add by wendal, refer: https://github.com/lua/lua/commit/f5eb809d3f1da13683cd02184042e67228206205
  LoadFunction(&S, cl->p, NULL);
  lua_assert(cl->nupvalues == cl->p->sizeupvalues);
  luai_verifycode(L, buff, cl->p);
  return cl;
}

