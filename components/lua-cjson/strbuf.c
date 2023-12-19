/* strbuf - String buffer routines
 *
 * Copyright (c) 2010-2012  Mark Pulford <mark@kyne.com.au>
 *
 * Permission is hereby granted, free of charge, to any person obtaining
 * a copy of this software and associated documentation files (the
 * "Software"), to deal in the Software without restriction, including
 * without limitation the rights to use, copy, modify, merge, publish,
 * distribute, sublicense, and/or sell copies of the Software, and to
 * permit persons to whom the Software is furnished to do so, subject to
 * the following conditions:
 *
 * The above copyright notice and this permission notice shall be
 * included in all copies or substantial portions of the Software.
 *
 * THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
 * EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
 * MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT.
 * IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY
 * CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT,
 * TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE
 * SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
 */

#include <stdio.h>
#include <stdlib.h>
#include <stdarg.h>
#include <string.h>
#include "strbuf.h"

#include "luat_base.h"
#include "luat_mem.h"

#define LUAT_LOG_TAG "cjson"
#include "luat_log.h"

#ifdef WIN32
#define vsnprintf _vsnprintf
#endif

#define L_MALLOC luat_heap_malloc
#define L_FREE  luat_heap_free
#define L_REALLOC  luat_heap_realloc

int strbuf_init(strbuf_t *s, int len)
{
    int size;

    if (len <= 0)
        size = STRBUF_DEFAULT_SIZE;
    else
        size = len + 1;         /* \0 terminator */

    s->buf = NULL;
    s->size = size;
    s->length = 0;
    s->increment = STRBUF_DEFAULT_INCREMENT;
    s->dynamic = 0;
    s->is_err = 0;
    // s->reallocs = 0;
    // s->debug = 0;

    s->buf = (char *)L_MALLOC(size);
    if (!s->buf)
        return -1;

    strbuf_ensure_null(s);
    return 0;
}

strbuf_t *strbuf_new(int len)
{
    strbuf_t *s;
    int ret = 0;

    s = (strbuf_t *)L_MALLOC(sizeof(strbuf_t));
    if (!s)
        return NULL;

    ret = strbuf_init(s, len);
    if (ret) {
        L_FREE(s);
        return NULL;
    }

    /* Dynamic strbuf allocation / deallocation */
    s->dynamic = 1;

    return s;
}

/* If strbuf_t has not been dynamically allocated, strbuf_free() can
 * be called any number of times strbuf_init() */
void strbuf_free(strbuf_t *s)
{
    // debug_stats(s);

    if (s->buf) {
        L_FREE (s->buf);
        s->buf = NULL;
    }
    if (s->dynamic)
        L_FREE (s);
}

static int calculate_new_size(strbuf_t *s, int len)
{
    int reqsize;

    // if (len <= 0)
    //     die("BUG: Invalid strbuf length requested");

    /* Ensure there is room for optional NULL termination */
    reqsize = len + 1;

    /* If the user has requested to shrink the buffer, do it exactly */
    if (s->size > reqsize)
        return reqsize;

    // newsize = s->size;
    if (reqsize - s->size < 1023) {
        reqsize = s->size + 1023;
    }

    return reqsize + 1;
}


/* Ensure strbuf can handle a string length bytes long (ignoring NULL
 * optional termination). */
void strbuf_resize(strbuf_t *s, int len)
{
    int newsize;
    void* ptr;

    if (s->is_err)
        return;

    newsize = calculate_new_size(s, len);

    ptr = (char *)L_REALLOC(s->buf, newsize);
    if (ptr == NULL) {
        s->is_err = 1;
    }
    else {
        s->size = newsize;
        s->buf = ptr;
    }
}

void strbuf_append_string(strbuf_t *s, const char *str)
{
    int space, i;
    if (s->is_err)
        return;

    space = strbuf_empty_length(s);

    for (i = 0; str[i]; i++) {
        if (space < 1) {
            strbuf_resize(s, s->length + 1);
            space = strbuf_empty_length(s);
        }

        s->buf[s->length] = str[i];
        s->length++;
        space--;
    }
}
