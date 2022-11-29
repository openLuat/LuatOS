/*
@module  coremark
@summary 跑分
@version 1.0
@date    2022.01.11
@tag LUAT_USE_COREMARK
*/
#include "luat_base.h"

#include "printf.h"

#define LUAT_LOG_TAG "coremark"
#include "luat_log.h"

void ee_main(void);

int ee_printf(const char *fmt, ...) {
    va_list va;
    va_start(va, fmt);
    char buff[512];
    vsnprintf_(buff, 512, fmt, va);
    va_end(va);
    LLOGD("%s", buff);
    return 0;
}

/*
开始跑分
@api    coremark.run()
@return nil 无返回值,结果直接打印在日志中
@usage
-- 大部分情况下, 这个库都不会包含在正式版固件里
-- 若需使用,可以参考wiki文档自行编译或使用云编译
-- https://wiki.luatos.com/develop/compile.html

-- 跑分的main.lua 应移除硬狗代码, 防止重启
-- 若设备支持自动休眠, 应关闭休眠功能
-- 若设备支持更多的频率运行, 建议设置到最高频率
-- 使用 -O3 比 -O2 -Os 的分数更高, 通常情况下

-- 会一直独占线程到执行完毕, 然后在控制台输出结果
coremark.run()

-- 跑分图一乐^_^

*/
static int l_coremark_run(lua_State *L) {
    ee_main();
    return 0;
}

#include "rotable2.h"
static const rotable_Reg_t reg_coremark[] =
{
    { "run" ,         ROREG_FUNC(l_coremark_run)},
    { NULL,           ROREG_INT(0)}
};

LUAMOD_API int luaopen_coremark( lua_State *L ) {
    luat_newlib2(L, reg_coremark);
    return 1;
}
