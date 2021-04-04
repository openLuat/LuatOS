#ifndef LUAT_ZBUFF
#define LUAT_ZBUFF

#include "luat_msgbus.h"

#define ZBUFF_SEEK_SET 0
#define ZBUFF_SEEK_CUR 1
#define ZBUFF_SEEK_END 2
typedef struct luat_zbuff {
    uint8_t* addr;      //数据存储的地址
    size_t len;       //数据的长度
    size_t cursor;    //目前的指针位置
} luat_zbuff;

#endif
