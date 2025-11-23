#include "uv.h"
#include "luat_base.h"
#include "luat_queue_pc.h"
#include "luat_malloc.h"

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
        // item->prev = head;
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
    memcpy(item, head, head->size + sizeof(uv_queue_item_t) - 4);
    if (head->next == NULL) {
        queue->next = NULL;
    }
    else {
        queue->next = head->next;
    }
    luat_heap_free(head);
    return 0;
}
