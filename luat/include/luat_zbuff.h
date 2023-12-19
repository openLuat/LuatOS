#ifndef LUAT_ZBUFF_H
#define LUAT_ZBUFF_H

#include "luat_mem.h"
#include "luat_msgbus.h"

#define LUAT_ZBUFF_TYPE "ZBUFF*"
#define tozbuff(L) ((luat_zbuff_t *)luaL_checkudata(L, 1, LUAT_ZBUFF_TYPE))

#define ZBUFF_SEEK_SET 0
#define ZBUFF_SEEK_CUR 1
#define ZBUFF_SEEK_END 2

#if defined ( __CC_ARM )
#pragma anon_unions
#endif

typedef struct luat_zbuff {
    LUAT_HEAP_TYPE_E type; //内存类型
    uint8_t* addr;      //数据存储的地址
    size_t len;       //实际分配空间的长度
    union {
    	size_t cursor;    //目前的指针位置，表明了处理了多少数据
    	size_t used;	//已经保存的数据量，表明了存了多少数据
    };

    uint32_t width; //宽度
    uint32_t height;//高度
    uint8_t bit;    //色深度
} luat_zbuff_t;


int __zbuff_resize(luat_zbuff_t *buff, uint32_t new_size);

#endif
