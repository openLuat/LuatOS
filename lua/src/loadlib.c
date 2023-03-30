/*
** $Id: loadlib.c,v 1.130.1.1 2017/04/19 17:20:42 roberto Exp $
** Dynamic library loader for Lua
** See Copyright Notice in lua.h
**
** This module contains an implementation of loadlib for Unix systems
** that have dlfcn, an implementation for Windows, and a stub for other
** systems.
*/

#define loadlib_c
#define LUA_LIB

#include "lprefix.h"


#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "lua.h"

#include "lauxlib.h"
#include "lualib.h"

#include "luat_fs.h"
#undef fopen
#undef fclose
#define fopen luat_fs_fopen
#define fclose luat_fs_fclose

#define LUAT_LOG_TAG "loadlib"
#include "luat_log.h"

/*
** LUA_IGMARK is a mark to ignore all before it when building the
** luaopen_ function name.
*/
#if !defined (LUA_IGMARK)
#define LUA_IGMARK		"-"
#endif


/*
** LUA_CSUBSEP is the character that replaces dots in submodule names
** when searching for a C loader.
** LUA_LSUBSEP is the character that replaces dots in submodule names
** when searching for a Lua loader.
*/
#if !defined(LUA_CSUBSEP)
#define LUA_CSUBSEP		LUA_DIRSEP
#endif

#if !defined(LUA_LSUBSEP)
#define LUA_LSUBSEP		LUA_DIRSEP
#endif


/* prefix for open functions in C libraries */
#define LUA_POF		"luaopen_"

/* separator for open functions in C libraries */
#define LUA_OFSEP	"_"


/*
** unique key for table in the registry that keeps handles
** for all loaded C libraries
*/

#define LIB_FAIL	"open"


#define setprogdir(L)           ((void)0)


/*
** LUA_PATH_VAR and LUA_CPATH_VAR are the names of the environment
** variables that Lua check to set its paths.
*/
#if !defined(LUA_PATH_VAR)
#define LUA_PATH_VAR    "LUA_PATH"
#endif

#if !defined(LUA_CPATH_VAR)
#define LUA_CPATH_VAR   "LUA_CPATH"
#endif


#define AUXMARK         "\1"	/* auxiliary mark */

/* error codes for 'lookforfunc' */
#define ERRLIB		1
#define ERRFUNC		2

/*
** {======================================================
** 'require' function
** =======================================================
*/

static int checkload (lua_State *L, int stat, const char *filename) {
  if (stat) {  /* module loaded successfully? */
    lua_pushstring(L, filename);  /* will be 2nd argument to module */
    return 2;  /* return open function and file name */
  }
  else
    return luaL_error(L, "error loading module '%s' from file '%s':\n\t%s",
                          lua_tostring(L, 1), filename, lua_tostring(L, -1));
}

#ifndef LUAT_MODULE_SEARCH_PATH
#define LUAT_MODULE_SEARCH_PATH   "/%s.luac", "/%s.lua", \
  "/luadb/%s.luac", "/luadb/%s.lua",\
  "/lua/%s.luac", "/lua/%s.lua",\
  "",
#endif
static const char* search_paths[] = {
  LUAT_MODULE_SEARCH_PATH
};

char custom_search_paths[4][24] = {0};

int luat_search_module(const char* name, char* filename) {
  int index = 0;
  for (size_t i = 0; i < 4; i++)
  {
    if (strlen(custom_search_paths[i]) == 0)
      continue;
    sprintf(filename, custom_search_paths[i], name);
    if (luat_fs_fexist(filename)) return 0;
    filename[0] = 0x00;
  }
  while (1) {
    if (strlen(search_paths[index]) == 0)
      break;
    sprintf(filename, search_paths[index], name);
    if (luat_fs_fexist(filename)) return 0;
    index ++;
    filename[0] = 0x00;
  }
  return -1;
}

static int searcher_Lua (lua_State *L) {
  char filename[32] = {0};
  const char *name = luaL_checkstring(L, 1);
  int re = luat_search_module(name, filename);
  if (re == 0)
    re = checkload(L, (luaL_loadfile(L, filename) == LUA_OK), filename);
  return re;
}


int ll_require (lua_State *L) {
  const char *name = luaL_checkstring(L, 1);
  lua_settop(L, 1);  /* LOADED table will be at index 2 */
  lua_getfield(L, LUA_REGISTRYINDEX, LUA_LOADED_TABLE);
  lua_getfield(L, 2, name);  /* LOADED[name] */
  if (lua_toboolean(L, -1))  /* is it there? */
    return 1;  /* package is already loaded */
  /* else must load package */
  lua_pop(L, 1);  /* remove 'getfield' result */
  //findloader(L, name);
  //lua_pushstring(L, name);  /* pass name as argument to module loader */
  //lua_insert(L, -2);  /* name is 1st argument (before search data) */
  //lua_call(L, 2, 1);  /* run loader to load module */

  // add by wendal, 替换原有的逻辑
  lua_pushstring(L, name);
  //luat_os_print_heapinfo("go-loadfile");
  // LLOGD("module %s , searching......",name);
  if (searcher_Lua(L) == 2) {
    //luat_os_print_heapinfo("go-call");
    //LLOGD("module %s , found OK!!!",name);
    lua_gc(L, LUA_GCCOLLECT, 0);
    lua_pushstring(L, name);
    lua_call(L, 2, 1);
    //luat_os_print_heapinfo("after-call");
    lua_gc(L, LUA_GCCOLLECT, 0);
  }
  else {
    luaL_error(L, "module '%s' not found", name);
  }
  if (!lua_isnil(L, -1))  /* non-nil return? */
    lua_setfield(L, 2, name);  /* LOADED[name] = returned value */
  if (lua_getfield(L, 2, name) == LUA_TNIL) {   /* module set no value? */
    lua_pushboolean(L, 1);  /* use true as result */
    lua_pushvalue(L, -1);  /* extra copy to be returned */
    lua_setfield(L, 2, name);  /* LOADED[name] = true */
  }
  return 1;
}

/* }====================================================== */



/*
** {======================================================
** 'module' function
** =======================================================
*/
#if defined(LUA_COMPAT_MODULE)

/*
** changes the environment variable of calling function
*/
static void set_env (lua_State *L) {
  lua_Debug ar;
  if (lua_getstack(L, 1, &ar) == 0 ||
      lua_getinfo(L, "f", &ar) == 0 ||  /* get calling function */
      lua_iscfunction(L, -1))
    luaL_error(L, "'module' not called from a Lua function");
  lua_pushvalue(L, -2);  /* copy new environment table to top */
  lua_setupvalue(L, -2, 1);
  lua_pop(L, 1);  /* remove function */
}


static void dooptions (lua_State *L, int n) {
  int i;
  for (i = 2; i <= n; i++) {
    if (lua_isfunction(L, i)) {  /* avoid 'calling' extra info. */
      lua_pushvalue(L, i);  /* get option (a function) */
      lua_pushvalue(L, -2);  /* module */
      lua_call(L, 1, 0);
    }
  }
}


static void modinit (lua_State *L, const char *modname) {
  const char *dot;
  lua_pushvalue(L, -1);
  lua_setfield(L, -2, "_M");  /* module._M = module */
  lua_pushstring(L, modname);
  lua_setfield(L, -2, "_NAME");
  dot = strrchr(modname, '.');  /* look for last dot in module name */
  if (dot == NULL) dot = modname;
  else dot++;
  /* set _PACKAGE as package name (full module name minus last part) */
  lua_pushlstring(L, modname, dot - modname);
  lua_setfield(L, -2, "_PACKAGE");
}


static int ll_module (lua_State *L) {
  const char *modname = luaL_checkstring(L, 1);
  int lastarg = lua_gettop(L);  /* last parameter */
  luaL_pushmodule(L, modname, 1);  /* get/create module table */
  /* check whether table already has a _NAME field */
  if (lua_getfield(L, -1, "_NAME") != LUA_TNIL)
    lua_pop(L, 1);  /* table is an initialized module */
  else {  /* no; initialize it */
    lua_pop(L, 1);
    modinit(L, modname);
  }
  lua_pushvalue(L, -1);
  set_env(L);
  dooptions(L, lastarg);
  return 1;
}


static int ll_seeall (lua_State *L) {
  luaL_checktype(L, 1, LUA_TTABLE);
  if (!lua_getmetatable(L, 1)) {
    lua_createtable(L, 0, 1); /* create new metatable */
    lua_pushvalue(L, -1);
    lua_setmetatable(L, 1);
  }
  lua_pushglobaltable(L);
  lua_setfield(L, -2, "__index");  /* mt.__index = _G */
  return 0;
}

#endif
/* }====================================================== */




static int ll_unload(lua_State *L) {
  const char* name = luaL_checkstring(L, 1);
  lua_settop(L, 1);  /* LOADED table will be at index 2 */
  lua_getfield(L, LUA_REGISTRYINDEX, LUA_LOADED_TABLE);
  lua_pushnil(L);
  lua_setfield(L, -2, name);
  lua_settop(L, 0);
  lua_gc(L, LUA_GCCOLLECT, 0);
  return 0;
}

LUAMOD_API int luaopen_package (lua_State *L) {
  #ifndef LUAT_MEMORY_OPT_G_FUNCS
  lua_pushcfunction(L, ll_require);
  lua_setglobal(L, "require");
  lua_pushcfunction(L, ll_unload);
  lua_setglobal(L, "unload");
  #endif
#if defined(LUA_COMPAT_MODULE)
  // 兼容LuatOS-Air
  lua_pushcfunction(L, ll_module);
  lua_setglobal(L, "module");
  lua_newtable(L);
  lua_pushcfunction(L, ll_seeall);
  lua_setfield(L, -2, "seeall");
#else
  lua_pushnil(L);
#endif
  return 1;
}

#if 0
LUAMOD_API int luaopen_package (lua_State *L) {
  createclibstable(L);
  luaL_newlib(L, pk_funcs);  /* create 'package' table */
  createsearcherstable(L);
  /* set paths */
  setpath(L, "path", LUA_PATH_VAR, LUA_PATH_DEFAULT);
  setpath(L, "cpath", LUA_CPATH_VAR, LUA_CPATH_DEFAULT);
  /* store config information */
  lua_pushliteral(L, LUA_DIRSEP "\n" LUA_PATH_SEP "\n" LUA_PATH_MARK "\n"
                     LUA_EXEC_DIR "\n" LUA_IGMARK "\n");
  lua_setfield(L, -2, "config");
  /* set field 'loaded' */
  luaL_getsubtable(L, LUA_REGISTRYINDEX, LUA_LOADED_TABLE);
  lua_setfield(L, -2, "loaded");
  /* set field 'preload' */
  luaL_getsubtable(L, LUA_REGISTRYINDEX, LUA_PRELOAD_TABLE);
  lua_setfield(L, -2, "preload");
  lua_pushglobaltable(L);
  lua_pushvalue(L, -2);  /* set 'package' as upvalue for next lib */
  luaL_setfuncs(L, ll_funcs, 1);  /* open lib into global table */
  lua_pop(L, 1);  /* pop global table */
  return 1;  /* return 'package' table */
}
#endif
