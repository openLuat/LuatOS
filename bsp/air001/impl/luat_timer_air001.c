
#include "luat_base.h"
#include "luat_timer.h"

#include <unistd.h>

int luat_timer_start(luat_timer_t* timer) {
    return -1;
}

int luat_timer_stop(luat_timer_t* timer) {
    return -1;
}

luat_timer_t* luat_timer_get(size_t timer_id) {
    return NULL;
}


int luat_timer_mdelay(size_t ms) {
    while (ms > 0) {
        if (ms >= 1000) {
            ms -= 1000;
            sleep(1);
        }
        else if (ms > 100) {
            ms -= 100;
            usleep(100*1000);
        }
        else {
            usleep(ms * 1000);
            break;
        }
    }
    return 0;
}