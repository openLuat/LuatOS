#include <stdlib.h>
#include <stdint.h>
#include <string.h>

#include "uv.h"

#include "lwip/opt.h"
#include "lwip/arch.h"
#include "lwip/stats.h"
#include "lwip/debug.h"
#include "lwip/sys.h"
#include "lwip/tcpip.h"
#include "lwip/mem.h"
#include "lwip/err.h"

#include "luat_mcu.h"
#include "luat_crypto.h"

/*
   本文件提供 NO_SYS=0 模式下的 sys_arch 实现，
   全部基于 libuv 原语（uv_mutex/uv_cond/uv_thread），不使用 OS 原生 API。
   结构体类型遵循 include/arch/sys_arch.h 的定义：
   - sys_sem_t   : { void* sem; }
   - sys_mutex_t : { void* mut; }
   - sys_mbox_t  : { void* sem; void* q_mem[MAX_QUEUE_ENTRIES]; u32 head, tail; }
*/

typedef struct uv_semx {
    uv_mutex_t lock;
    uv_cond_t cond;
    unsigned int count;
    unsigned int maxcount; /* 仅用于兼容，但不做严格限制 */
} uv_semx_t;

/* 保护区：模仿 Win32 端口的全局临界区实现 */
static uv_mutex_t s_protect_mutex;
static int s_protect_inited = 0;
#if 1 /* 如需严格校验可设置为 1 */
static int s_protection_depth = 0;
#endif

static void sys_arch_global_init(void) {
    if (!s_protect_inited) {
        uv_mutex_init(&s_protect_mutex);
        s_protect_inited = 1;
    }
}

/* lwIP 要求在 lwip_init() 前调用，用于初始化 sys 层 */
void sys_init(void) {
    sys_arch_global_init();
}

/* 随机数：供 LWIP_RAND() 使用 */
unsigned int lwip_port_rand(void) {
    union { uint32_t u32; uint8_t u8[4]; } u;
    luat_crypto_trng((char*)u.u8, 4);
    return u.u32;
}

/* 时间接口 */
u32_t sys_now(void) {
    return (u32_t)luat_mcu_tick64_ms();
}

u32_t sys_jiffies(void) {
    return sys_now();
}

/* 保护区进入/退出 */
sys_prot_t sys_arch_protect(void) {
    sys_arch_global_init();
    uv_mutex_lock(&s_protect_mutex);
#if 1
    LWIP_ASSERT("nested SYS_ARCH_PROTECT", s_protection_depth == 0);
    s_protection_depth++;
#endif
    return 0;
}

void sys_arch_unprotect(sys_prot_t pval) {
    LWIP_UNUSED_ARG(pval);
#if 1
    LWIP_ASSERT("missing SYS_ARCH_PROTECT", s_protection_depth == 1);
    s_protection_depth--;
#endif
    uv_mutex_unlock(&s_protect_mutex);
}

/* 当 LWIP_ASSERT_CORE_LOCKED() 被配置为调用该函数时，
   在 NO_SYS=0 且未启用核心锁的场景下，给出空实现即可。*/
void sys_check_core_locking(void) {
    /* no-op: 在 PC 模拟器上不做线程归属校验 */
}

/* 信号量实现（带超时） */
static uv_semx_t* uv_semx_create(unsigned initial_count, unsigned maxcount) {
    uv_semx_t* s = (uv_semx_t*)malloc(sizeof(uv_semx_t));
    if (!s) return NULL;
    memset(s, 0, sizeof(*s));
    uv_mutex_init(&s->lock);
    uv_cond_init(&s->cond);
    s->count = initial_count;
    s->maxcount = maxcount ? maxcount : 100000; /* 不严格限制 */
    return s;
}

static void uv_semx_destroy(uv_semx_t* s) {
    if (!s) return;
    uv_cond_destroy(&s->cond);
    uv_mutex_destroy(&s->lock);
    free(s);
}

static void uv_semx_post(uv_semx_t* s) {
    uv_mutex_lock(&s->lock);
    if (s->count < s->maxcount) {
        s->count++;
        uv_cond_signal(&s->cond);
    }
    uv_mutex_unlock(&s->lock);
}

/* 返回：0 表示成功，非0 表示超时 */
static int uv_semx_timedwait(uv_semx_t* s, u32_t timeout_ms) {
    int ret = 0;
    uv_mutex_lock(&s->lock);
    if (timeout_ms == 0) {
        while (s->count == 0) {
            uv_cond_wait(&s->cond, &s->lock);
        }
        s->count--;
        uv_mutex_unlock(&s->lock);
        return 0;
    }
    uint64_t start = uv_hrtime();
    uint64_t deadline = (uint64_t)timeout_ms * 1000000ull; /* ns */
    while (s->count == 0) {
        uint64_t now = uv_hrtime();
        uint64_t elapsed = now - start;
        if (elapsed >= deadline) { ret = -1; break; }
        uint64_t remain = deadline - elapsed;
        /* uv_cond_timedwait 接受纳秒（相对超时） */
        int r = uv_cond_timedwait(&s->cond, &s->lock, remain);
        if (r == UV_ETIMEDOUT) { ret = -1; break; }
    }
    if (ret == 0 && s->count > 0) {
        s->count--;
    }
    uv_mutex_unlock(&s->lock);
    return ret;
}

err_t sys_sem_new(sys_sem_t *sem, u8_t count) {
    LWIP_ASSERT("sem != NULL", sem != NULL);
    uv_semx_t* s = uv_semx_create(count ? 1 : 0, 100000);
    if (!s) {
        SYS_STATS_INC(sem.err);
        sem->sem = NULL;
        return ERR_MEM;
    }
    sem->sem = s;
    SYS_STATS_INC_USED(sem);
    return ERR_OK;
}

void sys_sem_free(sys_sem_t *sem) {
    LWIP_ASSERT("sem != NULL", sem != NULL);
    if (sem->sem) {
        uv_semx_destroy((uv_semx_t*)sem->sem);
        sem->sem = NULL;
        SYS_STATS_DEC(sem.used);
    }
}

void sys_sem_signal(sys_sem_t *sem) {
    LWIP_ASSERT("sem != NULL", sem != NULL);
    LWIP_ASSERT("sem->sem != NULL", sem->sem != NULL);
    uv_semx_post((uv_semx_t*)sem->sem);
}

u32_t sys_arch_sem_wait(sys_sem_t *sem, u32_t timeout) {
    LWIP_ASSERT("sem != NULL", sem != NULL);
    LWIP_ASSERT("sem->sem != NULL", sem->sem != NULL);

    uint32_t waited = 0;
    if (timeout == 0) {
        (void)uv_semx_timedwait((uv_semx_t*)sem->sem, 0);
        return 0;
    }
    uint64_t start = uv_hrtime();
    int r = uv_semx_timedwait((uv_semx_t*)sem->sem, timeout);
    if (r == 0) {
        uint64_t end = uv_hrtime();
        waited = (u32_t)((end - start) / 1000000ull);
        if (waited == 0) waited = 1; /* lwIP 语义：成功至少返回 >0 的等待时间 */
        return waited;
    }
    return SYS_ARCH_TIMEOUT;
}

/* 互斥量 */
err_t sys_mutex_new(sys_mutex_t *mutex) {
    LWIP_ASSERT("mutex != NULL", mutex != NULL);
    uv_mutex_t* m = (uv_mutex_t*)malloc(sizeof(uv_mutex_t));
    if (!m) {
        SYS_STATS_INC(mutex.err);
        mutex->mut = NULL;
        return ERR_MEM;
    }
    uv_mutex_init(m);
    mutex->mut = m;
    SYS_STATS_INC_USED(mutex);
    return ERR_OK;
}

void sys_mutex_free(sys_mutex_t *mutex) {
    LWIP_ASSERT("mutex != NULL", mutex != NULL);
    if (mutex->mut) {
        uv_mutex_destroy((uv_mutex_t*)mutex->mut);
        free(mutex->mut);
        mutex->mut = NULL;
        SYS_STATS_DEC(mutex.used);
    }
}

void sys_mutex_lock(sys_mutex_t *mutex) {
    LWIP_ASSERT("mutex != NULL", mutex != NULL);
    LWIP_ASSERT("mutex->mut != NULL", mutex->mut != NULL);
    uv_mutex_lock((uv_mutex_t*)mutex->mut);
}

void sys_mutex_unlock(sys_mutex_t *mutex) {
    LWIP_ASSERT("mutex != NULL", mutex != NULL);
    LWIP_ASSERT("mutex->mut != NULL", mutex->mut != NULL);
    uv_mutex_unlock((uv_mutex_t*)mutex->mut);
}

/* mbox：使用全局保护区 + 每个 mbox 的信号量控制 */
err_t sys_mbox_new(sys_mbox_t *mbox, int size) {
    LWIP_UNUSED_ARG(size);
    LWIP_ASSERT("mbox != NULL", mbox != NULL);
    /* 创建计数信号量，初始为 0 */
    uv_semx_t* s = uv_semx_create(0, MAX_QUEUE_ENTRIES);
    if (!s) {
        SYS_STATS_INC(mbox.err);
        mbox->sem = NULL;
        return ERR_MEM;
    }
    memset(mbox->q_mem, 0, sizeof(mbox->q_mem));
    mbox->head = 0;
    mbox->tail = 0;
    mbox->sem = s;
    SYS_STATS_INC_USED(mbox);
    return ERR_OK;
}

void sys_mbox_free(sys_mbox_t *mbox) {
    LWIP_ASSERT("mbox != NULL", mbox != NULL);
    if (mbox->sem) {
        uv_semx_destroy((uv_semx_t*)mbox->sem);
        mbox->sem = NULL;
        SYS_STATS_DEC(mbox.used);
    }
}

void sys_mbox_post(sys_mbox_t *q, void *msg) {
    LWIP_ASSERT("q != NULL", q != NULL);
    sys_prot_t lev = sys_arch_protect();
    u32_t new_head = q->head + 1;
    if (new_head >= MAX_QUEUE_ENTRIES) new_head = 0;
    LWIP_ASSERT("mbox is full!", new_head != q->tail);
    q->q_mem[q->head] = msg;
    q->head = new_head;
    sys_arch_unprotect(lev);
    uv_semx_post((uv_semx_t*)q->sem);
}

err_t sys_mbox_trypost(sys_mbox_t *q, void *msg) {
    LWIP_ASSERT("q != NULL", q != NULL);
    sys_prot_t lev = sys_arch_protect();
    u32_t new_head = q->head + 1;
    if (new_head >= MAX_QUEUE_ENTRIES) new_head = 0;
    if (new_head == q->tail) {
        sys_arch_unprotect(lev);
        return ERR_MEM;
    }
    q->q_mem[q->head] = msg;
    q->head = new_head;
    sys_arch_unprotect(lev);
    uv_semx_post((uv_semx_t*)q->sem);
    return ERR_OK;
}

err_t sys_mbox_trypost_fromisr(sys_mbox_t *q, void *msg) {
    /* PC 上无 ISR 语义，等同 trypost */
    return sys_mbox_trypost(q, msg);
}

u32_t sys_arch_mbox_fetch(sys_mbox_t *q, void **msg, u32_t timeout) {
    LWIP_ASSERT("q != NULL", q != NULL);
    if (timeout == 0) {
        (void)uv_semx_timedwait((uv_semx_t*)q->sem, 0);
    } else {
        int r = uv_semx_timedwait((uv_semx_t*)q->sem, timeout);
        if (r != 0) {
            if (msg) *msg = NULL;
            return SYS_ARCH_TIMEOUT;
        }
    }
    sys_prot_t lev = sys_arch_protect();
    if (msg) *msg = q->q_mem[q->tail];
    q->tail++;
    if (q->tail >= MAX_QUEUE_ENTRIES) q->tail = 0;
    sys_arch_unprotect(lev);
    /* 返回等待的毫秒数：这里无法精确返回阻塞时间，返回 0 也可被 lwIP 接受 */
    return 0;
}

u32_t sys_arch_mbox_tryfetch(sys_mbox_t *q, void **msg) {
    LWIP_ASSERT("q != NULL", q != NULL);
    uv_semx_t* s = (uv_semx_t*)q->sem;
    u32_t ret = SYS_MBOX_EMPTY;
    /* 非阻塞检查：若无可用项直接返回 */
    uv_mutex_lock(&s->lock);
    if (s->count > 0) {
        s->count--;
        ret = 0;
    }
    uv_mutex_unlock(&s->lock);
    if (ret == 0) {
        sys_prot_t lev = sys_arch_protect();
        if (msg) *msg = q->q_mem[q->tail];
        q->tail++;
        if (q->tail >= MAX_QUEUE_ENTRIES) q->tail = 0;
        sys_arch_unprotect(lev);
    } else {
        if (msg) *msg = NULL;
    }
    return ret;
}

/* 线程：lwIP 仅需要创建线程并运行给定函数 */
struct _lwip_thread_start {
    lwip_thread_fn fn;
    void* arg;
};

static void _lwip_thread_entry(void* p) {
    struct _lwip_thread_start ctx = *(struct _lwip_thread_start*)p;
    free(p);
    ctx.fn(ctx.arg);
}

sys_thread_t sys_thread_new(const char *name, lwip_thread_fn function, void *arg, int stacksize, int prio) {
    LWIP_UNUSED_ARG(name);
    LWIP_UNUSED_ARG(stacksize);
    LWIP_UNUSED_ARG(prio);
    uv_thread_t* th = (uv_thread_t*)malloc(sizeof(uv_thread_t));
    if (!th) return 0;
    struct _lwip_thread_start* ctx = (struct _lwip_thread_start*)malloc(sizeof(struct _lwip_thread_start));
    if (!ctx) return 0;
    ctx->fn = function;
    ctx->arg = arg;
    if (uv_thread_create(th, _lwip_thread_entry, ctx) != 0) {
        free(ctx);
        free(th);
        return 0;
    }
    /* 返回非 0 句柄，后续不在此处回收，交由进程退出清理 */
    return (sys_thread_t)(uintptr_t)(th);
}

/* 可选接口占位，避免链接缺失 */
sys_sem_t* sys_arch_netconn_sem_get(void) { return NULL; }
void sys_arch_netconn_sem_alloc(void) {}
void sys_arch_netconn_sem_free(void) {}

int lwip_win32_keypressed(void) { return 0; }

void sys_mark_tcpip_thread(void) { /* no-op */ }
