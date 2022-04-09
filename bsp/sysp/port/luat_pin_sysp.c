#include "luat_base.h"
#include "luat_pin.h"

int luat_pin_to_gpio(const char* pin_name) {
    int zone = 0;
    int index = 0;
    int re = 0;
    re = luat_pin_parse(pin_name, &zone, &index);
    if (re < 0) {
        return -1;
    }
    return zone * 16 + index;
}

