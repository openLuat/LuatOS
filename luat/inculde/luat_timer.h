#ifndef LUAT_TIMER
#define LUAT_TIMER

#include "luat_base.h"

typedef void(* luat_timer_func )(void *argument);

struct luat_timer_ec616_t
{
    void* os_timer;
    luat_timer_func timer_func;
    int timeout;
    int _type;
    int _repeat;
};


int luat_timer_start(struct luat_timer_ec616_t* timer);
int luat_timer_stop(struct luat_timer_ec616_t* timer);

#endif
