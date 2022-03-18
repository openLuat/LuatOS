#ifndef ROTABLE2_H_
#define ROTABLE2_H_

#include "lua.h"

typedef struct rotable_Reg_Value {
  int type;
  union 
  {
    lua_CFunction func;
    lua_Number numvalue;
    const char* strvalue;
    lua_Integer intvalue;
    void*       ptr;
  } value;
}rotable_Reg_Value_t;

/* exactly the same as luaL_Reg, but since we are on small embedded
 * microcontrollers, we don't assume that you have `lauxlib.h`
 * available in your build! */
typedef struct rotable_Reg2 {
  char const* name;
  rotable_Reg_Value_t value;
} rotable_Reg_t;

#define ROREG_FUNC(fvalue) {.type=LUA_TFUNCTION, .value={.func=fvalue}}
#define ROREG_NUM(fvalue)  {.type=LUA_TNUMBER,   .value={.numvalue=fvalue}}
#define ROREG_INT(fvalue)  {.type=LUA_TINTEGER,  .value={.intvalue=fvalue}}
#define ROREG_STR(fvalue)  {.type=LUA_TSTRING,   .value={.strvalue=fvalue}}
#define ROREG_PTR(fvalue)  {.type=LUA_TLIGHTUSERDATA,   .value={.ptr=fvalue}}

#ifndef ROTABLE_EXPORT
#  define ROTABLE_EXPORT extern
#endif

/* compatible with `luaL_newlib()`, and works with `luaL_Reg` *and*
 * `rotable_Reg` arrays (in case you don't use `lauxlib.h`) */
ROTABLE_EXPORT void rotable2_newlib( lua_State* L, void const* reg );

/* Since userdatas can not be used as `__index` meta methods directly
 * this function creates a C closure that looks up keys in a given
 * `rotable_Reg` array. */
ROTABLE_EXPORT void rotable2_newidx( lua_State* L, void const* reg );

#endif /* ROTABLE_H_ */

