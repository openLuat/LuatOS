#include "luat_base.h"
#include "luat_pm.h"

int luat_pm_request(int mode) {
    return 0;
}

int luat_pm_release(int mode) {
    return 0;
}

int luat_pm_dtimer_start(int id, size_t timeout) {
    return 0;
}

int luat_pm_dtimer_stop(int id) {
    return 0;
}

int luat_pm_dtimer_check(int id) {
    return 0;
}

int luat_pm_last_state(int *lastState, int *rtcOrPad) {
    return 0;
}

int luat_pm_force(int mode) {
    return 0;
}

int luat_pm_check(void) {
    return 0;
}

int luat_pm_dtimer_list(size_t* count, size_t* list) {
    return 0;
}

int luat_pm_dtimer_wakeup_id(int* id) {
    return 0;
}
