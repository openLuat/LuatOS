#ifndef LUAT_ZBUFF_H
#define LUAT_ZBUFF_H

#include "luat_msgbus.h"

#define LUAT_ZBUFF_TYPE "ZBUFF*"
#define tozbuff(L) ((luat_zbuff_t *)luaL_checkudata(L, 1, LUAT_ZBUFF_TYPE))

#define ZBUFF_SEEK_SET 0
#define ZBUFF_SEEK_CUR 1
#define ZBUFF_SEEK_END 2
typedef struct luat_zbuff {
    uint8_t* addr;      //数据存储的地址
    size_t len;       //数据的长度
    size_t cursor;    //目前的指针位置
    uint32_t width; //宽度
    uint32_t height;//高度
    uint8_t bit;    //色深度
} luat_zbuff_t;

#endif
