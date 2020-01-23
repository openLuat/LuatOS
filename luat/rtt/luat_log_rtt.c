
#include "luat_base.h"
#include "luat_log.h"
#include "rtthread.h"

void luat_print(const char* _str) {
    rt_kputs(_str);
}

void luat_nprint(char *s, size_t l) {
    char buf[2];
    buf[1] = 0x00;
    for (size_t i = 0; i < l; i++)
    {
        buf[0] = s[i];
        rt_kputs(buf);
    }
}

void luat_printf(const char* fmt, const char* value) {
    rt_kprintf(fmt, value);
}
