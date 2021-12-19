#include "luat_base.h"
#include "luat_malloc.h"

#define LUAT_LOG_TAG "lv_mem"
#include "luat_log.h"

typedef struct lv_mem_block {
    uint8_t magic;
    uint8_t ZERO;
    uint16_t size;
    uint8_t ptr[4];
}lv_mem_block_t;

void* luat_lvgl_malloc(int len) {
    if (len == 0)
        return NULL;
    lv_mem_block_t *block = luat_heap_malloc(len + 4);
    if (block == NULL)
        return NULL;
    block->magic = 0xAA;
    block->ZERO = 0;
    block->size = len;
    return block->ptr;
}

void* luat_lvgl_free(void* ptr) {
    if (ptr == NULL)
        return NULL;
    lv_mem_block_t *block = (lv_mem_block_t *)(((uint8_t*)ptr) - 4);
    if (block->magic == 0xAA && block->ZERO == 0) {
        luat_heap_free((void*)block);
    }
    else {
        LLOGW("bad lv_mem_block %p %d %d", block, block->magic, block->ZERO);
    }
    return NULL;
}

void* luat_lvgl_realloc(void* ptr, int _new) {
    if (_new == 0) {
        luat_lvgl_free(ptr);
        return NULL;
    }
    lv_mem_block_t *block = (lv_mem_block_t *)(((uint8_t*)ptr) - 4);
    if (block->magic == 0xAA && block->ZERO == 0) {
        lv_mem_block_t * tmp = luat_heap_realloc((void*)block, _new);
        if (tmp == NULL) {
            return NULL;
        }
        tmp->size = _new;
        return tmp->ptr;
    }
    else {
        LLOGW("bad lv_mem_block %p %d %d", block, block->magic, block->ZERO);
        return NULL;
    }
}

int luat_lvgl_mem_get_size(void* ptr) {
    if (ptr == NULL)
        return 0;
    lv_mem_block_t *block = (lv_mem_block_t *)(((uint8_t*)ptr) - 4);
    if (block->magic == 0xAA && block->ZERO == 0) {
        return block->size;
    }
    else {
        LLOGW("bad lv_mem_block %p %d %d", block, block->magic, block->ZERO);
        return 64; // 很危险
    }
}
