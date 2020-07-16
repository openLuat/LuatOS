#ifndef CUSTOM_VSPRINTF
#define CUSTOM_VSPRINTF

#include <stdarg.h>
#include "luat_base.h"

int atob(uint32_t *vp, char *p, int base);
char * btoa(char *dst, uint32_t value, int base);
int custom_vsprintf (char *d, const char *s, va_list ap);
char* llbtoa(char *dst, long long value, int base);


#endif
