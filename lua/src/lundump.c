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

size_t ptr_offset = 0;
#ifdef LUAT_UNDUMP_DEBUG
size_t code_size = 0;
size_t code_max = 0;
size_t proto_size = 0;
size_t const_size = 0;
size_t debug_size = 0;
size_t str_size = 0;
size_t max_pc = 0;
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
  ptr_offset += size;
  if (luaZ_read(S->Z, b, size) != 0)
    error(S, "truncated");
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

#ifndef LoadF
typedef struct LoadF {
  int n;  /* number of pre-read characters */
  FILE *f;  /* file being read */
  char buff[BUFSIZ];  /* area for reading file */
} LoadF;
#endif

#if defined(__LUATOS_SMALL_RAM__) && defined(__LUATOS_SCRIPT_BASE__)
/*
** creates a new string object
*/
static TString *static_createstrobj (lua_State *L, size_t l, int tag, unsigned int h) {
  TString *ts;
  GCObject *o;
  o = luaC_newobj(L, tag, sizeof(TString) + l);
  ts = gco2ts(o);
  ts->hash = h;
  ts->extra = 0;
  return ts;
}

/*
** checks whether short string exists and reuses it or creates a new one
*/
static TString *static_internshrstr (lua_State *L, const char *str, size_t l) {
  TString *ts;
  global_State *g = G(L);
  unsigned int h = luaS_hash(str, l, g->seed);
  TString **list = &g->strt.hash[lmod(h, g->strt.size)];
  lua_assert(str != NULL);  /* otherwise 'memcmp'/'memcpy' are undefined */
  for (ts = *list; ts != NULL; ts = ts->u.hnext) {
    if (l == ts->shrlen &&
        (memcmp(str, getstr(ts), l * sizeof(char)) == 0)) {
      /* found! */
      if (isdead(g, ts))  /* dead (but not collected yet)? */
        changewhite(ts);  /* resurrect it */
      return ts;
    }
  }
  if (g->strt.nuse >= g->strt.size && g->strt.size <= MAX_INT/2) {
    luaS_resize(L, g->strt.size * 2);
    list = &g->strt.hash[lmod(h, g->strt.size)];  /* recompute with new size */
  }
  ts = static_createstrobj(L, 4, LUA_TSHRSTR, h);
  ts->static_flag = 1;
  memcpy(cast(char *, (ts)) + sizeof(UTString), &str, 4);
  ts->shrlen = cast_byte(l);
  ts->u.hnext = *list;
  *list = ts;
  g->strt.nuse++;
  return ts;
}
#endif

static TString *LoadString (LoadState *S, Proto *p) {
  size_t size = LoadByte(S);
  TString *ts;
  if (size == 0xFF)
    LoadVar(S, size);
#if defined(__LUATOS_SMALL_RAM__) && defined(__LUATOS_SCRIPT_BASE__)
  char* ptr = (char*)luat_vfs_mmap(((LoadF*)S->Z->data)->f);
  uint32_t offset;
  if (ptr && size) {
	  offset = (uint32_t)ptr + ptr_offset - __LUATOS_SCRIPT_BASE__;
	  char temp[128];
	  uint32_t done_len = size;
	  do {
		  if (done_len > sizeof(temp)){
			  LoadVector(S, temp, sizeof(temp));
			  done_len -= sizeof(temp);
		  } else {
			  LoadVector(S, temp, done_len);
			  done_len = 0;
		  }
	  }while(done_len);
	  if (--size <= LUAI_MAXSHORTLEN) {  /* short string? */
		  ts = static_internshrstr(S->L, offset + __LUATOS_SCRIPT_BASE__, size);
#ifdef LUAT_UNDUMP_DEBUG
		  str_size+= (4 + sizeof(TString) + (8 - 1)) & (~(8 - 1));
#endif
	  }
	  else {  /* long string */
		  ts = static_createstrobj(S->L, 0, LUA_TLNGSTR, G(S->L)->seed);
		  ts->static_flag = (offset >> 15) + 1;
		  ts->u.static_offset = offset & 0x00007fff;
		  ts->u.lnglen = size;
#ifdef LUAT_UNDUMP_DEBUG
		  str_size+= (sizeof(TString) + (8 - 1)) & (~(8 - 1));
#endif
	  }

  } else {
	return NULL;
  }
  size = 0;
#else
  if (size == 0)
    return NULL;
  else if (--size <= LUAI_MAXSHORTLEN) {  /* short string? */
    char buff[LUAI_MAXSHORTLEN];
    LoadVector(S, buff, size);
    ts = luaS_newlstr(S->L, buff, size);
  }
  else {  /* long string */
    ts = luaS_createlngstrobj(S->L, size);
    LoadVector(S, getstr(ts), size);  /* load directly in final place */
  }
#ifdef LUAT_UNDUMP_DEBUG
  str_size+= (size + sizeof(TString) + (8 - 1)) & (~(8 - 1));
#endif
#endif
  luaC_objbarrier(S->L, p, ts);


  return ts;
}



static void LoadCode (LoadState *S, Proto *f) {
  int n = LoadInt(S);
  f->sizecode = n;
#ifdef LUAT_UNDUMP_DEBUG
  code_max += n * sizeof(Instruction);
#endif
#ifdef LUAT_USE_MEMORY_OPTIMIZATION_CODE_MMAP
  #if LUAT_UNDUMP_DEBUG
//  LLOGD("try mmap %p %p %p", S, S->Z, S->Z->data);
  #endif
  char* ptr = (char*)luat_fs_mmap(((LoadF*)S->Z->data)->f);
  Instruction inst[1];
  if (ptr) {
    f->code = (Instruction*)(ptr + ptr_offset);
    for (size_t i = 0; i < n; i++)
    {
      LoadVector(S, &inst, 1);
    }
    #if LUAT_UNDUMP_DEBUG
    LLOGD("code in rom");
    #endif
    return;
  }
#endif
  // 调试时务必打开
#if LUAT_UNDUMP_DEBUG
  LLOGD("code in ram");
  code_size += ((n * sizeof(Instruction)) + (8 - 1)) & (~(8 - 1));
#endif
  f->code = luaM_newvector(S->L, n, Instruction);
  LoadVector(S, f->code, n);

}


static void LoadFunction(LoadState *S, Proto *f, TString *psource);


static void LoadConstants (LoadState *S, Proto *f) {
  int i;
  int n = LoadInt(S);
  f->k = luaM_newvector(S->L, n, TValue);
  f->sizek = n;
  for (i = 0; i < n; i++)
    setnilvalue(&f->k[i]);
  for (i = 0; i < n; i++) {
    TValue *o = &f->k[i];
    int t = LoadByte(S);
    switch (t) {
    case LUA_TNIL:
      setnilvalue(o);
      break;
    case LUA_TBOOLEAN:
      setbvalue(o, LoadByte(S));
      break;
    case LUA_TNUMFLT:
      setfltvalue(o, LoadNumber(S));
      break;
    case LUA_TNUMINT:
      setivalue(o, LoadInteger(S));
      break;
    case LUA_TSHRSTR:
    case LUA_TLNGSTR:
      setsvalue2n(S->L, o, LoadString(S, f));
      break;
    default:
      lua_assert(0);
    }
  }
#ifdef LUAT_UNDUMP_DEBUG
  const_size += (n * sizeof(TValue) + (8 - 1)) & (~(8 - 1));
#endif
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
#ifdef LUAT_UNDUMP_DEBUG
  proto_size += (sizeof(Proto) + (8 - 1)) & (~(8 - 1));
#endif
}


static void LoadUpvalues (LoadState *S, Proto *f) {
  int i, n;
  n = LoadInt(S);
  f->upvalues = luaM_newvector(S->L, n, Upvaldesc);
  f->sizeupvalues = n;
  for (i = 0; i < n; i++)
    f->upvalues[i].name = NULL;
  for (i = 0; i < n; i++) {
    f->upvalues[i].instack = LoadByte(S);
    f->upvalues[i].idx = LoadByte(S);
  }
}


static void LoadDebug (LoadState *S, Proto *f) {
  int i, n;
  n = LoadInt(S);
  f->sizelineinfo = n;
  f->lineinfo = NULL;
#ifdef LUAT_USE_MEMORY_OPTIMIZATION_CODE_MMAP
  if (n > 0) {
    uint8_t* ptr = (uint8_t*)luat_fs_mmap(((LoadF*)S->Z->data)->f);
    int inst[1];
    if (ptr) {
	    f->lineinfo = (int*)(ptr + ptr_offset);
      for (size_t i = 0; i < n; i++)
      {
        LoadVector(S, &inst, 1);
      }
    }
  }
#endif
  if (n > 0 && f->lineinfo == NULL) {
    f->lineinfo = luaM_newvector(S->L, n, int);
    LoadVector(S, f->lineinfo, n);
  }
// #ifdef LUAT_UNDUMP_DEBUG
//   debug_size += (f->sizelineinfo * sizeof(int) + (8 - 1)) & (~(8 - 1));
// #endif
// #endif
  n = LoadInt(S);
  f->locvars = luaM_newvector(S->L, n, LocVar);
  f->sizelocvars = n;
  for (i = 0; i < n; i++)
    f->locvars[i].varname = NULL;
  for (i = 0; i < n; i++) {
    f->locvars[i].varname = LoadString(S, f);
    f->locvars[i].startpc = LoadInt(S);
    f->locvars[i].endpc = LoadInt(S);
#ifdef LUAT_UNDUMP_DEBUG
    if (f->locvars[i].startpc > max_pc)
    {
    	max_pc = f->locvars[i].startpc;
    }
    if (f->locvars[i].endpc > max_pc)
    {
    	max_pc = f->locvars[i].endpc;
    }
#endif
  }
  n = LoadInt(S);
  for (i = 0; i < n; i++)
    f->upvalues[i].name = LoadString(S, f);

#ifdef LUAT_UNDUMP_DEBUG
  debug_size += f->sizelocvars * (sizeof(LocVar) + (8 - 1)) & (~(8 - 1));
#endif
}


static void LoadFunction (LoadState *S, Proto *f, TString *psource) {
  f->source = LoadString(S, f);
  if (f->source == NULL)  /* no source in dump? */
    f->source = psource;  /* reuse parent's source */
  f->linedefined = LoadInt(S);
  f->lastlinedefined = LoadInt(S);
  f->numparams = LoadByte(S);
  f->is_vararg = LoadByte(S);
  f->maxstacksize = LoadByte(S);
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
  if (LoadByte(S) != LUAC_FORMAT)
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
LClosure *luaU_undump(lua_State *L, ZIO *Z, const char *name) {
  LoadState S;
  LClosure *cl;
  TString *ts = NULL;

  // 复位偏移量数据
  ptr_offset = 0;
  ptr_offset ++; // 之前的方法已经读取了一个字节
  if (*name == '@' || *name == '=')
    S.name = name + 1;
  else if (*name == LUA_SIGNATURE[0])
    S.name = "binary string";
  else
    S.name = name;
  S.L = L;
  S.Z = Z;
  checkHeader(&S);
  cl = luaF_newLclosure(L, LoadByte(&S));
  setclLvalue(L, L->top, cl);
  luaD_inctop(L);
  cl->p = luaF_newproto(L);
  luaC_objbarrier(L, cl, cl->p); // add by wendal, refer: https://github.com/lua/lua/commit/f5eb809d3f1da13683cd02184042e67228206205
  if (*name == '@') {
    // 既然是从文件加载,那它就能作为调试信息中的源文件名
    size_t size = strlen(name);
    if (size > 0 && size <= LUAI_MAXSHORTLEN) {
      ts = luaS_newlstr(S.L, name, size);
    }
  }
  LoadFunction(&S, cl->p, ts);

  lua_assert(cl->nupvalues == cl->p->sizeupvalues);
  luai_verifycode(L, buff, cl->p);

  // 打印各部分的内存消耗
#if LUAT_UNDUMP_DEBUG
  LLOGD("str_size %d", str_size);
  LLOGD("debug_size %d", debug_size);
  LLOGD("const_size now %d", const_size);
  LLOGD("code_size now %d", code_size);
  LLOGD("code max now %d", code_max);
  LLOGD("ptr_offset %d", ptr_offset);
  LLOGD("proto size now %d", proto_size);
  LLOGD("max pc %d", max_pc);
  luat_os_print_heapinfo("func");
#endif

  return cl;
}

