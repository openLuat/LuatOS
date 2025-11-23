#ifndef LUAT_QUEUE_PC_H
#define LUAT_QUEUE_PC_H

#include "stdint.h"
#include "inttypes.h"
// #include "uv.h"

typedef struct uv_queue_item
{
    // size_t is_head;
    void* next;
    // void* prev;
    size_t size;
    char msg[4]; // 实际数据
}uv_queue_item_t;

int luat_queue_push(uv_queue_item_t* queue, uv_queue_item_t* item);
int luat_queue_pop(uv_queue_item_t* queue, uv_queue_item_t* item);

#endif