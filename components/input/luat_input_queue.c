#include "luat_base.h"
#ifdef LUAT_USE_INPUT
#include "luat_input.h"
#include <string.h>

static uintptr_t enter(luat_input_queue_t *q)
{
    return q->ops.lock ? q->ops.lock(q->ops.userdata) : 0;
}

static void leave(luat_input_queue_t *q, uintptr_t token)
{
    if (q->ops.unlock) q->ops.unlock(q->ops.userdata, token);
}

static size_t copy_in(luat_input_queue_t *q, size_t pos, const void *src, size_t len)
{
    if (!len) return pos;
    size_t first = q->capacity - pos;
    if (first > len) first = len;
    memcpy(q->buffer + pos, src, first);
    pos += first;
    if (pos == q->capacity) pos = 0;
    if (len > first) {
        memcpy(q->buffer, (const uint8_t *)src + first, len - first);
        pos = len - first;
    }
    return pos;
}

static size_t copy_out(luat_input_queue_t *q, size_t pos, void *dst, size_t len)
{
    if (!len) return pos;
    size_t first = q->capacity - pos;
    if (first > len) first = len;
    memcpy(dst, q->buffer + pos, first);
    pos += first;
    if (pos == q->capacity) pos = 0;
    if (len > first) {
        memcpy((uint8_t *)dst + first, q->buffer, len - first);
        pos = len - first;
    }
    return pos;
}

int luat_input_queue_init(luat_input_queue_t *q, void *buffer, size_t bytes,
    const luat_input_queue_ops_t *ops)
{
    if (!q || !buffer || bytes < sizeof(luat_input_frame_t) ||
        (ops && (!!ops->lock != !!ops->unlock))) return LUAT_INPUT_EINVAL;
    luat_input_queue_ops_t saved = {0};
    if (ops) saved = *ops;
    memset(q, 0, sizeof(*q));
    q->buffer = buffer;
    q->capacity = bytes;
    q->ops = saved;
    return LUAT_INPUT_OK;
}

int luat_input_queue_push_types(luat_input_queue_t *q,
    const luat_input_frame_t *frame, const luat_input_event_t *events, uint32_t types)
{
    if (!q || !q->buffer || !frame || (frame->count && !events)) return LUAT_INPUT_EINVAL;
    luat_input_frame_t selected = *frame;
    int filter = !frame->flags && types != UINT32_MAX;
    if (filter) {
        selected.count = 0;
        for (unsigned i = 0; i < frame->count; i++)
            if (events[i].type < 32 && (types & (UINT32_C(1) << events[i].type))) selected.count++;
        if (!selected.count) return LUAT_INPUT_OK;
    }
    size_t bytes = sizeof(selected) + (size_t)selected.count * sizeof(*events);
    uintptr_t token = enter(q);
    int ret = LUAT_INPUT_OK;
    int notify = 0;
    /* Offsets and a full bit avoid a shared read/modify/write byte counter. */
    size_t available = q->full ? 0 : q->tail >= q->head ?
        q->capacity - (q->tail - q->head) : q->head - q->tail;
    if (q->lost) ret = LUAT_INPUT_ELOST;
    else if (bytes > available) {
        /* Keep loss out-of-band: a full queue cannot reliably enqueue a marker. */
        q->head = q->tail = 0;
        q->full = 0;
        q->lost = 1;
        ret = LUAT_INPUT_ELOST;
        notify = 1;
    } else {
        notify = available == q->capacity;
        q->tail = copy_in(q, q->tail, &selected, sizeof(selected));
        if (filter) {
            for (unsigned i = 0; i < frame->count; i++)
                if (events[i].type < 32 && (types & (UINT32_C(1) << events[i].type)))
                    q->tail = copy_in(q, q->tail, &events[i], sizeof(*events));
        } else q->tail = copy_in(q, q->tail, events, bytes - sizeof(*frame));
        q->full = q->tail == q->head;
    }
    leave(q, token);
    if (notify && q->ops.notify) q->ops.notify(q->ops.userdata);
    return ret;
}

int luat_input_queue_push(luat_input_queue_t *q,
    const luat_input_frame_t *frame, const luat_input_event_t *events)
{
    return luat_input_queue_push_types(q, frame, events, UINT32_MAX);
}

int luat_input_queue_peek(luat_input_queue_t *q, luat_input_frame_t *frame)
{
    if (!q || !q->buffer || !frame) return LUAT_INPUT_EINVAL;
    uintptr_t token = enter(q);
    int ret = q->lost ? LUAT_INPUT_ELOST :
        (!q->full && q->head == q->tail ? LUAT_INPUT_EEMPTY : LUAT_INPUT_OK);
    if (!ret) copy_out(q, q->head, frame, sizeof(*frame));
    leave(q, token);
    return ret;
}

void luat_input_queue_receive(void *queue,
    const luat_input_frame_t *frame, const luat_input_event_t *events)
{
    (void)luat_input_queue_push(queue, frame, events);
}

int luat_input_queue_read(luat_input_queue_t *q,
    luat_input_frame_t *frame, luat_input_event_t *events, size_t capacity)
{
    if (!q || !q->buffer || !frame) return LUAT_INPUT_EINVAL;
    uintptr_t token = enter(q);
    int ret = LUAT_INPUT_OK;
    if (q->lost) ret = LUAT_INPUT_ELOST;
    else if (!q->full && q->head == q->tail) ret = LUAT_INPUT_EEMPTY;
    else {
        size_t pos = copy_out(q, q->head, frame, sizeof(*frame));
        if (frame->count > capacity) ret = LUAT_INPUT_ENOSPC;
        else if (frame->count && !events) ret = LUAT_INPUT_EINVAL;
        else {
            size_t bytes = (size_t)frame->count * sizeof(*events);
            q->head = copy_out(q, pos, events, bytes);
            q->full = 0;
        }
    }
    leave(q, token);
    return ret;
}

int luat_input_queue_reset(luat_input_queue_t *q)
{
    if (!q || !q->buffer) return LUAT_INPUT_EINVAL;
    uintptr_t token = enter(q);
    q->head = q->tail = 0;
    q->full = 0;
    q->lost = 0;
    leave(q, token);
    return LUAT_INPUT_OK;
}
#endif
