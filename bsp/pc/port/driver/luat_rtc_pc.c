#include <stdlib.h>
#include <string.h>//add for memset
#include "luat_base.h"
#include "luat_malloc.h"
#include "luat_rtc.h"
#include "time.h"

#define LUAT_LOG_TAG "rtc"
#include "luat_log.h"

int luat_rtc_set(struct tm *tblock) {
    return 0; // 未实现
}
int luat_rtc_get(struct tm *tblock) {
    if (tblock == NULL)
        return -1;
    time_t rawtime;
    struct tm *tmp;
    time(&rawtime);
    tmp = gmtime(&rawtime );
    memcpy(tblock, tmp, sizeof(struct tm));
    return 0;
}
int luat_rtc_timer_start(int id, struct tm *tblock) {
    return -1; // 未实现
}
int luat_rtc_timer_stop(int id) {
    return 0; // 未实现
}
void luat_rtc_set_tamp32(uint32_t tamp) {
     // 未实现
}

int luat_rtc_timezone(int* timezone) {
    return 32; // 未实现
}
