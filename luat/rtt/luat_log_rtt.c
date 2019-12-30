
#include "luat_base.h"
#include "luat_log.h"

// 导入rt-thread的日志函数
extern void rt_kprintf(const char* fmt,...);

void luat_print(const char* _str) {
    rt_kprintf(_str);
}
void luat_printf(const char* fmt, ...) {
    va_list args;
    va_start(args, fmt);
    rt_kprintf(fmt, args);
    va_end(args);
}
