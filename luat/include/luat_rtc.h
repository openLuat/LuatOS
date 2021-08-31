
#include "luat_base.h"
#include "time.h"

int luat_rtc_set(struct tm *tblock);
int luat_rtc_get(struct tm *tblock);
int luat_rtc_timer_start(int id, struct tm *tblock);
int luat_rtc_timer_stop(int id);
