//
// Copyright (c) 2026 ZettaScale Technology
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

// Hashmap with separate chaining using a fixed-size node pool.
//
// Each bucket is the head of an intrusive singly-linked list.  Nodes are
// allocated from a flat pool of _ZP_HASHMAP_TEMPLATE_CAPACITY
// elements — no heap allocation is performed.
//
// User must define the following macros before including this file:
//
// Required:
//   _ZP_HASHMAP_TEMPLATE_KEY_TYPE
//       type of the key
//   _ZP_HASHMAP_TEMPLATE_VAL_TYPE
//       type of the value
//   _ZP_HASHMAP_TEMPLATE_KEY_HASH_FN_NAME(key_ptr) -> size_t
//       hash function for the key
//
// Optional:
//   _ZP_HASHMAP_TEMPLATE_KEY_EQ_FN_NAME(key_a_ptr, key_b_ptr) -> bool
//       equality function for keys (default: memcmp == 0)
//   _ZP_HASHMAP_TEMPLATE_NAME
//       base name for all generated symbols
//       (default: _ZP_CAT(key_type, _ZP_CAT(val_type, hmap)))
//   _ZP_HASHMAP_TEMPLATE_BUCKET_COUNT
//       number of hash buckets
//       (default: 16)
//   _ZP_HASHMAP_TEMPLATE_CAPACITY
//       maximum total number of entries that can be stored
//       (default: _ZP_HASHMAP_TEMPLATE_BUCKET_COUNT)
//   _ZP_HASHMAP_TEMPLATE_KEY_DESTROY_FN_NAME(key_ptr)
//       destroy a key (default: no-op)
//   _ZP_HASHMAP_TEMPLATE_VAL_DESTROY_FN_NAME(val_ptr)
//       destroy a value (default: no-op)
//   _ZP_HASHMAP_TEMPLATE_KEY_MOVE_FN_NAME(dst_ptr, src_ptr)
//       move a key (default: copy then destroy src)
//   _ZP_HASHMAP_TEMPLATE_VAL_MOVE_FN_NAME(dst_ptr, src_ptr)
//       move a value (default: copy then destroy src)

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>
#include <string.h>

#include "zenoh-pico/collections/cat.h"

// ── Required macros ──────────────────────────────────────────────────────────

#ifndef _ZP_HASHMAP_TEMPLATE_KEY_TYPE
#error "_ZP_HASHMAP_TEMPLATE_KEY_TYPE must be defined before including hashmap_template.h"
#define _ZP_HASHMAP_TEMPLATE_KEY_TYPE int
#endif
#ifndef _ZP_HASHMAP_TEMPLATE_VAL_TYPE
#error "_ZP_HASHMAP_TEMPLATE_VAL_TYPE must be defined before including hashmap_template.h"
#define _ZP_HASHMAP_TEMPLATE_VAL_TYPE int
#endif
#ifndef _ZP_HASHMAP_TEMPLATE_KEY_HASH_FN_NAME
#error "_ZP_HASHMAP_TEMPLATE_KEY_HASH_FN_NAME must be defined before including hashmap_template.h"
#endif

// ── Optional macros with defaults ────────────────────────────────────────────
#ifndef _ZP_HASHMAP_TEMPLATE_KEY_EQ_FN_NAME
#define _ZP_HASHMAP_TEMPLATE_KEY_EQ_FN_NAME(key_a_ptr, key_b_ptr) (*(key_a_ptr) == *(key_b_ptr))
#endif

#ifndef _ZP_HASHMAP_TEMPLATE_BUCKET_COUNT
#define _ZP_HASHMAP_TEMPLATE_BUCKET_COUNT 16
#endif
#ifndef _ZP_HASHMAP_TEMPLATE_CAPACITY
#define _ZP_HASHMAP_TEMPLATE_CAPACITY _ZP_HASHMAP_TEMPLATE_BUCKET_COUNT
#endif
#ifndef _ZP_HASHMAP_TEMPLATE_NAME
#define _ZP_HASHMAP_TEMPLATE_NAME _ZP_CAT(_ZP_HASHMAP_TEMPLATE_KEY_TYPE, _ZP_CAT(_ZP_HASHMAP_TEMPLATE_VAL_TYPE, hmap))
#endif

// ── Index type selection ──────────────────────────────────────────────────────
//
// Choose the smallest unsigned type whose maximum representable value is
// strictly greater than CAPACITY (the extra value is used as the sentinel
// "end-of-list / empty-bucket" marker).
//
//   CAPACITY ≤ 254   → uint8_t   (sentinel = 255)
//   CAPACITY ≤ 65534 → uint16_t  (sentinel = 65535)
//   otherwise        → uint32_t  (sentinel = UINT32_MAX)

#if _ZP_HASHMAP_TEMPLATE_CAPACITY <= 254
#define _ZP_HASHMAP_TEMPLATE_INDEX_TYPE uint8_t
#define _ZP_HASHMAP_TEMPLATE_INDEX_NONE ((uint8_t)255)
#elif _ZP_HASHMAP_TEMPLATE_CAPACITY <= 65534
#define _ZP_HASHMAP_TEMPLATE_INDEX_TYPE uint16_t
#define _ZP_HASHMAP_TEMPLATE_INDEX_NONE ((uint16_t)65535)
#else
#define _ZP_HASHMAP_TEMPLATE_INDEX_TYPE uint32_t
#define _ZP_HASHMAP_TEMPLATE_INDEX_NONE ((uint32_t)0xFFFFFFFFu)
#endif

#ifndef _ZP_HASHMAP_TEMPLATE_KEY_DESTROY_FN_NAME
#define _ZP_HASHMAP_TEMPLATE_KEY_DESTROY_FN_NAME(x) (void)(x)
#endif
#ifndef _ZP_HASHMAP_TEMPLATE_VAL_DESTROY_FN_NAME
#define _ZP_HASHMAP_TEMPLATE_VAL_DESTROY_FN_NAME(x) (void)(x)
#endif
#ifndef _ZP_HASHMAP_TEMPLATE_KEY_MOVE_FN_NAME
#define _ZP_HASHMAP_TEMPLATE_KEY_MOVE_FN_NAME(dst, src) \
    *(dst) = *(src);                                    \
    _ZP_HASHMAP_TEMPLATE_KEY_DESTROY_FN_NAME(src);
#endif
#ifndef _ZP_HASHMAP_TEMPLATE_VAL_MOVE_FN_NAME
#define _ZP_HASHMAP_TEMPLATE_VAL_MOVE_FN_NAME(dst, src) \
    *(dst) = *(src);                                    \
    _ZP_HASHMAP_TEMPLATE_VAL_DESTROY_FN_NAME(src);
#endif

// ── Internal name helpers ─────────────────────────────────────────────────────

#define _ZP_HASHMAP_TEMPLATE_TYPE _ZP_CAT(_ZP_HASHMAP_TEMPLATE_NAME, t)
#define _ZP_HASHMAP_TEMPLATE_NODE_TYPE _ZP_CAT(_ZP_HASHMAP_TEMPLATE_NAME, node_t)
#define _ZP_HASHMAP_TEMPLATE_INDEX_TYPEDEF _ZP_CAT(_ZP_HASHMAP_TEMPLATE_NAME, index_t)

// ── Node ──────────────────────────────────────────────────────────────────────
//
// Nodes live in a flat pool. The singly-linked-list "next" pointers are stored
// in a separate parallel array (_next) rather than inside the node struct.
// This avoids the tail-padding that the compiler would otherwise insert after
// a small index field to satisfy the alignment requirement of the key/value
// types.

typedef struct _ZP_HASHMAP_TEMPLATE_NODE_TYPE {
    _ZP_HASHMAP_TEMPLATE_KEY_TYPE key;
    _ZP_HASHMAP_TEMPLATE_VAL_TYPE val;
} _ZP_HASHMAP_TEMPLATE_NODE_TYPE;

// Public typedef for the index type so callers can store/declare indices without
// spelling out the internal macro.
typedef _ZP_HASHMAP_TEMPLATE_INDEX_TYPE _ZP_HASHMAP_TEMPLATE_INDEX_TYPEDEF;

// ── Map type ──────────────────────────────────────────────────────────────────
//
// _next[i]     : index of the next node in the chain for pool slot i,
//                INDEX_NONE = end-of-chain or free-list end.
// _buckets[b]  : index of the first node in bucket b, INDEX_NONE = empty.
// _free_head   : index of the first free pool slot (free list via _next).

typedef struct _ZP_HASHMAP_TEMPLATE_TYPE {
    _ZP_HASHMAP_TEMPLATE_NODE_TYPE _pool[_ZP_HASHMAP_TEMPLATE_CAPACITY];
    _ZP_HASHMAP_TEMPLATE_INDEX_TYPE _next[_ZP_HASHMAP_TEMPLATE_CAPACITY];
    _ZP_HASHMAP_TEMPLATE_INDEX_TYPE _buckets[_ZP_HASHMAP_TEMPLATE_BUCKET_COUNT];
    _ZP_HASHMAP_TEMPLATE_INDEX_TYPE _free_head;
    size_t _size;  // number of live entries
} _ZP_HASHMAP_TEMPLATE_TYPE;

// ── new ───────────────────────────────────────────────────────────────────────

static inline _ZP_HASHMAP_TEMPLATE_TYPE _ZP_CAT(_ZP_HASHMAP_TEMPLATE_NAME, new)(void) {
    _ZP_HASHMAP_TEMPLATE_TYPE map;
    for (_ZP_HASHMAP_TEMPLATE_INDEX_TYPE b = 0; b < _ZP_HASHMAP_TEMPLATE_BUCKET_COUNT; b++) {
        map._buckets[b] = _ZP_HASHMAP_TEMPLATE_INDEX_NONE;
    }
    for (_ZP_HASHMAP_TEMPLATE_INDEX_TYPE i = 0; i + 1 < _ZP_HASHMAP_TEMPLATE_CAPACITY; i++) {
        map._next[i] = (_ZP_HASHMAP_TEMPLATE_INDEX_TYPE)(i + 1);
    }
    map._next[_ZP_HASHMAP_TEMPLATE_CAPACITY - 1] = _ZP_HASHMAP_TEMPLATE_INDEX_NONE;  // end of free list
    map._free_head = 0;
    map._size = 0;
    return map;
}

// ── Internal: allocate / free pool node ──────────────────────────────────────

static inline _ZP_HASHMAP_TEMPLATE_INDEX_TYPE _ZP_CAT(_ZP_HASHMAP_TEMPLATE_NAME,
                                                      pool_alloc)(_ZP_HASHMAP_TEMPLATE_TYPE *map) {
    _ZP_HASHMAP_TEMPLATE_INDEX_TYPE idx = map->_free_head;
    if (idx == _ZP_HASHMAP_TEMPLATE_INDEX_NONE) {
        return _ZP_HASHMAP_TEMPLATE_INDEX_NONE;  // pool full
    }
    map->_free_head = map->_next[idx];
    map->_next[idx] = _ZP_HASHMAP_TEMPLATE_INDEX_NONE;
    return idx;
}

static inline void _ZP_CAT(_ZP_HASHMAP_TEMPLATE_NAME, pool_free)(_ZP_HASHMAP_TEMPLATE_TYPE *map,
                                                                 _ZP_HASHMAP_TEMPLATE_INDEX_TYPE idx) {
    map->_next[idx] = map->_free_head;
    map->_free_head = idx;
}

// ── get_idx ──────────────────────────────────────────────────────────────────
// Returns an index of the node for key, or INDEX_NONE if not found.

static inline _ZP_HASHMAP_TEMPLATE_INDEX_TYPE _ZP_CAT(_ZP_HASHMAP_TEMPLATE_NAME,
                                                      get_idx)(_ZP_HASHMAP_TEMPLATE_TYPE *map,
                                                               const _ZP_HASHMAP_TEMPLATE_KEY_TYPE *key) {
    _ZP_HASHMAP_TEMPLATE_INDEX_TYPE b = (_ZP_HASHMAP_TEMPLATE_INDEX_TYPE)(_ZP_HASHMAP_TEMPLATE_KEY_HASH_FN_NAME(key) %
                                                                          _ZP_HASHMAP_TEMPLATE_BUCKET_COUNT);
    _ZP_HASHMAP_TEMPLATE_INDEX_TYPE idx = map->_buckets[b];
    while (idx != _ZP_HASHMAP_TEMPLATE_INDEX_NONE) {
        _ZP_HASHMAP_TEMPLATE_NODE_TYPE *n = &map->_pool[idx];
        if (_ZP_HASHMAP_TEMPLATE_KEY_EQ_FN_NAME(&n->key, key)) {
            return idx;
        }
        idx = map->_next[idx];
    }
    return _ZP_HASHMAP_TEMPLATE_INDEX_NONE;
}

// ── get ───────────────────────────────────────────────────────────────────────
// Returns a pointer to the value for key, or NULL if not found.

static inline _ZP_HASHMAP_TEMPLATE_VAL_TYPE *_ZP_CAT(_ZP_HASHMAP_TEMPLATE_NAME,
                                                     get)(_ZP_HASHMAP_TEMPLATE_TYPE *map,
                                                          const _ZP_HASHMAP_TEMPLATE_KEY_TYPE *key) {
    _ZP_HASHMAP_TEMPLATE_INDEX_TYPE idx = _ZP_CAT(_ZP_HASHMAP_TEMPLATE_NAME, get_idx)(map, key);
    if (idx != _ZP_HASHMAP_TEMPLATE_INDEX_NONE) {
        return &map->_pool[idx].val;
    }
    return NULL;
}

// ── contains ─────────────────────────────────────────────────────────────────

static inline bool _ZP_CAT(_ZP_HASHMAP_TEMPLATE_NAME, contains)(const _ZP_HASHMAP_TEMPLATE_TYPE *map,
                                                                const _ZP_HASHMAP_TEMPLATE_KEY_TYPE *key) {
    return _ZP_CAT(_ZP_HASHMAP_TEMPLATE_NAME, get)((_ZP_HASHMAP_TEMPLATE_TYPE *)(uintptr_t)map, key) != NULL;
}

// ── size / is_empty ───────────────────────────────────────────────────────────

static inline size_t _ZP_CAT(_ZP_HASHMAP_TEMPLATE_NAME, size)(const _ZP_HASHMAP_TEMPLATE_TYPE *map) {
    return map->_size;
}

static inline bool _ZP_CAT(_ZP_HASHMAP_TEMPLATE_NAME, is_empty)(const _ZP_HASHMAP_TEMPLATE_TYPE *map) {
    return map->_size == 0;
}

// ── index_valid ──────────────────────────────────────────────────────────────
// index_valid: returns true when idx is a live node index (not the sentinel).
static inline bool _ZP_CAT(_ZP_HASHMAP_TEMPLATE_NAME, index_valid)(_ZP_HASHMAP_TEMPLATE_INDEX_TYPE idx) {
    return idx != _ZP_HASHMAP_TEMPLATE_INDEX_NONE;
}
// ── node_at ──────────────────────────────────────────────────────────────────
// Converts a valid index to a pointer to its node.
// Behaviour is undefined if idx is INDEX_NONE.
static inline _ZP_HASHMAP_TEMPLATE_NODE_TYPE *_ZP_CAT(_ZP_HASHMAP_TEMPLATE_NAME,
                                                      node_at)(_ZP_HASHMAP_TEMPLATE_TYPE *map,
                                                               _ZP_HASHMAP_TEMPLATE_INDEX_TYPE idx) {
    return &map->_pool[idx];
}

// ── insert ────────────────────────────────────────────────────────────────────
// Takes ownership of *key and *val via move.
// If key already exists: old value is destroyed, new value is moved in.
// The new key is destroyed (existing key kept).
// Returns the index of the inserted/updated node.
// Returns INDEX_NONE only when the pool is exhausted and the key is not already
// present.  Use index_valid() to check the result; use node_at() to obtain
// a pointer to the node.

static inline _ZP_HASHMAP_TEMPLATE_INDEX_TYPE _ZP_CAT(_ZP_HASHMAP_TEMPLATE_NAME,
                                                      insert)(_ZP_HASHMAP_TEMPLATE_TYPE *map,
                                                              _ZP_HASHMAP_TEMPLATE_KEY_TYPE *key,
                                                              _ZP_HASHMAP_TEMPLATE_VAL_TYPE *val) {
    _ZP_HASHMAP_TEMPLATE_INDEX_TYPE b = (_ZP_HASHMAP_TEMPLATE_INDEX_TYPE)(_ZP_HASHMAP_TEMPLATE_KEY_HASH_FN_NAME(key) %
                                                                          _ZP_HASHMAP_TEMPLATE_BUCKET_COUNT);
    // Walk the chain looking for an existing entry with the same key
    _ZP_HASHMAP_TEMPLATE_INDEX_TYPE idx = map->_buckets[b];
    while (idx != _ZP_HASHMAP_TEMPLATE_INDEX_NONE) {
        _ZP_HASHMAP_TEMPLATE_NODE_TYPE *n = &map->_pool[idx];
        if (_ZP_HASHMAP_TEMPLATE_KEY_EQ_FN_NAME(&n->key, key)) {
            // Update: destroy incoming key, replace value in-place
            _ZP_HASHMAP_TEMPLATE_KEY_DESTROY_FN_NAME(key);
            _ZP_HASHMAP_TEMPLATE_VAL_DESTROY_FN_NAME(&n->val);
            _ZP_HASHMAP_TEMPLATE_VAL_MOVE_FN_NAME(&n->val, val);
            return idx;
        }
        idx = map->_next[idx];
    }
    // New entry — allocate a pool node
    _ZP_HASHMAP_TEMPLATE_INDEX_TYPE new_idx = _ZP_CAT(_ZP_HASHMAP_TEMPLATE_NAME, pool_alloc)(map);
    if (new_idx == _ZP_HASHMAP_TEMPLATE_INDEX_NONE) {
        return _ZP_HASHMAP_TEMPLATE_INDEX_NONE;  // pool exhausted
    }
    _ZP_HASHMAP_TEMPLATE_NODE_TYPE *n = &map->_pool[new_idx];
    _ZP_HASHMAP_TEMPLATE_KEY_MOVE_FN_NAME(&n->key, key);
    _ZP_HASHMAP_TEMPLATE_VAL_MOVE_FN_NAME(&n->val, val);
    // Prepend to bucket chain (O(1))
    map->_next[new_idx] = map->_buckets[b];
    map->_buckets[b] = new_idx;
    map->_size++;
    return new_idx;
}

// ── remove_at ────────────────────────────────────────────────────────────────
// Remove the node at the given pool index (obtained from insert or a prior
// lookup).  Behaviour is undefined if idx is INDEX_NONE or has already been
// freed.  If out_val != NULL the value is moved out; otherwise it is destroyed.

static inline void _ZP_CAT(_ZP_HASHMAP_TEMPLATE_NAME, remove_at)(_ZP_HASHMAP_TEMPLATE_TYPE *map,
                                                                 _ZP_HASHMAP_TEMPLATE_INDEX_TYPE idx,
                                                                 _ZP_HASHMAP_TEMPLATE_VAL_TYPE *out_val) {
    _ZP_HASHMAP_TEMPLATE_NODE_TYPE *n = &map->_pool[idx];
    // Re-derive the bucket from the node's own key so the caller does not need
    // to supply it separately.
    _ZP_HASHMAP_TEMPLATE_INDEX_TYPE b =
        (_ZP_HASHMAP_TEMPLATE_INDEX_TYPE)(_ZP_HASHMAP_TEMPLATE_KEY_HASH_FN_NAME(&n->key) %
                                          _ZP_HASHMAP_TEMPLATE_BUCKET_COUNT);
    // Walk the chain to find the predecessor and unlink idx.
    _ZP_HASHMAP_TEMPLATE_INDEX_TYPE prev = _ZP_HASHMAP_TEMPLATE_INDEX_NONE;
    _ZP_HASHMAP_TEMPLATE_INDEX_TYPE cur = map->_buckets[b];
    while (cur != idx) {
        prev = cur;
        cur = map->_next[cur];
    }
    if (prev == _ZP_HASHMAP_TEMPLATE_INDEX_NONE) {
        map->_buckets[b] = map->_next[idx];  // idx was the bucket head
    } else {
        map->_next[prev] = map->_next[idx];
    }
    _ZP_HASHMAP_TEMPLATE_KEY_DESTROY_FN_NAME(&n->key);
    if (out_val != NULL) {
        _ZP_HASHMAP_TEMPLATE_VAL_MOVE_FN_NAME(out_val, &n->val);
    } else {
        _ZP_HASHMAP_TEMPLATE_VAL_DESTROY_FN_NAME(&n->val);
    }
    _ZP_CAT(_ZP_HASHMAP_TEMPLATE_NAME, pool_free)(map, idx);
    map->_size--;
}

// ── remove ────────────────────────────────────────────────────────────────────
// If out_val != NULL the value is moved out; otherwise it is destroyed.
// Returns true if the key was found.

static inline bool _ZP_CAT(_ZP_HASHMAP_TEMPLATE_NAME, remove)(_ZP_HASHMAP_TEMPLATE_TYPE *map,
                                                              const _ZP_HASHMAP_TEMPLATE_KEY_TYPE *key,
                                                              _ZP_HASHMAP_TEMPLATE_VAL_TYPE *out_val) {
    _ZP_HASHMAP_TEMPLATE_INDEX_TYPE b = (_ZP_HASHMAP_TEMPLATE_INDEX_TYPE)(_ZP_HASHMAP_TEMPLATE_KEY_HASH_FN_NAME(key) %
                                                                          _ZP_HASHMAP_TEMPLATE_BUCKET_COUNT);
    _ZP_HASHMAP_TEMPLATE_INDEX_TYPE prev = _ZP_HASHMAP_TEMPLATE_INDEX_NONE;
    _ZP_HASHMAP_TEMPLATE_INDEX_TYPE idx = map->_buckets[b];
    while (idx != _ZP_HASHMAP_TEMPLATE_INDEX_NONE) {
        _ZP_HASHMAP_TEMPLATE_NODE_TYPE *n = &map->_pool[idx];
        if (_ZP_HASHMAP_TEMPLATE_KEY_EQ_FN_NAME(&n->key, key)) {
            // Unlink from chain
            if (prev == _ZP_HASHMAP_TEMPLATE_INDEX_NONE) {
                map->_buckets[b] = map->_next[idx];  // was the head
            } else {
                map->_next[prev] = map->_next[idx];
            }
            _ZP_HASHMAP_TEMPLATE_KEY_DESTROY_FN_NAME(&n->key);
            if (out_val != NULL) {
                _ZP_HASHMAP_TEMPLATE_VAL_MOVE_FN_NAME(out_val, &n->val);
            } else {
                _ZP_HASHMAP_TEMPLATE_VAL_DESTROY_FN_NAME(&n->val);
            }
            _ZP_CAT(_ZP_HASHMAP_TEMPLATE_NAME, pool_free)(map, idx);
            map->_size--;
            return true;
        }
        prev = idx;
        idx = map->_next[idx];
    }
    return false;
}

// ── destroy ─────────────────────────────────────────────────────────────────────
// Destroys all entries and resets the map for reuse (does not free the map).

static inline void _ZP_CAT(_ZP_HASHMAP_TEMPLATE_NAME, destroy)(_ZP_HASHMAP_TEMPLATE_TYPE *map) {
    // Walk every bucket chain and destroy live entries
    for (_ZP_HASHMAP_TEMPLATE_INDEX_TYPE b = 0; b < _ZP_HASHMAP_TEMPLATE_BUCKET_COUNT; b++) {
        _ZP_HASHMAP_TEMPLATE_INDEX_TYPE idx = map->_buckets[b];
        while (idx != _ZP_HASHMAP_TEMPLATE_INDEX_NONE) {
            _ZP_HASHMAP_TEMPLATE_NODE_TYPE *n = &map->_pool[idx];
            _ZP_HASHMAP_TEMPLATE_KEY_DESTROY_FN_NAME(&n->key);
            _ZP_HASHMAP_TEMPLATE_VAL_DESTROY_FN_NAME(&n->val);
            idx = map->_next[idx];
        }
        map->_buckets[b] = _ZP_HASHMAP_TEMPLATE_INDEX_NONE;
    }
    // Rebuild the free list
    for (_ZP_HASHMAP_TEMPLATE_INDEX_TYPE i = 0; i + 1 < _ZP_HASHMAP_TEMPLATE_CAPACITY; i++) {
        map->_next[i] = (_ZP_HASHMAP_TEMPLATE_INDEX_TYPE)(i + 1);
    }
    map->_next[_ZP_HASHMAP_TEMPLATE_CAPACITY - 1] = _ZP_HASHMAP_TEMPLATE_INDEX_NONE;  // end of free list
    map->_free_head = 0;
    map->_size = 0;
}

// ── Undef all macros ──────────────────────────────────────────────────────────

#undef _ZP_HASHMAP_TEMPLATE_KEY_TYPE
#undef _ZP_HASHMAP_TEMPLATE_VAL_TYPE
#undef _ZP_HASHMAP_TEMPLATE_NAME
#undef _ZP_HASHMAP_TEMPLATE_BUCKET_COUNT
#undef _ZP_HASHMAP_TEMPLATE_CAPACITY
#undef _ZP_HASHMAP_TEMPLATE_KEY_HASH_FN_NAME
#undef _ZP_HASHMAP_TEMPLATE_KEY_EQ_FN_NAME
#undef _ZP_HASHMAP_TEMPLATE_KEY_DESTROY_FN_NAME
#undef _ZP_HASHMAP_TEMPLATE_VAL_DESTROY_FN_NAME
#undef _ZP_HASHMAP_TEMPLATE_KEY_MOVE_FN_NAME
#undef _ZP_HASHMAP_TEMPLATE_VAL_MOVE_FN_NAME
#undef _ZP_HASHMAP_TEMPLATE_TYPE
#undef _ZP_HASHMAP_TEMPLATE_NODE_TYPE
#undef _ZP_HASHMAP_TEMPLATE_INDEX_TYPE
#undef _ZP_HASHMAP_TEMPLATE_INDEX_NONE
#undef _ZP_HASHMAP_TEMPLATE_INDEX_TYPEDEF
