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

#ifndef ZENOH_PICO_SESSION_KEYEXPR_MATCH_TEMPLATE_H
#define ZENOH_PICO_SESSION_KEYEXPR_MATCH_TEMPLATE_H
#include <stdbool.h>
#include <stddef.h>
#include <string.h>

#include "zenoh-pico/collections/cat.h"

const char _Z_VERBATIM = '@';
const char _Z_DELIMITER = '/';
const char _Z_STAR = '*';
const char _Z_DSL0 = '$';
const char _Z_DSL1 = '*';
const size_t _Z_DELIMITER_LEN = 1;
const size_t _Z_DSL_LEN = 2;
const size_t _Z_DOUBLE_STAR_LEN = 2;

typedef enum _z_chunk_match_result_t {
    _Z_CHUNK_MATCH_RESULT_NO,
    _Z_CHUNK_MATCH_RESULT_YES,
    _Z_CHUNK_MATCH_RESULT_LEFT_SUPERWILD,
    _Z_CHUNK_MATCH_RESULT_RIGHT_SUPERWILD,
} _z_chunk_match_result_t;

typedef struct _z_chunk_forward_match_data_t {
    _z_chunk_match_result_t result;
    const char *lend;  // only valid if result is _Z_CHUNK_MATCH_RESULT_YES
    const char *rend;  // only valid if result is _Z_CHUNK_MATCH_RESULT_YES
} _z_chunk_forward_match_data_t;

typedef struct _z_chunk_backward_match_data_t {
    _z_chunk_match_result_t result;
    const char *lbegin;  // only valid if result is _Z_CHUNK_MATCH_RESULT_YES
    const char *rbegin;  // only valid if result is _Z_CHUNK_MATCH_RESULT_YES
} _z_chunk_backward_match_data_t;

static inline const char *_z_chunk_end(const char *begin, const char *end) {
    const char *sep = (const char *)memchr(begin, _Z_DELIMITER, (size_t)(end - begin));
    return sep ? sep : end;
}

static inline const char *_z_chunk_begin(const char *begin, const char *end) {
    const char *last = end - 1;
    while (begin <= last && *last != _Z_DELIMITER) {
        last--;
    }
    return last + 1;
}

static inline bool _z_keyexpr_is_double_star(const char *begin, const char *end) {
    size_t len = (size_t)(end - begin);
    return len == 2 && begin[0] == _Z_STAR && begin[1] == _Z_STAR;
}

static inline bool _z_chunk_contains_stardsl(const char *begin, const char *end) {
    return memchr(begin, _Z_DSL0, (size_t)(end - begin)) != NULL;
}

static bool _z_chunk_right_contains_all_stardsl_subchunks_of_left(const char *lbegin, const char *lend,
                                                                  const char *rbegin, const char *rend) {
    // Check if right chunk contains all stardsl subchunks of left chunk
    const char *next_dsl = NULL;
    bool matched = false;
    do {
        size_t llen = (size_t)(lend - lbegin);
        next_dsl = memchr(lbegin, _Z_DSL0, llen);
        size_t clen = next_dsl ? (size_t)(next_dsl - lbegin) : llen;
        // TODO: Should we consider a more optimial substring search algorithm, like Boyer-Moore ? The simple version
        // below looks good enough if the chunks are short.
        matched = false;
        while (rbegin + clen <= rend) {
            if (memcmp(rbegin, lbegin, clen) == 0) {
                rbegin += clen;
                matched = true;
                break;
            }
            rbegin++;
        }
        lbegin += clen + _Z_DSL_LEN;  // skip the matched part and the following stardsl
    } while (matched && next_dsl != NULL);
    return matched;
}

static inline bool _z_chunk_is_stardsl(const char *begin, const char *kend) {
    return *begin == _Z_DSL0 && (begin + _Z_DSL_LEN == kend || *(begin + 2) == _Z_DELIMITER);
}

static inline bool _z_chunk_is_stardsl_backward(const char *kbegin, const char *last) {
    // does not test for **
    return *last == _Z_DSL1 && (last == kbegin + 1 || (last > kbegin + 1 && *(last - 2) == _Z_DELIMITER));
}

static inline const char *_z_keyexpr_get_next_double_star_chunk(const char *begin, const char *end) {
    while (begin + 1 < end) {
        const char *c = (const char *)memchr(begin, _Z_STAR, (size_t)(end - begin - 1));
        if (c == NULL) {
            return NULL;
        }
        if (*(c + 1) == _Z_STAR) {
            return c;
        }
        begin = c + _Z_DOUBLE_STAR_LEN;
    }
    return NULL;
}

static inline const char *_z_keyexpr_get_next_verbatim_chunk(const char *begin, const char *end) {
    return (const char *)memchr(begin, _Z_VERBATIM, (size_t)(end - begin));
}

#endif

#ifndef _ZP_KE_MATCH_TEMPLATE_INTERSECTS
#error "_ZP_KE_MATCH_TEMPLATE_INTERSECTS must be defined before including keyexpr_match_template.h"
#endif

#if _ZP_KE_MATCH_TEMPLATE_INTERSECTS == true
#define _ZP_KE_MATCH_OP intersects
#define _ZP_KE_MATCH_TYPE_INTERSECTS true
#define _ZP_KE_MATCH_TYPE_INCLUDES false
#else
#define _ZP_KE_MATCH_OP includes
#define _ZP_KE_MATCH_TYPE_INTERSECTS false
#define _ZP_KE_MATCH_TYPE_INCLUDES true
#endif

bool _ZP_CAT(_z_chunk_special, _ZP_KE_MATCH_OP)(const char *lbegin, const char *lend, const char *rbegin,
                                                const char *rend) {
    // left is a non-empty part of a chunk following a stardsl and preceeding a stardsl i.e. $*lllll$*,
    // right is chunk that does not start, nor end with a stardsl(s), but can contain stardsl in the middle,
    // original left chunk has the following form $*L1$*L2$*...$*LN$*
    // so there are only 2 cases where it can intersect with right:
    // 1. right contains a stardsl in the middle, in this case bound stardsls in left can match parts before and after
    // stardsl in the right, while right's stardsl can match the middle part of left.
    //
    // 2. every subchunk of left (L1, L2, ..., LN) is present in right in the
    // correct order (and they do not overlap).
    //
    // For includes relation, only case 2 is valid.

    return (_ZP_KE_MATCH_TYPE_INTERSECTS && _z_chunk_contains_stardsl(rbegin, rend)) ||
           _z_chunk_right_contains_all_stardsl_subchunks_of_left(lbegin, lend, rbegin, rend);
}

_z_chunk_forward_match_data_t _ZP_CAT(_z_chunk_forward_backward, _ZP_KE_MATCH_OP)(const char *lbegin, const char *lkend,
                                                                                  const char *rbegin,
                                                                                  const char *rkend) {
    // left is a part of a chunk following a stardsl. i.e $*llllll
    _z_chunk_forward_match_data_t result = {0};
    result.lend = _z_chunk_end(lbegin, lkend);
    result.rend = _z_chunk_end(rbegin, rkend);

    const char *lend = result.lend;
    const char *rend = result.rend;

    while (lend > lbegin && rend > rbegin) {
        lend--;
        rend--;
        if (_ZP_KE_MATCH_TYPE_INTERSECTS && *rend == _Z_DSL1) {
            result.result = _Z_CHUNK_MATCH_RESULT_YES;
            return result;
        } else if (*lend == _Z_DSL1) {
            result.result = _ZP_CAT(_z_chunk_special, _ZP_KE_MATCH_OP)(lbegin, lend + 1 - _Z_DSL_LEN, rbegin, rend + 1)
                                ? _Z_CHUNK_MATCH_RESULT_YES
                                : _Z_CHUNK_MATCH_RESULT_NO;
            return result;
        } else if (*lend != *rend) {
            result.result = _Z_CHUNK_MATCH_RESULT_NO;
            return result;
        }
    }
    if (lbegin == lend) {  // remainder of left is entirely matched, leading stardsl can match the rest of right
        result.result = _Z_CHUNK_MATCH_RESULT_YES;
    }
    // if rbegin == rend remainder of right is entirely matched, but there are still chars in left (which are not
    // strardsl due to canonicalization), so no match
    return result;
}

_z_chunk_forward_match_data_t _ZP_CAT(_z_chunk_forward, _ZP_KE_MATCH_OP)(const char *lbegin, const char *lkend,
                                                                         const char *rbegin, const char *rkend) {
    // left and right are guaranteed to be non-empty canonized chunks
    _z_chunk_forward_match_data_t result = {0};
    // assume canonized chunks
    bool left_is_wild = *lbegin == _Z_STAR;
    bool right_is_wild = *rbegin == _Z_STAR;

    bool left_is_superwild = left_is_wild && (lbegin + 2 <= lkend) && *(lbegin + 1) == _Z_STAR;
    bool right_is_superwild = right_is_wild && (rbegin + 2 <= rkend) && *(rbegin + 1) == _Z_STAR;

    if (left_is_superwild) {
        result.result = _Z_CHUNK_MATCH_RESULT_LEFT_SUPERWILD;
        return result;
    } else if (right_is_superwild) {
        if (_ZP_KE_MATCH_TYPE_INCLUDES) {
            return result;
        }
        result.result = _Z_CHUNK_MATCH_RESULT_RIGHT_SUPERWILD;
        return result;
    }
    bool left_is_verbatim = *lbegin == _Z_VERBATIM;
    bool right_is_verbatim = *rbegin == _Z_VERBATIM;

    if (left_is_verbatim != right_is_verbatim) {
        return result;
    } else if (left_is_wild) {
        result.result = _Z_CHUNK_MATCH_RESULT_YES;
        result.lend = lbegin + 1;
        result.rend = _z_chunk_end(rbegin, rkend);
        return result;
    } else if (right_is_wild) {
        if (_ZP_KE_MATCH_TYPE_INCLUDES) {
            return result;
        }
        result.result = _Z_CHUNK_MATCH_RESULT_YES;
        result.lend = _z_chunk_end(lbegin, lkend);
        result.rend = rbegin + 1;
        return result;
    }
    // at this stage we should only care about stardsl, as the presence of verbatim or wild is already checked.
    while (lbegin < lkend && rbegin < rkend && *lbegin != _Z_DELIMITER && *rbegin != _Z_DELIMITER) {
        if (*lbegin == _Z_DSL0) {
            return _ZP_CAT(_z_chunk_forward_backward, _ZP_KE_MATCH_OP)(lbegin + _Z_DSL_LEN, lkend, rbegin, rkend);
        } else if (_ZP_KE_MATCH_TYPE_INTERSECTS && *rbegin == _Z_DSL0) {
            _z_chunk_forward_match_data_t res =
                _ZP_CAT(_z_chunk_forward_backward, _ZP_KE_MATCH_OP)(rbegin + _Z_DSL_LEN, rkend, lbegin, lkend);
            result.lend = res.rend;
            result.rend = res.lend;
            result.result = res.result;
            return result;
        } else if (*lbegin != *rbegin) {
            return result;
        }
        lbegin++;
        rbegin++;
    }
    bool left_exhausted = lbegin == lkend || *lbegin == _Z_DELIMITER;
    bool right_exhausted = rbegin == rkend || *rbegin == _Z_DELIMITER;
    if (left_exhausted && right_exhausted) {
        result.result = _Z_CHUNK_MATCH_RESULT_YES;
        result.lend = lbegin;
        result.rend = rbegin;
    } else if (_ZP_KE_MATCH_TYPE_INTERSECTS && left_exhausted && _z_chunk_is_stardsl(rbegin, rkend)) {
        result.result = _Z_CHUNK_MATCH_RESULT_YES;
        result.lend = lbegin;
        result.rend = rbegin + _Z_DSL_LEN;
    } else if (right_exhausted && _z_chunk_is_stardsl(lbegin, lkend)) {
        result.result = _Z_CHUNK_MATCH_RESULT_YES;
        result.lend = lbegin + _Z_DSL_LEN;
        result.rend = rbegin;
    }
    return result;
}

_z_chunk_backward_match_data_t _ZP_CAT(_z_chunk_backward_forward,
                                       _ZP_KE_MATCH_OP)(const char *lkbegin, const char *lend, const char *rkbegin,
                                                        const char *rend) {
    // left is a part of a chunk preceeding a stardsl i.e lllll$*
    _z_chunk_backward_match_data_t result = {0};
    const char *lbegin = _z_chunk_begin(lkbegin, lend);
    const char *rbegin = _z_chunk_begin(rkbegin, rend);
    if ((*lbegin == _Z_VERBATIM) != (*rbegin == _Z_VERBATIM)) {  // one is verbatim, the other is not, so no match
        return result;
    }
    result.lbegin = lbegin;
    result.rbegin = rbegin;

    // chunks can not be star, nor doublestar
    while (lbegin < lend && rbegin < rend) {
        if (_ZP_KE_MATCH_TYPE_INTERSECTS && *rbegin == _Z_DSL0) {
            result.result = _Z_CHUNK_MATCH_RESULT_YES;
            return result;
        } else if (*lbegin == _Z_DSL0) {
            result.result = _ZP_CAT(_z_chunk_special, _ZP_KE_MATCH_OP)(lbegin + 2, lend, rbegin, rend)
                                ? _Z_CHUNK_MATCH_RESULT_YES
                                : _Z_CHUNK_MATCH_RESULT_NO;
            return result;
        } else if (*lbegin != *rbegin) {
            return result;
        }
        lbegin++;
        rbegin++;
    }

    if (lbegin == lend) {  // remainder of left is entirely matched, suffix stardsl can match the rest of right
        result.result = _Z_CHUNK_MATCH_RESULT_YES;
    }
    return result;
}

_z_chunk_backward_match_data_t _ZP_CAT(_z_chunk_backward, _ZP_KE_MATCH_OP)(const char *lkbegin, const char *lend,
                                                                           const char *rkbegin, const char *rend) {
    _z_chunk_backward_match_data_t result = {0};
    const char *llast = lend - 1;
    const char *rlast = rend - 1;
    // assume canonized chunks
    bool left_is_wild = *llast == _Z_STAR;
    bool right_is_wild = *rlast == _Z_STAR;

    bool left_is_superwild = left_is_wild && (lkbegin + 2 <= lend) && *(llast - 1) == _Z_STAR;
    bool right_is_superwild = right_is_wild && (rkbegin + 2 <= rend) && *(rlast - 1) == _Z_STAR;

    if (left_is_superwild) {
        result.result = _Z_CHUNK_MATCH_RESULT_LEFT_SUPERWILD;
        return result;
    } else if (right_is_superwild) {
        if (_ZP_KE_MATCH_TYPE_INCLUDES) {
            return result;
        }
        result.result = _Z_CHUNK_MATCH_RESULT_RIGHT_SUPERWILD;
        return result;
    }
    left_is_wild = left_is_wild && (lkbegin == llast || *(llast - 1) == _Z_DELIMITER);
    right_is_wild = right_is_wild && (rkbegin == rlast || *(rlast - 1) == _Z_DELIMITER);
    if (left_is_wild) {
        result.lbegin = llast;
        result.rbegin = _z_chunk_begin(rkbegin, rend);
        result.result = *result.rbegin == _Z_VERBATIM ? _Z_CHUNK_MATCH_RESULT_NO : _Z_CHUNK_MATCH_RESULT_YES;
        return result;
    } else if (right_is_wild) {
        if (_ZP_KE_MATCH_TYPE_INCLUDES) {
            return result;
        }
        result.lbegin = _z_chunk_begin(lkbegin, lend);
        result.rbegin = rlast;
        result.result = *result.lbegin == _Z_VERBATIM ? _Z_CHUNK_MATCH_RESULT_NO : _Z_CHUNK_MATCH_RESULT_YES;
        return result;
    }

    while (llast >= lkbegin && rlast >= rkbegin && *llast != _Z_DELIMITER && *rlast != _Z_DELIMITER) {
        if (*llast == _Z_DSL1) {
            return _ZP_CAT(_z_chunk_backward_forward, _ZP_KE_MATCH_OP)(lkbegin, llast + 1 - _Z_DSL_LEN, rkbegin,
                                                                       rlast + 1);
        } else if (_ZP_KE_MATCH_TYPE_INTERSECTS && *rlast == _Z_DSL1) {
            _z_chunk_backward_match_data_t res = _ZP_CAT(_z_chunk_backward_forward, _ZP_KE_MATCH_OP)(
                rkbegin, rlast + 1 - _Z_DSL_LEN, lkbegin, llast + 1);
            result.lbegin = res.rbegin;
            result.rbegin = res.lbegin;
            result.result = res.result;
            return result;
        } else if (*llast != *rlast) {
            return result;
        }
        llast--;
        rlast--;
    }
    bool left_exhausted = lkbegin == llast + 1 || *llast == _Z_DELIMITER;
    bool right_exhausted = rkbegin == rlast + 1 || *rlast == _Z_DELIMITER;
    if (left_exhausted && right_exhausted) {
        result.result = _Z_CHUNK_MATCH_RESULT_YES;
        result.lbegin = llast + 1;
        result.rbegin = rlast + 1;
    } else if (_ZP_KE_MATCH_TYPE_INTERSECTS && left_exhausted && _z_chunk_is_stardsl_backward(rkbegin, rlast)) {
        result.result = _Z_CHUNK_MATCH_RESULT_YES;
        result.lbegin = llast + 1;
        result.rbegin = rlast + 1 - _Z_DSL_LEN;
    } else if (right_exhausted && _z_chunk_is_stardsl_backward(lkbegin, llast)) {
        result.result = _Z_CHUNK_MATCH_RESULT_YES;
        result.lbegin = llast + 1 - _Z_DSL_LEN;
        result.rbegin = rlast + 1;
    }
    return result;
}

bool _ZP_CAT(_z_keyexpr_special, _ZP_KE_MATCH_OP)(const char *lbegin, const char *lend, const char *rbegin,
                                                  const char *rend) {
    // left is a non-empty part of a ke sorrounded by doublestar i.e. **/l/l/l/l**
    // right is ke that does not start, nor end with a doublestar(s), but can contain doublestar in the middle
    // none of the kes contain any verbatim chunks
    // so there are only 2 cases where left can intersect with right:
    // 1. right contains a doublestar in the middle, in this case bound doublestars in left can match parts before and
    // after doublestar in right, while right's doublestar can match the middle part of left.
    //
    // 2. every chunk of left **/L1/**/L2/**/../LN/** is matched in right
    // in the correct order and without overlap.

    // For includes relation, only case 2 is valid.
    if (_ZP_KE_MATCH_TYPE_INTERSECTS && _z_keyexpr_get_next_double_star_chunk(rbegin, rend) != NULL) {
        return true;
    }

    // right is guaranteed not to have doublestars for intersects, while for includes we do not care
    while (lbegin < lend) {
        const char *lcbegin = lbegin;
        const char *lcend = _z_keyexpr_get_next_double_star_chunk(lbegin, lend);
        lcend = lcend != NULL ? lcend - _Z_DELIMITER_LEN : lend;
        const char *rcbegin = rbegin;

        while (lcbegin < lcend) {
            if (rcbegin >= rend) {
                return false;
            }
            _z_chunk_forward_match_data_t res =
                _ZP_CAT(_z_chunk_forward, _ZP_KE_MATCH_OP)(lcbegin, lcend, rcbegin, rend);
            if (res.result == _Z_CHUNK_MATCH_RESULT_YES) {
                lcbegin = res.lend + _Z_DELIMITER_LEN;
                rcbegin = res.rend + _Z_DELIMITER_LEN;
            } else {  // the only other possible case is res.result == _Z_CHUNK_MATCH_RESULT_NO
                // reset subke matching and try to match current left subke with the next right chunk
                lcbegin = lbegin;
                rbegin = _z_chunk_end(rbegin, rend) + _Z_DELIMITER_LEN;
                rcbegin = rbegin;
            }
        }
        lbegin = lcbegin;
        rbegin = rcbegin;
    }
    return true;
}

bool _ZP_CAT(_z_keyexpr_parts, _ZP_KE_MATCH_OP)(const char *lbegin, const char *lend, const char *rbegin,
                                                const char *rend);

bool _ZP_CAT(_z_keyexpr_backward, _ZP_KE_MATCH_OP)(const char *lbegin, const char *lend, const char *rbegin,
                                                   const char *rend, bool can_have_verbatim) {
    // left is a suffix following a doublestar i.e. **/l/l/l/l
    while (lbegin < lend && rbegin < rend) {
        _z_chunk_backward_match_data_t res = _ZP_CAT(_z_chunk_backward, _ZP_KE_MATCH_OP)(lbegin, lend, rbegin, rend);
        if (res.result == _Z_CHUNK_MATCH_RESULT_NO ||
            (_ZP_KE_MATCH_TYPE_INCLUDES && res.result == _Z_CHUNK_MATCH_RESULT_RIGHT_SUPERWILD)) {
            return false;
        } else if (res.result == _Z_CHUNK_MATCH_RESULT_YES) {
            bool left_exhausted = lbegin == res.lbegin;
            bool right_exhausted = rbegin == res.rbegin;
            if (left_exhausted && right_exhausted) {
                return true;  // leading doublestar in left matches an empty string
            } else if (left_exhausted) {
                // left is exhausted, right is matched if it does not contain any verbatim chunks
                return !can_have_verbatim ||
                       _z_keyexpr_get_next_verbatim_chunk(rbegin, res.rbegin - _Z_DELIMITER_LEN) == NULL;
            } else if (right_exhausted) {
                return false;  // right is exhausted, left is not (and thus contains at least one non doublestar chunk),
                               // match is impossible
            }
            lend = res.lbegin - _Z_DELIMITER_LEN;
            rend = res.rbegin - _Z_DELIMITER_LEN;
        } else if (can_have_verbatim) {
            // Now this becomes more complicated.
            // In the absence of verbatim chunks, we could apply the same logic as for matching stardsl chunks, but not
            // here. Given that we would anyway need to scan both kes for verbatim chunks and compare them, we rather
            // fallback to splitting kes across verbatim chunks boundary and run matching on each subke.
            return _ZP_CAT(_z_keyexpr_parts, _ZP_KE_MATCH_OP)(lbegin - _Z_DOUBLE_STAR_LEN - _Z_DELIMITER_LEN, lend,
                                                              rbegin, rend);
        } else if (res.result == _Z_CHUNK_MATCH_RESULT_LEFT_SUPERWILD) {
            return _ZP_CAT(_z_keyexpr_special, _ZP_KE_MATCH_OP)(lbegin, lend - _Z_DOUBLE_STAR_LEN - _Z_DELIMITER_LEN,
                                                                rbegin, rend);
        } else if (res.result == _Z_CHUNK_MATCH_RESULT_RIGHT_SUPERWILD) {
            return true;
        }
    }
    bool left_exhausted = lbegin >= lend;
    bool right_exhausted = rbegin >= rend;
    return (left_exhausted || _z_keyexpr_is_double_star(lbegin, lend)) &&
           (right_exhausted || (_ZP_KE_MATCH_TYPE_INTERSECTS && _z_keyexpr_is_double_star(rbegin, rend)));
}

bool _ZP_CAT(_z_keyexpr_forward, _ZP_KE_MATCH_OP)(const char *lbegin, const char *lend, const char *rbegin,
                                                  const char *rend, bool can_have_verbatim) {
    while (lbegin < lend && rbegin < rend) {
        _z_chunk_forward_match_data_t res = _ZP_CAT(_z_chunk_forward, _ZP_KE_MATCH_OP)(lbegin, lend, rbegin, rend);
        if (res.result == _Z_CHUNK_MATCH_RESULT_YES) {
            lbegin = res.lend + _Z_DELIMITER_LEN;
            rbegin = res.rend + _Z_DELIMITER_LEN;
        } else if (res.result == _Z_CHUNK_MATCH_RESULT_LEFT_SUPERWILD) {
            if (lbegin + _Z_DOUBLE_STAR_LEN == lend) {  // left is exhausted
                return _z_keyexpr_get_next_verbatim_chunk(rbegin, rend) == NULL;
            }
            return _ZP_CAT(_z_keyexpr_backward, _ZP_KE_MATCH_OP)(lbegin + _Z_DOUBLE_STAR_LEN + _Z_DELIMITER_LEN, lend,
                                                                 rbegin, rend, can_have_verbatim);
        } else if (_ZP_KE_MATCH_TYPE_INTERSECTS && res.result == _Z_CHUNK_MATCH_RESULT_RIGHT_SUPERWILD) {
            if (rbegin + _Z_DOUBLE_STAR_LEN == rend) {  // right is exhausted
                return _z_keyexpr_get_next_verbatim_chunk(lbegin, lend) == NULL;
            }
            return _ZP_CAT(_z_keyexpr_backward, _ZP_KE_MATCH_OP)(rbegin + _Z_DOUBLE_STAR_LEN + _Z_DELIMITER_LEN, rend,
                                                                 lbegin, lend, can_have_verbatim);
        } else {
            return false;
        }
    }

    bool left_exhausted = lbegin >= lend;
    bool right_exhausted = rbegin >= rend;
    return (left_exhausted || _z_keyexpr_is_double_star(lbegin, lend)) &&
           (right_exhausted || (_ZP_KE_MATCH_TYPE_INTERSECTS && _z_keyexpr_is_double_star(rbegin, rend)));
}

bool _ZP_CAT(_z_keyexpr_parts, _ZP_KE_MATCH_OP)(const char *lbegin, const char *lend, const char *rbegin,
                                                const char *rend) {
    while (lbegin < lend && rbegin < rend) {
        const char *lverbatim = _z_keyexpr_get_next_verbatim_chunk(lbegin, lend);
        const char *rverbatim = _z_keyexpr_get_next_verbatim_chunk(rbegin, rend);
        if (lverbatim == NULL && rverbatim == NULL) {
            return _ZP_CAT(_z_keyexpr_forward, _ZP_KE_MATCH_OP)(lbegin, lend, rbegin, rend, false);
        } else if (lverbatim == NULL || rverbatim == NULL) {  // different number of verbatim chunks, kes can not match
            return false;
        }

        const char *lskend = lverbatim == lbegin ? lbegin : lverbatim - _Z_DELIMITER_LEN;
        const char *rskend = rverbatim == rbegin ? rbegin : rverbatim - _Z_DELIMITER_LEN;
        if (!_ZP_CAT(_z_keyexpr_forward, _ZP_KE_MATCH_OP)(lbegin, lskend, rbegin, rskend, false)) {
            return false;  // prefixes before verbatim chunks do not match, so kes can not match
        }

        _z_chunk_forward_match_data_t res =
            _ZP_CAT(_z_chunk_forward, _ZP_KE_MATCH_OP)(lverbatim, lend, rverbatim, rend);
        if (res.result != _Z_CHUNK_MATCH_RESULT_YES) {
            return false;  // verbatim chunks do not match, so kes can not match
        }
        lbegin = res.lend + _Z_DELIMITER_LEN;
        rbegin = res.rend + _Z_DELIMITER_LEN;
    }
    bool left_exhausted = lbegin >= lend;
    bool right_exhausted = rbegin >= rend;
    return (left_exhausted || _z_keyexpr_is_double_star(lbegin, lend)) &&
           (right_exhausted || (_ZP_KE_MATCH_TYPE_INTERSECTS && _z_keyexpr_is_double_star(rbegin, rend)));
}

#undef _ZP_KE_MATCH_OP
#undef _ZP_KE_MATCH_TYPE_INTERSECTS
#undef _ZP_KE_MATCH_TYPE_INCLUDES
#undef _ZP_KE_MATCH_TEMPLATE_INTERSECTS
