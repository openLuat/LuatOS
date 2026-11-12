/* AI-MANAGED: true */
/* SPDX-License-Identifier: MIT */
/* 直接调用固定SDK，逐处分配失败后核错误、所有权和真实堆余额。 */
#include "zenoh-pico.h"
#include "zenoh-pico/protocol/iobuf.h"
#include "zenoh-pico/net/query.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
extern void host_fail_after(long n);
extern long host_allocations(void);
extern size_t host_allocation_bytes(void);
void luat_zp_test_before_dispatch(const char *kind) { (void)kind; }
void luat_zp_test_dispatch(const char *kind) { (void)kind; }
static int check(int ok, const char *what) { if (!ok) fprintf(stderr, "FAIL %s\n", what); return !ok; }
static unsigned owned_drops;
static void owned_drop(void *data, void *context) { (void)context; ++owned_drops; z_free(data); }
static int make_owned(z_owned_bytes_t *out, size_t length) {
    uint8_t *data = z_malloc(length); if (!data) return -1;
    memset(data, 0xa5, length); return z_bytes_from_buf(out, data, length, owned_drop, NULL);
}
int main(int argc, char **argv) {
    if (argc != 2) return 2;
    long base = host_allocations(); size_t bytes = host_allocation_bytes();
    int failed = 0;
    if (!strcmp(argv[1], "make")) {
        host_fail_after(1);
        _z_zbuf_t b = _z_zbuf_make(4096);
        failed |= check(_z_zbuf_capacity(&b) == 0 && !b._ios._buf, "failed zbuf must be empty");
        _z_zbuf_clear(&b);
    } else if (!strcmp(argv[1], "move")) {
        _z_wbuf_t w = _z_wbuf_make(4096, false); _z_wbuf_write(&w, 7);
        host_fail_after(0);
        _z_zbuf_t b = _z_wbuf_moved_as_zbuf(&w);
        failed |= check(_z_zbuf_capacity(&b) == 0, "failed moved zbuf must be empty");
        _z_zbuf_clear(&b); _z_wbuf_clear(&w);
    } else if (!strcmp(argv[1], "expand") || !strcmp(argv[1], "expand_bytes")) {
        _z_wbuf_t w = _z_wbuf_make(1, true); _z_wbuf_write(&w, 7);
        host_fail_after(0); uint8_t data[2] = {8,9};
        int rc = !strcmp(argv[1], "expand") ? _z_wbuf_write(&w, 8) : _z_wbuf_write_bytes(&w, data, 0, 2);
        failed |= check(rc == _Z_ERR_SYSTEM_OUT_OF_MEMORY, "failed expansion must report OOM");
        _z_wbuf_clear(&w);
    } else if (!strcmp(argv[1], "copy")) {
        _z_wbuf_t w = _z_wbuf_make(4, false); _z_wbuf_write(&w, 7);
        host_fail_after(0); _z_zbuf_t b = _z_wbuf_to_zbuf(&w);
        failed |= check(_z_zbuf_capacity(&b) == 0, "failed copied zbuf must be empty");
        _z_zbuf_clear(&b); _z_wbuf_clear(&w);
    } else if (!strcmp(argv[1], "bytes") || !strcmp(argv[1], "internal_bytes")) {
        for (int i=0; i<3; ++i) {
            uint8_t data[4] = {0,1,2,3};
            host_fail_after(i); int rc;
            if (!strcmp(argv[1], "bytes")) {
                z_owned_bytes_t b; z_bytes_empty(&b); rc = z_bytes_copy_from_buf(&b, data, sizeof(data)); z_drop(z_move(b));
            } else {
                _z_bytes_t b; rc = _z_bytes_from_buf(&b, data, sizeof(data)); _z_bytes_drop(&b);
            }
            host_fail_after(-1);
            failed |= check(rc != 0, "allocation failure must be returned");
            failed |= check(host_allocations()==base && host_allocation_bytes()==bytes, "bytes allocation leak");
        }
    } else if (!strcmp(argv[1], "owned_bytes")) {
        for (int at=0; at<5; ++at) {
            uint8_t *data=z_malloc(262144); memset(data,0xa5,262144); owned_drops=0;
            host_fail_after(at); z_owned_bytes_t value;
            int rc=z_bytes_from_buf(&value,data,262144,owned_drop,NULL); host_fail_after(-1);
            if (!rc) {
                z_owned_bytes_t clone; failed |= check(!z_bytes_clone(&clone,z_loan(value)),"clone owned bytes");
                z_drop(z_move(value)); failed |= check(owned_drops==0,"owner freed before clone");
                z_drop(z_move(clone));
            } else z_drop(z_move(value));
            failed |= check(owned_drops==1,"owned bytes must free exactly once");
            failed |= check(host_allocations()==base && host_allocation_bytes()==bytes,"owned bytes leaked");
        }
    } else if (!strcmp(argv[1], "reply_closed")) {
        for (int kind=0;kind<3;++kind) for (int with_options=0;with_options<2;++with_options) {
            z_owned_query_t query; query._rc=_z_query_rc_new_undefined();
            failed |= check(query._rc._val != NULL,"query allocation");
            *query._rc._val=_z_query_null();
            z_view_keyexpr_t key; z_view_keyexpr_from_str(&key,"test/closed");
            z_owned_bytes_t payload,attachment;z_bytes_empty(&payload);z_bytes_empty(&attachment);
            z_owned_encoding_t encoding;z_encoding_from_str(&encoding,"application/test;synthetic");
            owned_drops=0;unsigned expected=0;
            if(kind!=1){failed |= check(!make_owned(&payload,262144),"owned payload");++expected;}
            if(with_options && kind!=2){failed |= check(!make_owned(&attachment,7),"owned attachment");++expected;}
            int rc;
            if(kind==0){z_query_reply_options_t opts;z_query_reply_options_default(&opts);
                opts.encoding=z_move(encoding);opts.attachment=z_move(attachment);
                rc=z_query_reply(z_loan(query),z_loan(key),z_move(payload),with_options?&opts:NULL);
            }else if(kind==1){z_query_reply_del_options_t opts;z_query_reply_del_options_default(&opts);
                opts.attachment=z_move(attachment);
                rc=z_query_reply_del(z_loan(query),z_loan(key),with_options?&opts:NULL);
            }else{z_query_reply_err_options_t opts;z_query_reply_err_options_default(&opts);opts.encoding=z_move(encoding);
                rc=z_query_reply_err(z_loan(query),z_move(payload),with_options?&opts:NULL);}
            failed |= check(rc==_Z_ERR_SESSION_CLOSED && owned_drops==expected,"closed reply must consume moved values");
            z_drop(z_move(encoding));z_drop(z_move(attachment));z_drop(z_move(payload));z_drop(z_move(query));
            failed |= check(host_allocations()==base && host_allocation_bytes()==bytes,"closed reply leak");
        }
    } else return 2;
    host_fail_after(-1);
    failed |= check(host_allocations()==base && host_allocation_bytes()==bytes, "SDK allocation leak");
    if (!failed) printf("SDK_MEMORY_PASS %s\n", argv[1]);
    return failed ? 1 : 0;
}
