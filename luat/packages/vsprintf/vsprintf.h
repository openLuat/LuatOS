#ifndef CUSTOM_VSPRINTF
#define CUSTOM_VSPRINTF

#include "luat_base.h"
#include <stdarg.h>

int atob(uint32_t *vp, char *p, int base);
char * btoa(char *dst, uint32_t value, int base);
int custom_vsprintf (char *d, const char *s, va_list ap);


#endif
