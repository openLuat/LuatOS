

#include "luat_base.h"
#include "luat_mem.h"
#include "luat_fs.h"
#include "stdio.h"
#include "luat_msgbus.h"
#include "luat_timer.h"
#include "luat_rtos.h"
#include "luat_gpio.h"
#include "luat_ota.h"
#include "luat_ems_server.h"

#define LUAT_LOG_TAG "main"
#include "luat_log.h"

#ifdef LUAT_USE_ERRDUMP
#include "luat_errdump.h"
#endif

#ifdef LUAT_USE_PROFILER
#include "luat_profiler.h"
#endif

#ifdef LUAT_USE_WDT
#include "luat_wdt.h"
#endif

#ifdef LUAT_USE_HMETA
#include "luat_hmeta.h"
#endif

static int report (lua_State *L, int status);

lua_State *L;

static luat_rtos_timer_t luar_error_timer;
static char model[32] = {0};

static LUAT_RT_RET_TYPE l_timer_error_cb(LUAT_RT_CB_PARAM) {
  LLOGE("未找到main.lua,请刷入脚本以运行程序,luatos快速入门教程: https://docs.openluat.com");
  LLOGE("The main.lua not found, please flash the script to run the program, luatos quick start: https://docs.openluat.com");
}

int luat_search_module(const char* name, char* filename);
void luat_os_print_heapinfo(const char* tag);
void luat_force_gc_all(void)
{
	lua_gc(L, LUA_GCCOLLECT, 0);
}

static int dolibrary (lua_State *L, const char *name) {
//   int status;
  lua_getglobal(L, "require");
  lua_pushstring(L, name);
  lua_call(L, 1, 1);  /* call 'require(name)' */
  lua_setglobal(L, name);  /* global[name] = require return */
  return 0;
}

int luat_main_demo() { // 这是验证LuatVM最基础的消息/定时器/Task机制是否正常
  return luaL_dostring(L, "local sys = require \"sys\"\n"
                          "log.info(\"main\", os.date())\n"
                          "leda = gpio.setup(3, 0)"
                          "sys.taskInit(function ()\n"
                          "  while true do\n"
                          "    log.info(\"hi\", rtos.meminfo())\n"
                          "    sys.wait(500)\n"
                          "    leda(1)\n"
                          "    sys.wait(500)\n"
                          "    leda(0)\n"
                          "    log.info(\"main\", os.date())\n"
                          "  end\n"
                          "end)\n"
                          "sys.run()\n");
}

int luat_restore_main(void) {
  return luaL_dostring(L, ems_server_lua_code);
}

static int pmain(lua_State *L) {
    int re = -2;
    #ifndef LUAT_MAIN_DEMO
    char filename[32] = {0};
    #endif

    // 加载内置库
    luat_openlibs(L);
    #if !defined(LUAT_USE_PSRAM)
    lua_gc(L, LUA_GCCOLLECT, 0);
    #endif
    luat_os_print_heapinfo("loadlibs");

    lua_gc(L, LUA_GCSETPAUSE, 90); // 设置`垃圾收集器间歇率`要低于100%

  
	// Air8000硬等最多200ms, 梁健要加的, 有问题找他
  #if defined(LUAT_USE_AIRLINK)
  extern void luat_airlink_wait_ready(void);
  luat_airlink_wait_ready();
  #endif

#ifdef LUAT_HAS_CUSTOM_LIB_INIT
    luat_custom_init(L);
#endif
    if (re == -2) {
      #ifndef LUAT_MAIN_DEMO
        // add by wendal, 自动加载sys和sysplus
        #ifndef LUAT_CONF_AUTOLOAD_SYS_DISABLE
        dolibrary(L, "sys");
        #ifndef LUAT_CONF_AUTOLOAD_SYSPLUS_DISABLE
        dolibrary(L, "sysplus");
        #endif
        #endif
        // 急救服务判断
        uint8_t emg_enable = 0;
        uint8_t exception_max_count = 10;       // 默认10次异常重启启动急救服务
        uint8_t normal_max_count = 20;         // 默认20次正常重启退出急救服务
        uint32_t interval = 180;               // 默认3小时上报间隔
        uint8_t power_exception = 0;           // 记录异常开机次数
        uint8_t power_normal = 0;              // 记录正常开机次数
        char emg_key[32] = {0};
        
        // 使用 luat_ems_server 接口读取配置
	      luat_ems_server_read_config_all(&emg_enable, emg_key, &interval, &exception_max_count, &normal_max_count, &power_exception, &power_normal);
        if (emg_enable) {
          LLOGE("Emergency service enabled, exception count: %d, threshold: %d", power_exception, exception_max_count);
          // 检查异常计数是否超过阈值
          if (power_exception >= exception_max_count) {
            LLOGE("Emergency service enabled, normal count: %d, threshold: %d", power_normal, normal_max_count);
            if (power_normal >= normal_max_count) {
              LLOGE("Emergency service restoring original main.lua execution");
              if (luat_search_module("main", filename) == 0) {
                re = luaL_dofile(L, filename);
                if (re != 0) {
                  LLOGE("Failed to load main.lua, error code: %d", re);
                  re = luat_restore_main(); // 加载失败时尝试加载急救脚本
                }
              }
              else {
                re = -1;
                luar_error_timer = luat_create_rtos_timer(l_timer_error_cb, NULL, NULL);
                luat_start_rtos_timer(luar_error_timer, 1000, 1);
                luaL_error(L, "module '%s' not found", "main");
              }
            }
            else
            {
              LLOGE("Emergency service enabled, normal count: %d, threshold: %d", power_normal, normal_max_count);
              re = luat_restore_main();   // Restore and load emergency script
              if (re != 0) {
                LLOGE("Failed to load emergency script, error code: %d", re);
                // 尝试加载main.lua作为备选
                if (luat_search_module("main", filename) == 0) {
                  re = luaL_dofile(L, filename);
                }
              }
            }
          } 
          else {
            if (luat_search_module("main", filename) == 0) {
                re = luaL_dofile(L, filename);
                if (re != 0) {
                  LLOGE("Failed to load main.lua, error code: %d", re);
                  // 加载失败时尝试加载急救脚本
                  re = luat_restore_main();
                }
            }
            else {
              re = -1;
              luar_error_timer = luat_create_rtos_timer(l_timer_error_cb, NULL, NULL);
              luat_start_rtos_timer(luar_error_timer, 1000, 1);
              luaL_error(L, "module '%s' not found", "main");
            }
          }
        }
        else {
          if (luat_search_module("main", filename) == 0) {
              re = luaL_dofile(L, filename);
              if (re != 0) {
                LLOGE("Failed to load main.lua, error code: %d", re);
                // 尝试加载急救脚本作为备选
                re = luat_restore_main();
              }
          }
          else {
            LLOGE("main.lua not found, trying emergency script");
            re = luat_restore_main(); // 找不到main.lua时尝试加载急救脚本
          }
        }
      #else
        re = luat_main_demo();
      #endif
    }
        
    report(L, re);
    lua_pushboolean(L, re == LUA_OK);  /* signal no errors */
    return 1;
}

/*
** Prints an error message, adding the program name in front of it
** (if present)
*/
static void l_message (const char *pname, const char *msg) {
  if (pname) LLOGE("%s: ", pname);
#ifdef LUAT_LOG_NO_NEWLINE
  LLOGE("%s", strlen(msg), msg);
#else
  LLOGE("%s\n", msg);
#endif
}


/*
** Check whether 'status' is not OK and, if so, prints the error
** message on the top of the stack. It assumes that the error object
** is a string, as it was either generated by Lua or by 'msghandler'.
*/
static int report (lua_State *L, int status) {
  size_t len = 0;
  if (status != LUA_OK) {
    const char *msg = lua_tolstring(L, -1, &len);
    //luaL_traceback(L, L, msg, 1);
    //msg = lua_tolstring(L, -1, &len);
    LLOGE("Luat: ");
    LLOGE("%s", msg);
    // LLOGD("MSG2 ==> %s %d", msg, len);
    // l_message("LUAT", msg);
#ifdef LUAT_USE_ERRDUMP
    luat_errdump_save_file((const uint8_t *)msg, strlen(msg));
#endif
    lua_pop(L, 1);  /* remove message */
  }
  return status;
}

static int panic (lua_State *L) {
  LLOGE("PANIC: unprotected error in call to Lua API (%s)\n",
                        lua_tostring(L, -1));
  return 0;  /* return to Lua to abort */
}


int luat_main_call(void) {
  // 4. init Lua State
  int status = 0;
  int result = 0;
#ifdef LUAT_USE_PROFILER
  L = lua_newstate(luat_profiler_alloc, NULL);
#else
  L = lua_newstate(luat_heap_alloc, NULL);
#endif
  if (L == NULL) {
    l_message("lua", "cannot create state: not enough memory\n");
    goto _exit;
  }
  if (L) lua_atpanic(L, &panic);
  //print_list_mem("after lua_newstate");
  lua_pushcfunction(L, &pmain);  /* to call 'pmain' in protected mode */
  //lua_pushinteger(L, argc);  /* 1st argument */
  //lua_pushlightuserdata(L, argv); /* 2nd argument */
  status = lua_pcall(L, 0, 1, 0);  /* do the call */
  result = lua_toboolean(L, -1);  /* get result */
  report(L, status);
  //lua_close(L);
_exit:
  return result;
}

/**
 * 常规流程, 单一入口, 执行脚本.
 * require "sys"
 * 
 * ... 用户代码 ....
 * 
 * sys.run() 
*/
int luat_main (void) {
  
  #ifdef LUAT_USE_HMETA
  luat_hmeta_model_name(model);
  #endif
  if (model[0] == 0) {
    const char* tmp = luat_os_bsp();
    memcpy(model, tmp, strlen(tmp));
  }
  #ifdef LUAT_BSP_VERSION
  #ifdef LUAT_CONF_VM_64bit
  LLOGI("LuatOS@%s base %s bsp %s 64bit", model, LUAT_VERSION, LUAT_BSP_VERSION);
  #else
  LLOGI("LuatOS@%s base %s bsp %s 32bit", model, LUAT_VERSION, LUAT_BSP_VERSION);
  #endif
  /// 支持时间无关的编译, 符合幂等性
  #ifdef LUAT_BUILD_FINGER
  LLOGI("ROM Finger: " LUAT_BUILD_FINGER);
  #else
  LLOGI("ROM Build: " __DATE__ " " __TIME__);
  #endif
  // #if LUAT_VERSION_BETA
  // LLOGD("This is a beta/snapshot version, for testing");
  // #endif
  #else
  #ifdef LUAT_CONF_VM_64bit
  LLOGI("LuatOS@%s %s, Build: " __DATE__ " " __TIME__ " 64bit", model, LUAT_VERSION);
  #else
  LLOGI("LuatOS@%s %s, Build: " __DATE__ " " __TIME__ " 32bit", model, LUAT_VERSION);
  #endif
  #if LUAT_VERSION_BETA
  LLOGD("This is a beta version, for testing");
  #endif
  #endif

  // 1. 初始化文件系统
  luat_fs_init();
#ifdef LUAT_USE_OTA
  if (luat_ota_exec() == 0) {
    luat_os_reboot(5);
  }
#endif


  luat_main_call();
  LLOGE("Lua VM exit!! reboot in %dms", LUAT_EXIT_REBOOT_DELAY);
#ifdef LUAT_USE_WDT
  for (size_t i = 1; i < LUAT_EXIT_REBOOT_DELAY / 1000; i++)
  {
    luat_wdt_feed();
    luat_timer_mdelay(1000);
  }
  luat_ota_reboot(1000);
#else
  luat_ota_reboot(LUAT_EXIT_REBOOT_DELAY);
#endif
  // 往下是肯定不会被执行的
  return 0;
}

