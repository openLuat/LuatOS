#include "luat_base.h"
#include "luat_msgbus.h"
#include "luat_fs.h"
#include "luat_timer.h"
#include <stdlib.h>

LUAMOD_API int luaopen_win32( lua_State *L );
int luaopen_lfs(lua_State * L);
int luaopen_rs232_core(lua_State * L);

static const luaL_Reg loadedlibs[] = {
  {"_G", luaopen_base}, // _G
  {LUA_LOADLIBNAME, luaopen_package}, // require
  {LUA_COLIBNAME, luaopen_coroutine}, // coroutine协程库
  {LUA_TABLIBNAME, luaopen_table},    // table库,操作table类型的数据结构
  {LUA_IOLIBNAME, luaopen_io},        // io库,操作文件
  {LUA_OSLIBNAME, luaopen_os},        // os库,已精简
  {LUA_STRLIBNAME, luaopen_string},   // string库,字符串操作
  {LUA_MATHLIBNAME, luaopen_math},    // math 数值计算
//  {LUA_UTF8LIBNAME, luaopen_utf8},
  {LUA_DBLIBNAME, luaopen_debug},     // debug库,已精简
#if defined(LUA_COMPAT_BITLIB)
  {LUA_BITLIBNAME, luaopen_bit32},    // 不太可能启用
#endif
  {"rtos", luaopen_rtos},             // rtos底层库, 核心功能是队列和定时器
  {"log", luaopen_log},               // 日志库
  {"timer", luaopen_timer},           // 延时库
  {"pack", luaopen_pack},             // pack.pack/pack.unpack
  {"json", luaopen_cjson},             // json
  {"zbuff", luaopen_zbuff},            // 
  {"mqttcore", luaopen_mqttcore},      // 
  {"libcoap", luaopen_libcoap},        // 
  {"crypto", luaopen_crypto},
  {NULL, NULL}
};

// 按不同的rtconfig加载不同的库函数
void luat_openlibs(lua_State *L) {
    // 初始化队列服务
    luat_msgbus_init();
    //print_list_mem("done>luat_msgbus_init");
    // 加载系统库
    const luaL_Reg *lib;
    /* "require" functions from 'loadedlibs' and set results to global table */
    for (lib = loadedlibs; lib->func; lib++) {
        luaL_requiref(L, lib->name, lib->func, 1);
        lua_pop(L, 1);  /* remove lib */
        //extern void print_list_mem(const char* name);
        //print_list_mem(lib->name);
    }
}

void luat_os_reboot(int code) {
    exit(code);
}

const char* luat_os_bsp(void) {
    return "sysp";
}

extern const struct luat_vfs_filesystem vfs_fs_posix;
extern const struct luat_vfs_filesystem vfs_fs_luadb;

#ifdef LUAT_USE_VFS_INLINE_LIB
extern const char luadb_inline[];
#endif

int luat_fs_init(void) {
	#ifdef LUAT_USE_FS_VFS
	// vfs进行必要的初始化
	luat_vfs_init(NULL);
	// 注册vfs for posix 实现
	luat_vfs_reg(&vfs_fs_posix);
	luat_vfs_reg(&vfs_fs_luadb);

	luat_fs_conf_t conf = {
		.busname = "",
		.type = "posix",
		.filesystem = "posix",
		.mount_point = "", // window环境下, 需要支持任意路径的读取,不能强制要求必须是/
	};
	luat_fs_mount(&conf);
	#ifdef LUAT_USE_VFS_INLINE_LIB
	luat_fs_conf_t conf2 = {
		.busname = (char*)luadb_inline,
		.type = "luadb",
		.filesystem = "luadb",
		.mount_point = "/luadb/",
	};
	luat_fs_mount(&conf2);
	#endif
	return 0;
	#else
	return 0;
	#endif
}

/** 设备进入待机模式 */
void luat_os_standy(int timeout) {
    return; // nop
}

void luat_ota_reboot(int timeout_ms) {
  if (timeout_ms > 0)
    luat_timer_mdelay(timeout_ms);
  luat_os_reboot(1);
}

