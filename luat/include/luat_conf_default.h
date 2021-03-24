
#ifndef LUAT_CONF_DEFAULT

// 首先, 必须先引入luat_conf.h
#ifndef LUAT_CONF_BSP
#error "include luat_conf_bsp.h first!!!"
#endif

//------------------------------
// Lua虚拟机相关特性
//------------------------------


// 是否使用64bit的虚拟机,默认关闭
#ifndef LUAT_CONF_VM_64bit
    #define LUA_32BITS
#endif

// 是否使用平台自定义的sprintf方法
// 默认使用printf.h提供的l_sprintf
#ifndef LUAT_CONF_CUSTOM_SPRINTF
    #include "printf.h"
    #define l_sprintf snprintf_
#endif

// 是否使用静态LuaState状态
#ifndef LUAT_CONF_LUASTATE_NOT_STATIC
    #define FEATURE_STATIC_LUASTATE 1
#endif

// LUA lauxlib buff system大小
#ifndef LUAT_CONF_LAUX_BUFFSIZE
    #define LUAL_BUFFERSIZE 256
#else
    #define LUAL_BUFFERSIZE LUAT_CONF_LAUX_BUFFSIZE
#endif

//------------------------------
// LuatOS 特性
//-----------------------------

// 是否使用rotable节省内置库的固定内存
#ifndef LUAT_CONF_DISABLE_ROTABLE
    #define LUAT_USING_ROTABLE
#endif

// 自定义VM退出时的钩子(异常报错退出, 或者升级后重启)
#ifdef LUAT_CONF_CUSTOM_VM_EXIT_HOOK
    void luat_os_vm_exit_hook(int code, int delayMs);
#endif

// OTA 钩子
#ifdef LUAT_CONF_CUSTOM_OTA_HOOK
    void luat_os_ota_hook(void);
#endif

// 是否支持SSL/TLS/DLTS
#ifdef LUAT_CONF_SUPPORT_SSL
    
#endif

//------------------------------

#endif
