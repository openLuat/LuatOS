#include "luat_timer_engine.h"
#include "luat_posix_compat.h"
#include "luat_malloc.h"

#include <stdio.h>
#include <string.h>
#include <stdint.h>

/* ------------------------------------------------------------------ */
/* Constants                                                           */
/* ------------------------------------------------------------------ */
#define TIMER_SLOT_MAX  1024
#define TIMER_MAGIC     0xA5C3E1B2u

/* ------------------------------------------------------------------ */
/* Timer slot structure                                                */
/* ------------------------------------------------------------------ */
typedef struct luat_timer_slot {
    uint32_t         magic;       /* TIMER_MAGIC when valid */
    luat_timer_cb_t  cb;
    void            *param;
    uint64_t         expire_ms;   /* absolute monotonic ms */
    uint32_t         period_ms;   /* 0 = one-shot */
    int              repeat;      /* 1 = repeat */
    int              active;      /* 1 = scheduled */
    int              deleted;     /* 1 = pending free */
} luat_timer_slot_t;

/* ------------------------------------------------------------------ */
/* Engine globals                                                      */
/* ------------------------------------------------------------------ */
static luat_timer_slot_t  *g_slots[TIMER_SLOT_MAX];  /* slot pointer table */
static pthread_mutex_t     g_lock;
static pthread_cond_t      g_cond;
static pthread_t           g_thread;
static int                 g_running = 0;

/* ------------------------------------------------------------------ */
/* Internal helpers                                                    */
/* ------------------------------------------------------------------ */

/* Find the earliest active timer's expire_ms; returns UINT64_MAX if none. */
static uint64_t earliest_expire_locked(void) {
    uint64_t earliest = UINT64_MAX;
    for (int i = 0; i < TIMER_SLOT_MAX; i++) {
        luat_timer_slot_t *s = g_slots[i];
        if (s && s->active && !s->deleted) {
            if (s->expire_ms < earliest) {
                earliest = s->expire_ms;
            }
        }
    }
    return earliest;
}

/* Engine background thread */
static void *engine_thread(void *arg) {
    (void)arg;
    pthread_mutex_lock(&g_lock);
    while (g_running) {
        uint64_t now_ms = luat_monotonic_ms();
        uint64_t earliest = earliest_expire_locked();

        if (earliest == UINT64_MAX) {
            /* No active timers – wait indefinitely for a signal */
            pthread_cond_wait(&g_cond, &g_lock);
            continue;
        }

        if (earliest > now_ms) {
            /* Sleep until earliest deadline */
            uint32_t wait_ms = (uint32_t)(earliest - now_ms);
            struct timespec abs;
            luat_calc_abs_timeout(&abs, wait_ms);
            /* Ignore return: ETIMEDOUT is expected */
            pthread_cond_timedwait(&g_cond, &g_lock, &abs);
            /* Re-evaluate after wakeup (signal may have arrived early) */
            continue;
        }

        /* --- Fire all expired timers --- */
        now_ms = luat_monotonic_ms();
        for (int i = 0; i < TIMER_SLOT_MAX; i++) {
            luat_timer_slot_t *s = g_slots[i];
            if (!s || !s->active || s->deleted) continue;
            if (s->expire_ms > now_ms) continue;

            luat_timer_cb_t cb    = s->cb;
            void           *param = s->param;

            if (s->repeat && s->period_ms > 0) {
                /* Re-arm: advance expire by period (catch-up safe) */
                s->expire_ms += s->period_ms;
                if (s->expire_ms < now_ms) {
                    /* We fell behind; reset to now+period */
                    s->expire_ms = now_ms + s->period_ms;
                }
            } else {
                s->active = 0;
            }

            /* Release lock while calling the callback to avoid deadlock
             * if the callback itself calls timer API. */
            pthread_mutex_unlock(&g_lock);
            if (cb) cb(param);
            pthread_mutex_lock(&g_lock);
            /* NOTE: do NOT access `s` after the callback — the callback may
             * have called luat_timer_engine_delete(handle) which already freed
             * `s` via the found=1 path.  The deleted flag path is unreachable
             * (delete always finds the slot while it is still in g_slots). */
        }
    }
    pthread_mutex_unlock(&g_lock);
    return NULL;
}

/* ------------------------------------------------------------------ */
/* Public API                                                          */
/* ------------------------------------------------------------------ */

void luat_timer_engine_init(void) {
    if (g_running) return;
    memset(g_slots, 0, sizeof(g_slots));
    pthread_mutex_init(&g_lock, NULL);
    pthread_cond_init(&g_cond, NULL);
    g_running = 1;
    pthread_attr_t attr;
    pthread_attr_init(&attr);
    pthread_attr_setdetachstate(&attr, PTHREAD_CREATE_JOINABLE);
    pthread_create(&g_thread, &attr, engine_thread, NULL);
    pthread_attr_destroy(&attr);
}

void luat_timer_engine_deinit(void) {
    if (!g_running) return;
    pthread_mutex_lock(&g_lock);
    g_running = 0;
    pthread_cond_signal(&g_cond);
    pthread_mutex_unlock(&g_lock);
    pthread_join(g_thread, NULL);
    /* Free all remaining slots */
    pthread_mutex_lock(&g_lock);
    for (int i = 0; i < TIMER_SLOT_MAX; i++) {
        if (g_slots[i]) {
            luat_heap_free(g_slots[i]);
            g_slots[i] = NULL;
        }
    }
    pthread_mutex_unlock(&g_lock);
    pthread_mutex_destroy(&g_lock);
    pthread_cond_destroy(&g_cond);
}

luat_timer_handle_t luat_timer_engine_create(luat_timer_cb_t cb, void *param) {
    luat_timer_slot_t *s = (luat_timer_slot_t*)luat_heap_malloc(sizeof(luat_timer_slot_t));
    if (!s) return NULL;
    memset(s, 0, sizeof(luat_timer_slot_t));
    s->magic  = TIMER_MAGIC;
    s->cb     = cb;
    s->param  = param;

    pthread_mutex_lock(&g_lock);
    int placed = 0;
    for (int i = 0; i < TIMER_SLOT_MAX; i++) {
        if (g_slots[i] == NULL) {
            g_slots[i] = s;
            placed = 1;
            break;
        }
    }
    pthread_mutex_unlock(&g_lock);

    if (!placed) {
        luat_heap_free(s);
        return NULL;
    }
    return (luat_timer_handle_t)s;
}

void luat_timer_engine_set_cb(luat_timer_handle_t handle, luat_timer_cb_t cb, void *param) {
    luat_timer_slot_t *s = (luat_timer_slot_t*)handle;
    if (!s || s->magic != TIMER_MAGIC) return;
    pthread_mutex_lock(&g_lock);
    s->cb    = cb;
    s->param = param;
    pthread_mutex_unlock(&g_lock);
}

int luat_timer_engine_start(luat_timer_handle_t handle, uint32_t ms, int repeat) {
    luat_timer_slot_t *s = (luat_timer_slot_t*)handle;
    if (!s || s->magic != TIMER_MAGIC || ms == 0) return -1;
    pthread_mutex_lock(&g_lock);
    s->expire_ms = luat_monotonic_ms() + ms;
    s->period_ms = ms;
    s->repeat    = repeat;
    s->active    = 1;
    s->deleted   = 0;
    pthread_cond_signal(&g_cond);  /* wake engine to re-evaluate deadline */
    pthread_mutex_unlock(&g_lock);
    return 0;
}

void luat_timer_engine_stop(luat_timer_handle_t handle) {
    luat_timer_slot_t *s = (luat_timer_slot_t*)handle;
    if (!s || s->magic != TIMER_MAGIC) return;
    pthread_mutex_lock(&g_lock);
    s->active = 0;
    pthread_mutex_unlock(&g_lock);
}

void luat_timer_engine_delete(luat_timer_handle_t handle) {
    luat_timer_slot_t *s = (luat_timer_slot_t*)handle;
    if (!s || s->magic != TIMER_MAGIC) return;
    pthread_mutex_lock(&g_lock);
    s->active  = 0;
    s->deleted = 1;
    /* Find the slot and remove it from the table.
     * If the engine thread is currently firing this timer's callback the
     * deleted flag causes engine_thread to free it after callback returns. */
    int found = 0;
    for (int i = 0; i < TIMER_SLOT_MAX; i++) {
        if (g_slots[i] == s) {
            g_slots[i] = NULL;
            found = 1;
            break;
        }
    }
    pthread_mutex_unlock(&g_lock);
    if (found) {
        /* Safe to free: we removed it from the table under the lock,
         * so the engine thread will not touch it again. */
        s->magic = 0;
        luat_heap_free(s);
    }
}

int luat_timer_engine_is_active(luat_timer_handle_t handle) {
    luat_timer_slot_t *s = (luat_timer_slot_t*)handle;
    if (!s || s->magic != TIMER_MAGIC) return 0;
    pthread_mutex_lock(&g_lock);
    int active = s->active && !s->deleted;
    pthread_mutex_unlock(&g_lock);
    return active;
}

uint32_t luat_timer_engine_remaining_ms(luat_timer_handle_t handle) {
    luat_timer_slot_t *s = (luat_timer_slot_t*)handle;
    if (!s || s->magic != TIMER_MAGIC) return 0;
    pthread_mutex_lock(&g_lock);
    uint32_t remaining = 0;
    if (s->active && !s->deleted) {
        uint64_t now = luat_monotonic_ms();
        if (s->expire_ms > now) {
            remaining = (uint32_t)(s->expire_ms - now);
        }
    }
    pthread_mutex_unlock(&g_lock);
    return remaining;
}
