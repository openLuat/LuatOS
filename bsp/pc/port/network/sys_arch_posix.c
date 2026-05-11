#include <stdlib.h>
#include <stdint.h>
#include <string.h>
#include <time.h>
#include <errno.h>

#include "luat_posix_compat.h"

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

/* ---------- Internal semaphore (counting, with timeout) ---------- */

typedef struct {
    pthread_mutex_t lock;
    pthread_cond_t  cond;
    unsigned int    count;
    unsigned int    maxcount;
} posix_semx_t;

static posix_semx_t *semx_create(unsigned initial, unsigned maxcount)
{
    posix_semx_t *s = (posix_semx_t *)malloc(sizeof(posix_semx_t));
    if (!s) return NULL;
    pthread_mutex_init(&s->lock, NULL);
    pthread_cond_init(&s->cond, NULL);
    s->count    = initial;
    s->maxcount = maxcount ? maxcount : 100000;
    return s;
}

static void semx_destroy(posix_semx_t *s)
{
    if (!s) return;
    pthread_cond_destroy(&s->cond);
    pthread_mutex_destroy(&s->lock);
    free(s);
}

static void semx_post(posix_semx_t *s)
{
    pthread_mutex_lock(&s->lock);
    if (s->count < s->maxcount) {
        s->count++;
        pthread_cond_signal(&s->cond);
    }
    pthread_mutex_unlock(&s->lock);
}

/* Returns 0 on success, -1 on timeout. timeout_ms==0 means wait forever. */
static int semx_timedwait(posix_semx_t *s, u32_t timeout_ms)
{
    int ret = 0;
    pthread_mutex_lock(&s->lock);

    if (timeout_ms == 0) {
        while (s->count == 0)
            pthread_cond_wait(&s->cond, &s->lock);
        s->count--;
        pthread_mutex_unlock(&s->lock);
        return 0;
    }

    struct timespec abs_ts;
    luat_calc_abs_timeout(&abs_ts, timeout_ms);

    while (s->count == 0) {
        int r = pthread_cond_timedwait(&s->cond, &s->lock, &abs_ts);
        if (r == ETIMEDOUT) { ret = -1; break; }
    }
    if (ret == 0 && s->count > 0)
        s->count--;

    pthread_mutex_unlock(&s->lock);
    return ret;
}

/* ---------- Global protection mutex ---------- */

static pthread_mutex_t s_protect_mutex;
static pthread_once_t  s_protect_once = PTHREAD_ONCE_INIT;
static int             s_protect_depth = 0;

static void protect_init_once(void)
{
    pthread_mutex_init(&s_protect_mutex, NULL);
}

void sys_init(void)
{
    pthread_once(&s_protect_once, protect_init_once);
}

unsigned int lwip_port_rand(void)
{
    union { uint32_t u32; uint8_t u8[4]; } u;
    luat_crypto_trng((char *)u.u8, 4);
    return u.u32;
}

u32_t sys_now(void)    { return (u32_t)luat_mcu_tick64_ms(); }
u32_t sys_jiffies(void){ return sys_now(); }

sys_prot_t sys_arch_protect(void)
{
    pthread_once(&s_protect_once, protect_init_once);
    pthread_mutex_lock(&s_protect_mutex);
    LWIP_ASSERT("nested SYS_ARCH_PROTECT", s_protect_depth == 0);
    s_protect_depth++;
    return 0;
}

void sys_arch_unprotect(sys_prot_t pval)
{
    LWIP_UNUSED_ARG(pval);
    LWIP_ASSERT("missing SYS_ARCH_PROTECT", s_protect_depth == 1);
    s_protect_depth--;
    pthread_mutex_unlock(&s_protect_mutex);
}

void sys_check_core_locking(void) { /* no-op on PC simulator */ }
void sys_mark_tcpip_thread(void)  { /* no-op */ }

/* ---------- Semaphore ---------- */

err_t sys_sem_new(sys_sem_t *sem, u8_t count)
{
    LWIP_ASSERT("sem != NULL", sem != NULL);
    posix_semx_t *s = semx_create(count ? 1u : 0u, 100000u);
    if (!s) { SYS_STATS_INC(sem.err); sem->sem = NULL; return ERR_MEM; }
    sem->sem = s;
    SYS_STATS_INC_USED(sem);
    return ERR_OK;
}

void sys_sem_free(sys_sem_t *sem)
{
    LWIP_ASSERT("sem != NULL", sem != NULL);
    if (sem->sem) {
        semx_destroy((posix_semx_t *)sem->sem);
        sem->sem = NULL;
        SYS_STATS_DEC(sem.used);
    }
}

void sys_sem_signal(sys_sem_t *sem)
{
    LWIP_ASSERT("sem != NULL", sem != NULL);
    LWIP_ASSERT("sem->sem != NULL", sem->sem != NULL);
    semx_post((posix_semx_t *)sem->sem);
}

u32_t sys_arch_sem_wait(sys_sem_t *sem, u32_t timeout)
{
    LWIP_ASSERT("sem != NULL", sem != NULL);
    LWIP_ASSERT("sem->sem != NULL", sem->sem != NULL);

    if (timeout == 0) {
        semx_timedwait((posix_semx_t *)sem->sem, 0);
        return 0;
    }
    uint64_t start = luat_monotonic_ms();
    int r = semx_timedwait((posix_semx_t *)sem->sem, timeout);
    if (r == 0) {
        u32_t waited = (u32_t)(luat_monotonic_ms() - start);
        return waited ? waited : 1u;
    }
    return SYS_ARCH_TIMEOUT;
}

/* ---------- Mutex ---------- */

err_t sys_mutex_new(sys_mutex_t *mutex)
{
    LWIP_ASSERT("mutex != NULL", mutex != NULL);
    pthread_mutex_t *m = (pthread_mutex_t *)malloc(sizeof(pthread_mutex_t));
    if (!m) { SYS_STATS_INC(mutex.err); mutex->mut = NULL; return ERR_MEM; }
    pthread_mutex_init(m, NULL);
    mutex->mut = m;
    SYS_STATS_INC_USED(mutex);
    return ERR_OK;
}

void sys_mutex_free(sys_mutex_t *mutex)
{
    LWIP_ASSERT("mutex != NULL", mutex != NULL);
    if (mutex->mut) {
        pthread_mutex_destroy((pthread_mutex_t *)mutex->mut);
        free(mutex->mut);
        mutex->mut = NULL;
        SYS_STATS_DEC(mutex.used);
    }
}

void sys_mutex_lock(sys_mutex_t *mutex)
{
    LWIP_ASSERT("mutex != NULL", mutex != NULL);
    LWIP_ASSERT("mutex->mut != NULL", mutex->mut != NULL);
    pthread_mutex_lock((pthread_mutex_t *)mutex->mut);
}

void sys_mutex_unlock(sys_mutex_t *mutex)
{
    LWIP_ASSERT("mutex != NULL", mutex != NULL);
    LWIP_ASSERT("mutex->mut != NULL", mutex->mut != NULL);
    pthread_mutex_unlock((pthread_mutex_t *)mutex->mut);
}

/* ---------- Mailbox ---------- */

err_t sys_mbox_new(sys_mbox_t *mbox, int size)
{
    LWIP_UNUSED_ARG(size);
    LWIP_ASSERT("mbox != NULL", mbox != NULL);
    posix_semx_t *s = semx_create(0u, MAX_QUEUE_ENTRIES);
    if (!s) { SYS_STATS_INC(mbox.err); mbox->sem = NULL; return ERR_MEM; }
    memset(mbox->q_mem, 0, sizeof(mbox->q_mem));
    mbox->head = 0;
    mbox->tail = 0;
    mbox->sem  = s;
    SYS_STATS_INC_USED(mbox);
    return ERR_OK;
}

void sys_mbox_free(sys_mbox_t *mbox)
{
    LWIP_ASSERT("mbox != NULL", mbox != NULL);
    if (mbox->sem) {
        semx_destroy((posix_semx_t *)mbox->sem);
        mbox->sem = NULL;
        SYS_STATS_DEC(mbox.used);
    }
}

void sys_mbox_post(sys_mbox_t *q, void *msg)
{
    LWIP_ASSERT("q != NULL", q != NULL);
    sys_prot_t lev = sys_arch_protect();
    u32_t new_head = q->head + 1;
    if (new_head >= MAX_QUEUE_ENTRIES) new_head = 0;
    LWIP_ASSERT("mbox is full!", new_head != q->tail);
    q->q_mem[q->head] = msg;
    q->head = new_head;
    sys_arch_unprotect(lev);
    semx_post((posix_semx_t *)q->sem);
}

err_t sys_mbox_trypost(sys_mbox_t *q, void *msg)
{
    LWIP_ASSERT("q != NULL", q != NULL);
    sys_prot_t lev = sys_arch_protect();
    u32_t new_head = q->head + 1;
    if (new_head >= MAX_QUEUE_ENTRIES) new_head = 0;
    if (new_head == q->tail) { sys_arch_unprotect(lev); return ERR_MEM; }
    q->q_mem[q->head] = msg;
    q->head = new_head;
    sys_arch_unprotect(lev);
    semx_post((posix_semx_t *)q->sem);
    return ERR_OK;
}

err_t sys_mbox_trypost_fromisr(sys_mbox_t *q, void *msg)
{
    return sys_mbox_trypost(q, msg);
}

u32_t sys_arch_mbox_fetch(sys_mbox_t *q, void **msg, u32_t timeout)
{
    LWIP_ASSERT("q != NULL", q != NULL);
    if (timeout == 0) {
        semx_timedwait((posix_semx_t *)q->sem, 0);
    } else {
        int r = semx_timedwait((posix_semx_t *)q->sem, timeout);
        if (r != 0) { if (msg) *msg = NULL; return SYS_ARCH_TIMEOUT; }
    }
    sys_prot_t lev = sys_arch_protect();
    if (msg) *msg = q->q_mem[q->tail];
    q->tail++;
    if (q->tail >= MAX_QUEUE_ENTRIES) q->tail = 0;
    sys_arch_unprotect(lev);
    return 0;
}

u32_t sys_arch_mbox_tryfetch(sys_mbox_t *q, void **msg)
{
    LWIP_ASSERT("q != NULL", q != NULL);
    posix_semx_t *s = (posix_semx_t *)q->sem;
    u32_t ret = SYS_MBOX_EMPTY;

    pthread_mutex_lock(&s->lock);
    if (s->count > 0) { s->count--; ret = 0; }
    pthread_mutex_unlock(&s->lock);

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

/* ---------- Thread ---------- */

struct _lwip_thread_ctx {
    lwip_thread_fn fn;
    void          *arg;
};

static void *_lwip_thread_entry(void *p)
{
    struct _lwip_thread_ctx ctx = *(struct _lwip_thread_ctx *)p;
    free(p);
    ctx.fn(ctx.arg);
    return NULL;
}

sys_thread_t sys_thread_new(const char *name, lwip_thread_fn function,
                            void *arg, int stacksize, int prio)
{
    LWIP_UNUSED_ARG(name);
    LWIP_UNUSED_ARG(stacksize);
    LWIP_UNUSED_ARG(prio);

    pthread_t *th = (pthread_t *)malloc(sizeof(pthread_t));
    if (!th) return 0;
    struct _lwip_thread_ctx *ctx =
        (struct _lwip_thread_ctx *)malloc(sizeof(struct _lwip_thread_ctx));
    if (!ctx) { free(th); return 0; }
    ctx->fn  = function;
    ctx->arg = arg;

    if (pthread_create(th, NULL, _lwip_thread_entry, ctx) != 0) {
        free(ctx);
        free(th);
        return 0;
    }
    pthread_detach(*th);
    return (sys_thread_t)(uintptr_t)th;
}

/* Optional stubs */
sys_sem_t *sys_arch_netconn_sem_get(void) { return NULL; }
void sys_arch_netconn_sem_alloc(void) {}
void sys_arch_netconn_sem_free(void) {}
int  lwip_win32_keypressed(void) { return 0; }
