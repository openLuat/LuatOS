#include "luat_base.h"
#include "luat_malloc.h"

#include "lprefix.h"


#include <stddef.h>

#include "lua.h"
#include "lapi.h"

#include "lobject.h"
#include "lstate.h"
#include "lundump.h"
#include "luat_zbuff.h"

int luf_dump(lua_State *L, const Proto *f, lua_Writer w, void *data, int strip, int ptroffset);

LClosure *luat_luf_undump(lua_State *L, const char* ptr, size_t len, const char *name);

void luat_luf_cmp(lua_State *L, const Proto* p1, const Proto *p2);

static int writer (lua_State *L, const void *b, size_t size, void *B) {
  (void)L;
  luaL_addlstring((luaL_Buffer *) B, (const char *)b, size);
  return 0;
}

static int l_luf_dump(lua_State* L) {
  luaL_Buffer b;
  TValue *o;
  int strip = lua_toboolean(L, 2);
  uint32_t ptroffset = 0;
  luaL_checktype(L, 1, LUA_TFUNCTION);

  luat_zbuff_t *zbuff = NULL;

  if (lua_isuserdata(L, 3)) {
    zbuff = luaL_checkudata(L, 3, LUAT_ZBUFF_TYPE);
    ptroffset = (uint32_t)zbuff->addr;
  }
  else if (lua_isinteger(L, 3)) {
    ptroffset = luaL_checkinteger(L, 3);
  }

  lua_settop(L, 1);
  luaL_buffinit(L,&b);

  lua_lock(L);
  api_checknelems(L, 1);
  o = L->top - 1;
  if (luf_dump(L, getproto(o), writer, &b, strip, ptroffset) != 0)
    return luaL_error(L, "unable to dump given function");
  luaL_pushresult(&b);
  lua_unlock(L);
  return 1;
}

static int l_luf_undump(lua_State* L) {
  size_t len;
  const char* data = luaL_checklstring(L, 1, &len);
  luat_luf_undump(L, data, len, NULL);
  return 1;
}

static int l_luf_cmp(lua_State* L) {
  luaL_checktype(L, 1, LUA_TFUNCTION);
  luaL_checktype(L, 2, LUA_TFUNCTION);

  lua_settop(L, 2);

  TValue *o;
  Proto* p1;
  Proto* p2;

  o = L->top - 2;
  p1 = getproto(o);
  o = L->top - 1;
  p2 = getproto(o);

  luat_luf_cmp(L, p1, p2);

  return 0;
}

#include "rotable2.h"
static const rotable_Reg_t reg_luf[] =
{
    { "dump" ,        ROREG_FUNC(l_luf_dump)},
    { "undump" ,      ROREG_FUNC(l_luf_undump)},
    { "cmp",          ROREG_FUNC(l_luf_cmp)},
	  { NULL,           {}}
};

LUAMOD_API int luaopen_luf( lua_State *L ) {
    luat_newlib2(L, reg_luf);
    return 1;
}
