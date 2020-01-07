
#include "luat_base.h"
#include "luat_log.h"
#include "rtthread.h"

void luat_print(const char* _str) {
    rt_kputs(_str);
}

void luat_nprint(char *s, size_t l) {
    //char buf[l+1];
    //snprintf(buf, l, s);
    rt_kputs(s);
}

void luat_printf(const char* fmt, ...) {
    va_list args;
    va_start(args, fmt);
    rt_kprintf(fmt, args);
    va_end(args);
}
