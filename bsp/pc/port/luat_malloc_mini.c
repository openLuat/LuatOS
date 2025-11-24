
// 这个文件包含 系统heap和lua heap的默认实现


#include <stdlib.h>
#include <string.h>//add for memset
#include "bget.h"
#include "luat_malloc.h"

#define LUAT_LOG_TAG "vmheap"
#include "luat_log.h"


#include "luat_mem.h"
#include "luat_bget.h"

static void* psram_ptr;
static luat_bget_t psram_bget;

static void* sram_ptr;
static luat_bget_t sram_bget;

//------------------------------------------------
//  管理系统内存

void* luat_heap_malloc(size_t len) {
    // 改成从sram_bget分配
    if (len > 2*1024*1024) {
        LLOGW("luat_heap_malloc: len=%d too large\n", len);
    }
    return luat_bgetz(&sram_bget, len);
}

void luat_heap_free(void* ptr) {
    if (ptr == NULL) {
        printf("luat_heap_free: ptr is NULL, return\n");
        return;
    }
    uint32_t addr = (uint32_t)ptr;
    if (addr < (uint32_t)sram_ptr || addr >= ((uint32_t)sram_ptr + 1024*1024)) {
        printf("luat_heap_free: ptr %p out of sram range, return\n", ptr);
        return;
    }
    // 还得判断ptr的地址范围,防御不合法的free
    luat_brel(&sram_bget, ptr);
}

void* luat_heap_realloc(void* ptr, size_t len) {
    return luat_bgetr(&sram_bget, ptr, len);
}

void* luat_heap_calloc(size_t count, size_t _size) {
    void *ptr = luat_heap_malloc(count * _size);
    if (ptr) {
        memset(ptr, 0, count * _size);
    }
    return ptr;
}

void* luat_heap_zalloc(size_t _size) {
    void* ptr = luat_heap_malloc(_size);
    if (ptr != NULL) {
        memset(ptr, 0, _size);
    }
    return ptr;
}
//------------------------------------------------

//------------------------------------------------
// ---------- 管理 LuaVM所使用的内存----------------
void* luat_heap_alloc(void *ud, void *ptr, size_t osize, size_t nsize) {
    (void)ud;
    if (0) {
        if (ptr) {
            if (nsize) {
                // 缩放内存块
                LLOGD("realloc %p from %d to %d", ptr, osize, nsize);
            }
            else {
                // 释放内存块
                LLOGD("free %p ", ptr);
                brel(ptr);
                return NULL;
            }
        }
        else {
            // 申请内存块
            ptr = bget(nsize);
            LLOGD("malloc %p type=%d size=%d", ptr, osize, nsize);
            return ptr;
        }
    }

    if (nsize)
    {
    	void* ptmp = bgetr(ptr, nsize);
    	if(ptmp == NULL && osize >= nsize)
    	{
    		return ptr;
    	}
        return ptmp;
    }
    brel(ptr);
    return NULL;
}

void luat_meminfo_luavm(size_t *total, size_t *used, size_t *max_used) {
	long curalloc, totfree, maxfree;
	unsigned long nget, nrel;
	bstats(&curalloc, &totfree, &maxfree, &nget, &nrel);
	*used = curalloc;
	*max_used = bstatsmaxget();
    *total = curalloc + totfree;
}

void luat_meminfo_sys(size_t *total, size_t *used, size_t *max_used) {
    long curalloc, totfree, maxfree;
    unsigned long nget, nrel;
    luat_bstats(&sram_bget, &curalloc, &totfree, &maxfree, &nget, &nrel);
    *used = curalloc;
    *max_used = maxfree;
    *total = curalloc + totfree;
}


void luat_heap_opt_init(LUAT_HEAP_TYPE_E type){
    if (type == LUAT_HEAP_PSRAM && psram_ptr == NULL) {
        psram_ptr = malloc(2*1024*1024);
        luat_bget_init(&psram_bget);
        luat_bpool(&psram_bget, psram_ptr, 2*1024*1024);
    }
    else if (type == LUAT_HEAP_SRAM && sram_ptr == NULL) {
        sram_ptr = malloc(1024*1024);
        luat_bget_init(&sram_bget);
        luat_bpool(&sram_bget, sram_ptr, 1024*1024);
    }
}

void* luat_heap_opt_malloc(LUAT_HEAP_TYPE_E type,size_t len){
    if (type == LUAT_HEAP_PSRAM) {
        return luat_bgetz(&psram_bget, len);
    }
    return luat_heap_malloc(len);
}

void luat_heap_opt_free(LUAT_HEAP_TYPE_E type,void* ptr){
    if (type == LUAT_HEAP_PSRAM) {
        luat_brel(&psram_bget, ptr);
        return;
    }
    luat_heap_free(ptr);
}

void* luat_heap_opt_realloc(LUAT_HEAP_TYPE_E type,void* ptr, size_t len){
    if (type == LUAT_HEAP_PSRAM) {
        return luat_bgetr(&psram_bget, ptr, len);
    }
    return luat_heap_realloc(ptr, len);
}

void* luat_heap_opt_calloc(LUAT_HEAP_TYPE_E type,size_t count, size_t size){
    return luat_heap_opt_zalloc(type,count*size);
}

void* luat_heap_opt_zalloc(LUAT_HEAP_TYPE_E type,size_t size){
    void *ptr = luat_heap_opt_malloc(type,size);
    if (ptr) {
        memset(ptr, 0, size);
    }
    return ptr;
}

void luat_meminfo_opt_sys(LUAT_HEAP_TYPE_E type,size_t* total, size_t* used, size_t* max_used){
    if (type == LUAT_HEAP_PSRAM) {
        long curalloc, totfree, maxfree;
	    unsigned long nget, nrel;
	    luat_bstats(&psram_bget, &curalloc, &totfree, &maxfree, &nget, &nrel);
	    *used = curalloc;
	    *max_used = luat_bstatsmaxget(&psram_bget);
        *total = curalloc + totfree;
    }
    else {
        luat_meminfo_sys(total, used, max_used);
    }
}



//-----------------------------------------------------------------------------
