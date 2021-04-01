#ifndef LUAT_ZBUFF
#define LUAT_ZBUFF

#include "luat_msgbus.h"

typedef struct luat_zbuff {
    uint8_t* addr;      //数据存储的地址
    uint32_t len;       //数据的长度
    uint32_t cursor;    //目前的指针位置
} luat_zbuff;

#endif