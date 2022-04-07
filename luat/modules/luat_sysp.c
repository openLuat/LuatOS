
#include "luat_base.h"
#include "luat_fs.h"

#define LUAT_LOG_TAG "sysp"
#include "luat_log.h"

extern lua_State *L;

int luat_main_call(void);

/**
 * 这里的luat被当成库, 首先执行luat_sysp_init完成基础的初始化, 然后每隔tick时间, 调用一次luat_sysp_loop
 * require "sys"
 * 
 * ... 用户代码 ....
 * 
 * -- 注意, 没有sys.run()
*/
int luat_sysp_init(void) {
  LLOGI("LuatOS@%s %s, Build: " __DATE__ " " __TIME__, luat_os_bsp(), LUAT_VERSION);
  // 1. 初始化文件系统
  luat_fs_init();

  return luat_main_call();
  // 没有重启, 没有退出
}

static void l_message (const char *pname, const char *msg) {
  if (pname) LLOGE("%s: ", pname);
  LLOGE("%s", msg);
}

static int safeRun(lua_State *L) {
  //LLOGD("CALL C safeRun\n");
  lua_settop(L, 0); // 清空堆栈
  lua_getglobal(L, "sys");
  if (lua_isnil(L, -1)) {
    return 0;
  }
  lua_getfield(L, -1, "safeRun");
  if (lua_isfunction(L, -1)) {
    //LLOGD("CALL safeRun\n");
    lua_call(L, 0, 0);
    lua_pushboolean(L, 1);
    return 1;
  }
  else {
    LLOGE("sys.safeRun NOT FOUND!!\n");
  }
  return 0;
}

int luat_sysp_loop(void) {
  lua_pushcfunction(L, &safeRun);
  int status = lua_pcall(L, 0, 1, 0);  /* do the call */
  int result = lua_toboolean(L, -1);
  if (status != LUA_OK) {
    const char *msg = lua_tostring(L, -1);
    l_message("LUAT", msg);
    lua_pop(L, 1);  /* remove message */
  }
  //LLOGD("status %d result %d", status, result);
  if (!result)
    return LUA_ERRERR;
  return status;
}
