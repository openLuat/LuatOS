#ifndef HZFONT_PSRAM_H
#define HZFONT_PSRAM_H

#include <stddef.h>
#include "luat_conf_bsp.h"

// 定义hzfont的PSRAM链表块大小，当前默认为64KB
#define HZFONT_PSRAM_BLOCK_SIZE (64 * 1024)

// 定义hzfont的PSRAM链表块结构体
typedef struct hzfont_psram_block {
    struct hzfont_psram_block *next;
    size_t used;
    uint8_t data[HZFONT_PSRAM_BLOCK_SIZE];
} hzfont_psram_block_t;

// 定义hzfont的PSRAM链表结构体
typedef struct hzfont_psram_chain {
    hzfont_psram_block_t *head;
    hzfont_psram_block_t *tail;
    size_t total_size;
    uint32_t block_count;
} hzfont_psram_chain_t;
#endif /* HZFONT_PSRAM_H */