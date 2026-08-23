#include "luat_base.h"
#include "luat_queue_pc.h"
#include "luat_malloc.h"

#include <stddef.h>   /* offsetof */

int luat_queue_push(uv_queue_item_t* queue, uv_queue_item_t* item) {
    if (queue == NULL || item == NULL)
        return -1;
    uv_queue_item_t* head = queue;
    while (1) {
        if (head->next != NULL) {
            head = head->next;
            continue;
        }
        head->next = item;
        break;
    }
    return 0;
}

int luat_queue_pop(uv_queue_item_t* queue, uv_queue_item_t* item) {
    if (queue == NULL || item == NULL)
        return -1;
    uv_queue_item_t* head = queue->next;
    if (head == NULL)
        return -1;
    /* Copy both the header (next, size) and the payload (msg[...]) in one go.
     * head->size is the payload byte count (not including the header).
     * offsetof(uv_queue_item_t, msg) avoids the fragile `sizeof - 4` arithmetic
     * that breaks on 64-bit builds. */
    memcpy(item, head, head->size + offsetof(uv_queue_item_t, msg));
    queue->next = head->next;
    luat_heap_free(head);
    return 0;
}
