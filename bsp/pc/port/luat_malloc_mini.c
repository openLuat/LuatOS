
// 这个文件包含 系统heap和lua heap的默认实现


#include <stdlib.h>
#include <stdint.h>
#include <string.h>//add for memset
#include "bget.h"
#include "luat_malloc.h"

#define LUAT_LOG_TAG "vmheap"
#include "luat_log.h"


#include "luat_mem.h"
#include "luat_bget.h"
#include "luat_posix_compat.h"  // 引入 pthread (Windows 下走 pthreads-w32)

#define LUAT_HEAP_SRAM_SIZE (2*1024*1024)
#define LUAT_HEAP_PSRAM_SIZE (16*1024*1024)

static void* psram_ptr;
static luat_bget_t psram_bget;
static pthread_mutex_t psram_lock = PTHREAD_MUTEX_INITIALIZER;

static void* sram_ptr;
static luat_bget_t sram_bget;
static pthread_mutex_t sram_lock = PTHREAD_MUTEX_INITIALIZER;

static int ptr_in_psram_range(const void* ptr) {
    if (ptr == NULL || psram_ptr == NULL) return 0;
    uintptr_t addr = (uintptr_t)ptr;
    return addr >= (uintptr_t)psram_ptr
        && addr <  (uintptr_t)psram_ptr + LUAT_HEAP_PSRAM_SIZE;
}

static int ptr_in_sram_range(const void* ptr) {
    if (ptr == NULL || sram_ptr == NULL) return 0;
    uintptr_t addr = (uintptr_t)ptr;
    return addr >= (uintptr_t)sram_ptr
        && addr <  (uintptr_t)sram_ptr + LUAT_HEAP_SRAM_SIZE;
}

//------------------------------------------------
//  管理系统内存

void* luat_heap_malloc(size_t len) {
    // 改成从sram_bget分配
    if (len > 2*1024*1024) {
        LLOGW("luat_heap_malloc: len=%d too large\n", len);
    }
    pthread_mutex_lock(&sram_lock);
    void* p = luat_bgetz(&sram_bget, len);
    pthread_mutex_unlock(&sram_lock);
    return p;
}

void luat_heap_free(void* ptr) {
    if (ptr == NULL) {
        printf("luat_heap_free: ptr is NULL, return\n");
        return;
    }
    if (!ptr_in_sram_range(ptr)) {
        printf("luat_heap_free: ptr %p out of sram range, return\n", ptr);
        return;
    }
    pthread_mutex_lock(&sram_lock);
    luat_brel(&sram_bget, ptr);
    pthread_mutex_unlock(&sram_lock);
}

void* luat_heap_realloc(void* ptr, size_t len) {
    if (ptr != NULL && !ptr_in_sram_range(ptr)) {
        printf("luat_heap_realloc: ptr %p out of sram range, fallback to malloc(%zu)\n", ptr, len);
        return len ? luat_heap_malloc(len) : NULL;
    }
    pthread_mutex_lock(&sram_lock);
    void* p = luat_bgetr(&sram_bget, ptr, len);
    pthread_mutex_unlock(&sram_lock);
    return p;
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
    pthread_mutex_lock(&sram_lock);
    luat_bstats(&sram_bget, &curalloc, &totfree, &maxfree, &nget, &nrel);
    pthread_mutex_unlock(&sram_lock);
    *used = curalloc;
    *max_used = maxfree;
    *total = curalloc + totfree;
}


void luat_heap_opt_init(LUAT_HEAP_TYPE_E type){
    if (type == LUAT_HEAP_PSRAM && psram_ptr == NULL) {
        psram_ptr = malloc(LUAT_HEAP_PSRAM_SIZE);
        if (psram_ptr == NULL) {
            LLOGE("Failed to allocate PSRAM memory pool: %d bytes", LUAT_HEAP_PSRAM_SIZE);
            return;
        }
        luat_bget_init(&psram_bget);
        luat_bpool(&psram_bget, psram_ptr, LUAT_HEAP_PSRAM_SIZE);
        // LLOGI("PSRAM pool initialized: %d bytes at %p", LUAT_HEAP_PSRAM_SIZE, psram_ptr);
    }
    else if (type == LUAT_HEAP_SRAM && sram_ptr == NULL) {
        sram_ptr = malloc(LUAT_HEAP_SRAM_SIZE);
        if (sram_ptr == NULL) {
            LLOGE("Failed to allocate SRAM memory pool: %d bytes", LUAT_HEAP_SRAM_SIZE);
            return;
        }
        luat_bget_init(&sram_bget);
        luat_bpool(&sram_bget, sram_ptr, LUAT_HEAP_SRAM_SIZE);
        // LLOGI("SRAM pool initialized: %d bytes at %p", LUAT_HEAP_SRAM_SIZE, sram_ptr);
    }
}

void* luat_heap_opt_malloc(LUAT_HEAP_TYPE_E type,size_t len){
    if (type == LUAT_HEAP_PSRAM) {
        pthread_mutex_lock(&psram_lock);
        void* p = luat_bgetz(&psram_bget, len);
        pthread_mutex_unlock(&psram_lock);
        return p;
    }
    return luat_heap_malloc(len);
}

void luat_heap_opt_free(LUAT_HEAP_TYPE_E type,void* ptr){
    if (type == LUAT_HEAP_PSRAM) {
        if (ptr && !ptr_in_psram_range(ptr)) {
            printf("luat_heap_opt_free(PSRAM): ptr %p out of psram range, return\n", ptr);
            return;
        }
        pthread_mutex_lock(&psram_lock);
        luat_brel(&psram_bget, ptr);
        pthread_mutex_unlock(&psram_lock);
        return;
    }
    luat_heap_free(ptr);
}

void* luat_heap_opt_realloc(LUAT_HEAP_TYPE_E type,void* ptr, size_t len){
    if (type == LUAT_HEAP_PSRAM) {
        if (ptr != NULL && !ptr_in_psram_range(ptr)) {
            printf("luat_heap_opt_realloc(PSRAM): ptr %p out of psram range, fallback to malloc(%zu)\n", ptr, len);
            return len ? luat_heap_opt_malloc(type, len) : NULL;
        }
        pthread_mutex_lock(&psram_lock);
        void* p = luat_bgetr(&psram_bget, ptr, len);
        pthread_mutex_unlock(&psram_lock);
        return p;
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
        pthread_mutex_lock(&psram_lock);
	    luat_bstats(&psram_bget, &curalloc, &totfree, &maxfree, &nget, &nrel);
	    *max_used = luat_bstatsmaxget(&psram_bget);
        pthread_mutex_unlock(&psram_lock);
	    *used = curalloc;
        *total = curalloc + totfree;
    }
    else {
        luat_meminfo_sys(total, used, max_used);
    }
}



//-----------------------------------------------------------------------------
