//
// Copyright (c) 2022 ZettaScale Technology
//
// This program and the accompanying materials are made available under the
// terms of the Eclipse Public License 2.0 which is available at
// http://www.eclipse.org/legal/epl-2.0, or the Apache License, Version 2.0
// which is available at https://www.apache.org/licenses/LICENSE-2.0.
//
// SPDX-License-Identifier: EPL-2.0 OR Apache-2.0
//
// Contributors:
//   ZettaScale Zenoh Team, <zenoh@zettascale.tech>
//

#include "zenoh-pico/collections/list.h"

#include <assert.h>
#include <stddef.h>
#include <string.h>

#include "zenoh-pico/utils/logging.h"
#include "zenoh-pico/utils/pointers.h"

/*-------- Inner single-linked list --------*/
static _z_list_t *_z_list_new(void *x) {
    _z_list_t *xs = (_z_list_t *)z_malloc(sizeof(_z_list_t));
    if (xs == NULL) {
        _Z_ERROR("Failed to allocate list element.");
        return NULL;
    }
    xs->_val = x;
    xs->_next = NULL;
    return xs;
}

_z_list_t *_z_list_push(_z_list_t *xs, void *x) {
    _z_list_t *lst = _z_list_new(x);
    if (lst == NULL) {
        return xs;
    }
    lst->_next = xs;
    return lst;
}

_z_list_t *_z_list_push_after(_z_list_t *xs, void *x) {
    _z_list_t *l = _z_list_new(x);
    if (l == NULL || xs == NULL) {
        return l;
    }

    l->_next = xs->_next;
    xs->_next = l;

    return xs;
}

_z_list_t *_z_list_push_back(_z_list_t *xs, void *x) {
    if (xs == NULL) {
        return _z_list_new(x);
    }
    _z_list_t *l = xs;
    while (l->_next != NULL) {
        l = l->_next;
    }
    l->_next = _z_list_new(x);
    return xs;
}

_z_list_t *_z_list_push_sorted(_z_list_t *xs, z_element_cmp_f c_f, void *x) {
    if (xs == NULL) {
        return _z_list_new(x);
    }

    _z_list_t *l = xs;
    _z_list_t *prev = NULL;

    while (l != NULL && c_f(l->_val, x) <= 0) {
        prev = l;
        l = l->_next;
    }

    _z_list_t *new_elem = _z_list_new(x);
    if (new_elem == NULL) {
        return xs;
    }

    if (prev == NULL) {
        new_elem->_next = xs;
        return new_elem;
    } else {
        new_elem->_next = l;
        prev->_next = new_elem;
        return xs;
    }
}

size_t _z_list_len(const _z_list_t *xs) {
    size_t len = 0;
    _z_list_t *l = (_z_list_t *)xs;
    while (l != NULL) {
        len = len + (size_t)1;
        l = _z_list_next(l);
    }
    return len;
}

_z_list_t *_z_list_pop(_z_list_t *xs, z_element_free_f f_f, void **x) {
    if (xs == NULL) {
        return xs;
    }
    _z_list_t *head = xs;
    _z_list_t *l = head->_next;
    if (x != NULL) {
        *x = head->_val;
    } else {
        f_f(&head->_val);
    }
    z_free(head);
    return l;
}

_z_list_t *_z_list_find(const _z_list_t *xs, z_element_eq_f c_f, const void *e) {
    _z_list_t *l = (_z_list_t *)xs;
    _z_list_t *ret = NULL;
    while (l != NULL) {
        void *head = _z_list_value(l);
        if (c_f(e, head)) {
            ret = l;
            break;
        }
        l = _z_list_next(l);
    }
    return ret;
}

_z_list_t *_z_list_drop_element(_z_list_t *list, _z_list_t *prev, z_element_free_f f_f) {
    _z_list_t *dropped = NULL;
    if (prev == NULL) {  // Head removal
        dropped = list;
        list = list->_next;
    } else {  // Other cases
        dropped = prev->_next;
        if (dropped != NULL) {
            prev->_next = dropped->_next;
        }
    }
    if (dropped != NULL) {
        f_f(&dropped->_val);
        z_free(dropped);
    }
    return list;
}

_z_list_t *_z_list_drop_filter(_z_list_t *xs, z_element_free_f f_f, z_element_eq_f c_f, const void *left,
                               bool only_first) {
    _z_list_t *l = (_z_list_t *)xs;
    _z_list_t *previous = xs;
    _z_list_t *current = xs;

    while (current != NULL) {
        if (c_f(left, current->_val)) {
            _z_list_t *next = current->_next;
            _z_list_t *this_ = current;

            // head removal
            if (this_ == l) {
                l = l->_next;
            }
            // tail removal
            else if (this_->_next == NULL) {
                previous->_next = NULL;
            }
            // middle removal
            else {
                previous->_next = this_->_next;
            }

            f_f(&this_->_val);
            z_free(this_);
            if (only_first) {
                break;
            }
            current = next;
        } else {
            previous = current;
            current = current->_next;
        }
    }

    return l;
}

_z_list_t *_z_list_extract_filter(_z_list_t *head, z_element_eq_f c_f, const void *left, _z_list_t **extracted,
                                  bool only_first) {
    _z_list_t self_head = {0};
    _z_list_t extracted_head = {0};
    _z_list_t *self_tail = &self_head;
    _z_list_t *extracted_tail = &extracted_head;
    _z_list_t *current = head;
    while (current != NULL) {
        _z_list_t *next = current->_next;
        current->_next = NULL;
        if (c_f(left, current->_val)) {
            extracted_tail->_next = current;
            extracted_tail = extracted_tail->_next;
            if (only_first) {
                self_tail->_next = next;
                break;
            }
        } else {
            self_tail->_next = current;
            self_tail = self_tail->_next;
        }
        current = next;
    }

    *extracted = extracted_head._next;
    return self_head._next;
}

_z_list_t *_z_list_clone(const _z_list_t *xs, z_element_clone_f d_f) {
    _z_list_t *new = NULL;

    const _z_list_t *curr = xs;
    while (curr != NULL) {
        void *x = d_f(_z_list_value(curr));
        new = _z_list_push_back(new, x);
        curr = _z_list_next(curr);
    }

    return new;
}

/**
 * Free the list in deep. This function frees
 * the inner void * to the element of the list.
 */
void _z_list_free(_z_list_t **xs, z_element_free_f f) {
    _z_list_t *ptr = *xs;
    while (ptr != NULL) {
        ptr = _z_list_pop(ptr, f, NULL);
    }

    *xs = NULL;
}

/*-------- Inner sized single-linked list --------*/
typedef struct _z_slist_node_data_t {
    _z_slist_t *next;
} _z_slist_node_data_t;

#define NODE_DATA_SIZE sizeof(_z_slist_node_data_t)

static inline _z_slist_node_data_t *_z_slist_node_data(const _z_slist_t *list) { return (_z_slist_node_data_t *)list; }

static inline void *_z_slist_node_value(const _z_slist_t *node) {
    return (void *)_z_ptr_u8_offset((uint8_t *)node, (ptrdiff_t)NODE_DATA_SIZE);
}

static _z_slist_t *_z_slist_new(const void *value, size_t value_size, z_element_copy_f d_f, bool use_elem_f) {
    size_t node_size = NODE_DATA_SIZE + value_size;
    _z_slist_t *node = (_z_slist_t *)z_malloc(node_size);
    if (node == NULL) {
        _Z_ERROR("Failed to allocate list element.");
        return node;
    }
    memset(node, 0, NODE_DATA_SIZE);
    if (use_elem_f) {
        d_f(_z_slist_node_value(node), value);
    } else {
        memcpy(_z_slist_node_value(node), value, value_size);
    }
    return node;
}

static _z_slist_t *_z_slist_new_empty(size_t value_size) {
    size_t node_size = NODE_DATA_SIZE + value_size;
    _z_slist_t *node = (_z_slist_t *)z_malloc(node_size);
    if (node == NULL) {
        _Z_ERROR("Failed to allocate list element.");
        return node;
    }
    memset(node, 0, NODE_DATA_SIZE);
    return node;
}

_z_slist_t *_z_slist_push_empty(_z_slist_t *node, size_t value_size) {
    _z_slist_t *new_node = _z_slist_new_empty(value_size);
    if (new_node == NULL) {
        return node;
    }
    _z_slist_node_data_t *node_data = _z_slist_node_data(new_node);
    node_data->next = node;
    return new_node;
}

_z_slist_t *_z_slist_push(_z_slist_t *node, const void *value, size_t value_size, z_element_copy_f d_f,
                          bool use_elem_f) {
    _z_slist_t *new_node = _z_slist_new(value, value_size, d_f, use_elem_f);
    if (new_node == NULL) {
        return node;
    }
    _z_slist_node_data_t *node_data = _z_slist_node_data(new_node);
    node_data->next = node;
    return new_node;
}

_z_slist_t *_z_slist_push_back(_z_slist_t *node, const void *value, size_t value_size, z_element_copy_f d_f,
                               bool use_elem_f) {
    if (node == NULL) {
        return _z_slist_new(value, value_size, d_f, use_elem_f);
    }
    _z_slist_node_data_t *node_data = _z_slist_node_data(node);
    while (node_data->next != NULL) {
        node_data = _z_slist_node_data(node_data->next);
    }
    node_data->next = _z_slist_new(value, value_size, d_f, use_elem_f);
    return node;
}

void *_z_slist_value(const _z_slist_t *node) { return _z_slist_node_value(node); }

_z_slist_t *_z_slist_next(const _z_slist_t *node) {
    _z_slist_node_data_t *node_data = _z_slist_node_data(node);
    return _z_slist_node_data(node_data)->next;
}

size_t _z_slist_len(const _z_slist_t *node) {
    size_t len = 0;
    _z_slist_node_data_t *node_data = _z_slist_node_data(node);
    while (node_data != NULL) {
        len += (size_t)1;
        node_data = _z_slist_node_data(node_data->next);
    }
    return len;
}

_z_slist_t *_z_slist_pop(_z_slist_t *node, z_element_clear_f f_f) {
    if (node == NULL) {
        return node;
    }
    _z_slist_t *next_node = _z_slist_node_data(node)->next;
    f_f(_z_slist_node_value(node));
    z_free(node);
    return next_node;
}

_z_slist_t *_z_slist_find(const _z_slist_t *node, z_element_eq_f c_f, const void *target_val) {
    _z_slist_t *curr_node = (_z_slist_t *)node;
    _z_slist_node_data_t *node_data = _z_slist_node_data(curr_node);
    while (node_data != NULL) {
        if (c_f(target_val, _z_slist_node_value(curr_node))) {
            return curr_node;
        }
        curr_node = node_data->next;
        node_data = _z_slist_node_data(curr_node);
    }
    return NULL;
}

_z_slist_t *_z_slist_drop_element(_z_slist_t *list, _z_slist_t *prev, z_element_clear_f f_f) {
    _z_slist_t *dropped = NULL;
    if (prev == NULL) {  // Head removal
        dropped = list;
        list = _z_slist_node_data(list)->next;
    } else {  // Other cases
        dropped = _z_slist_node_data(prev)->next;
        if (dropped != NULL) {
            _z_slist_node_data(prev)->next = _z_slist_node_data(dropped)->next;
        }
    }
    if (dropped != NULL) {
        f_f(_z_slist_node_value(dropped));
        z_free(dropped);
    }
    return list;
}

_z_slist_t *_z_slist_drop_filter(_z_slist_t *head, z_element_clear_f f_f, z_element_eq_f c_f, const void *target_val,
                                 bool only_first) {
    _z_slist_t *previous = head;
    _z_slist_t *current = head;
    while (current != NULL) {
        if (c_f(target_val, _z_slist_node_value(current))) {
            if (current == head) {  // head removal
                head = _z_slist_node_data(head)->next;
            } else if (_z_slist_node_data(current)->next == NULL) {  // tail removal
                _z_slist_node_data(previous)->next = NULL;
            } else {  // middle removal
                _z_slist_node_data(previous)->next = _z_slist_node_data(current)->next;
            }
            _z_slist_t *next = _z_slist_node_data(current)->next;
            f_f(_z_slist_node_value(current));
            z_free(current);
            if (only_first) {
                break;
            }
            current = next;
        } else {
            previous = current;
            current = _z_slist_node_data(current)->next;
        }
    }
    return head;
}

_z_slist_t *_z_slist_extract_filter(_z_slist_t *head, z_element_eq_f c_f, const void *target_val,
                                    _z_slist_t **extracted, bool only_first) {
    _z_slist_node_data_t self_head = {0};
    _z_slist_node_data_t extracted_head = {0};
    _z_slist_node_data_t *self_tail = &self_head;
    _z_slist_node_data_t *extracted_tail = &extracted_head;
    _z_slist_t *current = head;
    while (current != NULL) {
        _z_slist_t *next = _z_slist_node_data(current)->next;
        _z_slist_node_data(current)->next = NULL;
        if (c_f(target_val, _z_slist_node_value(current))) {
            extracted_tail->next = current;
            extracted_tail = _z_slist_node_data(extracted_tail->next);
            if (only_first) {
                self_tail->next = next;
                break;
            }
        } else {
            self_tail->next = current;
            self_tail = _z_slist_node_data(self_tail->next);
        }
        current = next;
    }

    *extracted = extracted_head.next;
    return self_head.next;
}

_z_slist_t *_z_slist_clone(const _z_slist_t *node, size_t value_size, z_element_copy_f d_f, bool use_elem_f) {
    _z_slist_t *new_node = NULL;
    _z_slist_t *curr_node = (_z_slist_t *)node;
    while (curr_node != NULL) {
        void *value = _z_slist_node_value(curr_node);
        new_node = _z_slist_push(new_node, value, value_size, d_f, use_elem_f);
        curr_node = _z_slist_node_data(curr_node)->next;
    }
    return new_node;
}

void _z_slist_free(_z_slist_t **node, z_element_clear_f f) {
    _z_slist_t *ptr = *node;
    while (ptr != NULL) {
        ptr = _z_slist_pop(ptr, f);
    }
    *node = NULL;
}
