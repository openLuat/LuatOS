/* Session-scoped notification ownership shared by callbacks and the VoIP task. */
#ifndef LUAT_VOIP_EVENT_H
#define LUAT_VOIP_EVENT_H

#include <stdint.h>
#ifdef _MSC_VER
#include <intrin.h>
#endif

#define VOIP_EVENT_BATCH_MAX 4U
#define VOIP_EVENT_SESSION_MAX 0x3FFFFFFFU
#define VOIP_EVENT_PENDING 1U
#define VOIP_EVENT_DIRTY 2U

/* All accesses to a wake word use 32-bit CAS, including on PC ports whose
 * RTOS critical-section and scheduler-suspend implementations are no-ops. */
static inline uint32_t voip_event_cas(volatile uint32_t *word, uint32_t old, uint32_t value)
{
#ifdef _MSC_VER
    return (uint32_t)_InterlockedCompareExchange((volatile long *)word, (long)value, (long)old);
#else
    return __sync_val_compare_and_swap(word, old, value);
#endif
}

static inline uint32_t voip_event_load(volatile uint32_t *word)
{
    return voip_event_cas(word, 0, 0);
}

static inline void voip_event_reset(volatile uint32_t *word, uint32_t session)
{
    uint32_t old;
    do { old = voip_event_load(word); }
    while (voip_event_cas(word, old, session << 2) != old);
}

/* Returns true only to the producer responsible for enqueueing a wakeup. */
static inline int voip_event_claim(volatile uint32_t *word, uint32_t session)
{
    uint32_t old;
    do {
        old = voip_event_load(word);
        if ((old >> 2) != session) return 0;
    } while (voip_event_cas(word, old, old | VOIP_EVENT_PENDING | VOIP_EVENT_DIRTY) != old);
    return !(old & VOIP_EVENT_PENDING);
}

static inline int voip_event_begin(volatile uint32_t *word, uint32_t session)
{
    uint32_t old;
    do {
        old = voip_event_load(word);
        if ((old >> 2) != session || !(old & VOIP_EVENT_PENDING)) return 0;
    } while (voip_event_cas(word, old, old & ~VOIP_EVENT_DIRTY) != old);
    return 1;
}

/* Retain ownership for one tail continuation, or atomically release it.
 * A producer racing the release sets DIRTY and makes the CAS retry. */
static inline int voip_event_finish(volatile uint32_t *word, uint32_t session, int more)
{
    uint32_t old;
    do {
        old = voip_event_load(word);
        if ((old >> 2) != session || !(old & VOIP_EVENT_PENDING)) return 0;
        if (more || (old & VOIP_EVENT_DIRTY)) return 1;
    } while (voip_event_cas(word, old, old & ~VOIP_EVENT_PENDING) != old);
    return 0;
}

/* Failed enqueue: retain DIRTY, release ownership for the next producer.
 * A delayed failure from an old session must not reset a new session. */
static inline void voip_event_send_failed(volatile uint32_t *word, uint32_t session)
{
    uint32_t old;
    do {
        old = voip_event_load(word);
        if ((old >> 2) != session || !(old & VOIP_EVENT_PENDING)) return;
    } while (voip_event_cas(word, old, (old & ~VOIP_EVENT_PENDING) | VOIP_EVENT_DIRTY) != old);
}

static inline void voip_event_count_failure(volatile uint32_t *word)
{
#ifdef _MSC_VER
    _InterlockedIncrement((volatile long *)word);
#else
    __sync_add_and_fetch(word, 1U);
#endif
}

#endif
