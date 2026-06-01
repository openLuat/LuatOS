/*
 * nfs_list.h — Intrusive doubly-linked list (internal use only)
 *
 * Modelled after the Linux kernel list.h but fully self-contained.
 * No external dependencies beyond stddef.h.
 */

#ifndef NFS_LIST_H
#define NFS_LIST_H

#include <stddef.h>

typedef struct nfs_list_head {
    struct nfs_list_head *next;
    struct nfs_list_head *prev;
} nfs_list_t;

/* Get pointer to containing struct */
#define nfs_list_entry(ptr, type, member) \
    ((type *)((char *)(ptr) - offsetof(type, member)))

/* Iterate forwards */
#define nfs_list_for_each(pos, head) \
    for ((pos) = (head)->next; (pos) != (head); (pos) = (pos)->next)

/* Iterate forwards, safe against removal */
#define nfs_list_for_each_safe(pos, n, head) \
    for ((pos) = (head)->next, (n) = (pos)->next; \
         (pos) != (head); \
         (pos) = (n), (n) = (pos)->next)

/* Iterate over entries */
#define nfs_list_for_each_entry(pos, head, member) \
    for ((pos) = nfs_list_entry((head)->next, __typeof__(*(pos)), member); \
         &(pos)->member != (head); \
         (pos) = nfs_list_entry((pos)->member.next, __typeof__(*(pos)), member))

#define nfs_list_for_each_entry_safe(pos, n, head, member) \
    for ((pos) = nfs_list_entry((head)->next, __typeof__(*(pos)), member),     \
         (n)   = nfs_list_entry((pos)->member.next, __typeof__(*(pos)), member); \
         &(pos)->member != (head);                                              \
         (pos) = (n),                                                           \
         (n)   = nfs_list_entry((pos)->member.next, __typeof__(*(pos)), member))

/*-------------------------------------------------------------------
 *  Inline operations
 *-------------------------------------------------------------------*/

static inline void nfs_list_init(nfs_list_t *head)
{
    head->next = head;
    head->prev = head;
}

static inline int nfs_list_empty(const nfs_list_t *head)
{
    return head->next == head;
}

static inline void nfs_list_add(nfs_list_t *new_node, nfs_list_t *head)
{
    /* Insert after head */
    new_node->next = head->next;
    new_node->prev = head;
    head->next->prev = new_node;
    head->next = new_node;
}

static inline void nfs_list_add_tail(nfs_list_t *new_node, nfs_list_t *head)
{
    /* Insert before head (i.e. at tail) */
    new_node->next = head;
    new_node->prev = head->prev;
    head->prev->next = new_node;
    head->prev = new_node;
}

static inline void nfs_list_del(nfs_list_t *entry)
{
    entry->prev->next = entry->next;
    entry->next->prev = entry->prev;
    /* Poison the removed entry */
    entry->next = entry;
    entry->prev = entry;
}

static inline void nfs_list_move(nfs_list_t *entry, nfs_list_t *head)
{
    nfs_list_del(entry);
    nfs_list_add(entry, head);
}

static inline void nfs_list_move_tail(nfs_list_t *entry, nfs_list_t *head)
{
    nfs_list_del(entry);
    nfs_list_add_tail(entry, head);
}

#endif /* NFS_LIST_H */
