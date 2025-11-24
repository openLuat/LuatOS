#include "luat_base.h"
#include "luat_hmeta.h"

int luat_hmeta_chip(char* buff) {
    memcpy(buff, "x86", 4);
    return 0;
}

int luat_hmeta_model_name(char* buff) {
    memcpy(buff, "PC", 3);
    return 0;
}

int luat_hmeta_hwversion(char* buff) {
    memcpy(buff, "A10", 4);
    return 0;
}

