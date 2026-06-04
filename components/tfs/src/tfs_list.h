/*
 * tfs_list.h — Intrusive doubly-linked list (internal use only)
 *
 * Modelled after the Linux kernel list.h but fully self-contained.
 * No external dependencies beyond stddef.h.
 */

#ifndef TFS_LIST_H
#define TFS_LIST_H

#include <stddef.h>

typedef struct tfs_list_head {
    struct tfs_list_head *next;
    struct tfs_list_head *prev;
} tfs_list_t;

/* Get pointer to containing struct */
#define tfs_list_entry(ptr, type, member) \
    ((type *)((char *)(ptr) - offsetof(type, member)))

/* Iterate forwards */
#define tfs_list_for_each(pos, head) \
    for ((pos) = (head)->next; (pos) != (head); (pos) = (pos)->next)

/* Iterate forwards, safe against removal */
#define tfs_list_for_each_safe(pos, n, head) \
    for ((pos) = (head)->next, (n) = (pos)->next; \
         (pos) != (head); \
         (pos) = (n), (n) = (pos)->next)

/* Iterate over entries */
#define tfs_list_for_each_entry(pos, head, member) \
    for ((pos) = tfs_list_entry((head)->next, __typeof__(*(pos)), member); \
         &(pos)->member != (head); \
         (pos) = tfs_list_entry((pos)->member.next, __typeof__(*(pos)), member))

#define tfs_list_for_each_entry_safe(pos, n, head, member) \
    for ((pos) = tfs_list_entry((head)->next, __typeof__(*(pos)), member),     \
         (n)   = tfs_list_entry((pos)->member.next, __typeof__(*(pos)), member); \
         &(pos)->member != (head);                                              \
         (pos) = (n),                                                           \
         (n)   = tfs_list_entry((pos)->member.next, __typeof__(*(pos)), member))

/*-------------------------------------------------------------------
 *  Inline operations
 *-------------------------------------------------------------------*/

static inline void tfs_list_init(tfs_list_t *head)
{
    head->next = head;
    head->prev = head;
}

static inline int tfs_list_empty(const tfs_list_t *head)
{
    return head->next == head;
}

static inline void tfs_list_add(tfs_list_t *new_node, tfs_list_t *head)
{
    /* Insert after head */
    new_node->next = head->next;
    new_node->prev = head;
    head->next->prev = new_node;
    head->next = new_node;
}

static inline void tfs_list_add_tail(tfs_list_t *new_node, tfs_list_t *head)
{
    /* Insert before head (i.e. at tail) */
    new_node->next = head;
    new_node->prev = head->prev;
    head->prev->next = new_node;
    head->prev = new_node;
}

static inline void tfs_list_del(tfs_list_t *entry)
{
    entry->prev->next = entry->next;
    entry->next->prev = entry->prev;
    /* Poison the removed entry */
    entry->next = entry;
    entry->prev = entry;
}

static inline void tfs_list_move(tfs_list_t *entry, tfs_list_t *head)
{
    tfs_list_del(entry);
    tfs_list_add(entry, head);
}

static inline void tfs_list_move_tail(tfs_list_t *entry, tfs_list_t *head)
{
    tfs_list_del(entry);
    tfs_list_add_tail(entry, head);
}

#endif /* TFS_LIST_H */
