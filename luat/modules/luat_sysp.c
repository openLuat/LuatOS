
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
  #if LUAT_VERSION_BETA
  LLOGD("This is a beta version, for testing");
  #endif
  // 1. 初始化文件系统
  luat_fs_init();

  return luat_main_call();
  // 没有重启, 没有退出
}

static int safeRun(lua_State *L) {
  lua_settop(L, 0); // 清空堆栈
  lua_getglobal(L, "safeRun");
  if (lua_isfunction(L, -1)) {
    lua_call(L, 0, 0);
  }
  return 0;
}

int luat_sysp_loop(void) {
  lua_pushcfunction(L, &safeRun);
  int status = lua_pcall(L, 0, 1, 0);  /* do the call */
  return status;
}
