#ifndef LUAT_WDT_H
#define LUAT_WDT_H
#include "luat_base.h"

int luat_wdt_init(size_t timeout);
int luat_wdt_set_timeout(size_t timeout);
int luat_wdt_feed(void);
int luat_wdt_close(void);

#endif
