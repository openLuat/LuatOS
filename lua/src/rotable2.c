
/**
 * rotable 实现 lua下的只读table, 用于通常只用于库的注册.</p>
 * 从原理上说, 是声明一个userdata内存块, 然后通过元表,将其伪装成table.<p/>
 * 因为元表是共享的,而userdata内存块也很小(小于30字节),而且不会与方法的数量有关, 节省大量内存. 
 * 
 */
#include <stddef.h>
#include <string.h>
#include <stdlib.h>
#include "lua.h"
#include "rotable2.h"


/* The lookup code uses binary search on sorted `rotable_Reg` arrays
 * to find functions/methods. For a small number of elements a linear
 * search might be faster. */
#ifndef ROTABLE_BINSEARCH_MIN
#  define ROTABLE_BINSEARCH_MIN  5
#endif


typedef struct {
  int n;
} rotable;


static char const unique_address[ 1 ] = { 0 };


static int reg_compare(void const* a, void const* b) {
  return strcmp( (char const*)a, ((const rotable_Reg_t*)b)->name );
}

static int rotable_push_rovalue(lua_State *L, const rotable_Reg_t* q) {
    switch (q->value.type)
  {
  case LUA_TFUNCTION:
    lua_pushcfunction( L, q->value.value.func );
    break;
  case LUA_TINTEGER:
    lua_pushinteger( L, q->value.value.intvalue );
    break;
  case LUA_TSTRING:
    lua_pushstring( L, q->value.value.strvalue );
    break;
  case LUA_TNUMBER:
    lua_pushnumber( L, q->value.value.numvalue );
    break;
  case LUA_TLIGHTUSERDATA:
    lua_pushlightuserdata(L, q->value.value.ptr);
    break;
  default:
    return 0;
  }
  return 1;
}


static rotable* check_rotable( lua_State* L, int idx, char const* func ) {
  rotable* t = (rotable*)lua_touserdata( L, idx );
  if( t ) {
    if( lua_getmetatable( L, idx ) ) {
      lua_pushlightuserdata( L, (void*)unique_address );
      lua_rawget( L, LUA_REGISTRYINDEX );
      if( !lua_rawequal( L, -1, -2 ) )
        t = 0;
      lua_pop( L, 2 );
    }
  }
  if( !t ) {
    char const* type = lua_typename( L, lua_type( L, idx ) );
    if( lua_type( L, idx ) == LUA_TLIGHTUSERDATA ) {
      type = "light userdata";
    } else if( lua_getmetatable( L, idx ) ) {
      lua_getfield( L, -1, "__name" );
      lua_replace( L, -2 ); /* we don't need the metatable anymore */
      if( lua_type( L, -1 ) == LUA_TSTRING )
        type = lua_tostring( L, -1 );
    }
    lua_pushfstring( L, "bad argument #%d to '%s' "
                     "(rotable expected, got %s)", idx, func, type );
    lua_error( L );
  }
  return t;
}


static const rotable_Reg_t* find_key( const rotable_Reg_t* p, int n,
                                    char const* s ) {
  (void)n;
  if( s ) {
    for( ; p->name != NULL; ++p ) {
      if( 0 == reg_compare( s, p ) )
        return p;
    }
  }
  return 0;
}


static int rotable_func_index( lua_State* L ) {
  char const* s = lua_tostring( L, 2 );
  const rotable_Reg_t* p = (const rotable_Reg_t*)lua_touserdata( L, lua_upvalueindex( 1 ) );
  const rotable_Reg_t* p2 = p;
  int n = lua_tointeger( L, lua_upvalueindex( 2 ) );
  p = find_key( p, n, s );
  if( p ) {
    rotable_push_rovalue(L, p);
  }
  else {
    // 看看第一个方法是不是__index, 如果是的话, 调用之
    if (p2->name != NULL && !strcmp("__index", p2->name)) {
      lua_pushcfunction(L, p2->value.value.func);
      lua_pushvalue(L, 2);
      lua_call(L, 1, 1);
      return 1;
    }
    lua_pushnil( L );
  }
  return 1;
}


static int rotable_udata_index( lua_State* L ) {
  rotable* t = (rotable*)lua_touserdata( L, 1 );
  char const* s = lua_tostring( L, 2 );
  const rotable_Reg_t* p = 0;
  lua_getuservalue( L, 1 );
  p = (const rotable_Reg_t*)lua_touserdata( L, -1 );
  const rotable_Reg_t* p2 = p;
  p = find_key( p, t->n, s );
  if( p ) {
    if (rotable_push_rovalue(L, p)) {
      return 1;
    }
    return 0;
  }
  else {
    // 看看第一个方法是不是__index, 如果是的话, 调用之
    if (p2->name != NULL && !strcmp("__index", p2->name)) {
      lua_pushcfunction(L, p2->value.value.func);
      lua_pushvalue(L, 2);
      lua_call(L, 1, 1);
      return 1;
    }
    lua_pushnil( L );
  }
  return 1;
}


static int rotable_udata_len( lua_State* L ) {
  lua_pushinteger( L, 0 );
  return 1;
}


static int rotable_iter( lua_State* L ) {
  check_rotable( L, 1, "__pairs iterator" );
  char const* key;
  const rotable_Reg_t* q = 0;
  const rotable_Reg_t* p = 0;

  int isnil = lua_isnil(L, 2);
  lua_getuservalue( L, 1 );
  p = (const rotable_Reg_t*)lua_touserdata( L, -1 );

  if (isnil) {
    lua_pushstring(L, p->name);
    rotable_push_rovalue(L, p);
    return 2;
  }
  key = lua_tostring(L, 2);

  for( q = p; q->name != NULL; ++q ) {
      if( 0 == reg_compare( key, q ) ) {
        ++q;
        break;
      }
  }
  if (q == NULL || q->name == NULL) {
      return 0;
  }
  lua_pushstring( L, q->name );
  rotable_push_rovalue(L, q);
  return 2;
}


static int rotable_udata_pairs( lua_State* L ) {
  lua_pushcfunction( L, rotable_iter );
  lua_pushvalue( L, 1 );
  lua_pushnil( L );
  return 3;
}

/**
 * 与lua_newlib对应的函数, 用于生成一个库table,区别是lua_newlib生成普通table,这个函数生成rotable.
 */
#include "lgc.h"
ROTABLE_EXPORT void rotable2_newlib( lua_State* L, void const* v ) {
  const rotable_Reg_t* reg = (const rotable_Reg_t*)v;
  rotable* t = (rotable*)lua_newuserdata( L, sizeof( *t ) );
  luaC_fix(L, L->l_G->allgc);
  lua_pushlightuserdata( L, (void*)unique_address );
  lua_rawget( L, LUA_REGISTRYINDEX );
  if( !lua_istable( L, -1 ) ) {
    lua_pop( L, 1 );
    lua_createtable( L, 0, 5 );
    lua_pushcfunction( L, rotable_udata_index );
    lua_setfield( L, -2, "__index" );
    lua_pushcfunction( L, rotable_udata_len );
    lua_setfield( L, -2, "__len" );
    lua_pushcfunction( L, rotable_udata_pairs );
    lua_setfield( L, -2, "__pairs" );
    lua_pushboolean( L, 0 );
    lua_setfield( L, -2, "__metatable" );
    lua_pushliteral( L, "rotable" );
    lua_setfield( L, -2, "__name" );
    lua_pushlightuserdata( L, (void*)unique_address );
    lua_pushvalue( L, -2 );
    lua_rawset( L, LUA_REGISTRYINDEX );
  }
  lua_setmetatable( L, -2 );
#if LUA_VERSION_NUM < 503
  t->p = reg;
#else
  lua_pushlightuserdata( L, (void*)reg );
  lua_setuservalue( L, -2 );
#endif
}

/**
 * 为自定义对象也生成rotable形式的元表, 这个形式比rotable_newlib需要更多内存,但起码是一个解决办法.
 */
ROTABLE_EXPORT void rotable2_newidx( lua_State* L, void const* v ) {
  lua_pushlightuserdata( L, (void*)v);
  lua_pushcclosure( L, rotable_func_index, 1 );
}

