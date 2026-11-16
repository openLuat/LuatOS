/* AI-MANAGED: true */
/* SPDX-License-Identifier: MIT */
/* 真SDK算法、消息codec、配置OOM/所有权测试；不替换被测函数。 */
#define main sdk_memory_main
#include "host_sdk_memory_test.c"
#undef main
#include "zenoh-pico/utils/auth.h"
#include "zenoh-pico/utils/config.h"
#include "zenoh-pico/protocol/codec/transport.h"
#include "zenoh-pico/protocol/codec/core.h"
#include "zenoh-pico/protocol/definitions/transport.h"
#include <stdint.h>

static int config_cases(void) {
    int failed = 0;
    long base = host_allocations(); size_t bytes = host_allocation_bytes();
    for (int replace = 0; replace < 2; ++replace) for (int at = 0; at < 9; ++at) {
        _z_config_t config; _z_config_init(&config);
        if (replace) failed |= check(!_zp_config_insert(&config, Z_CONFIG_PASSWORD_KEY, "old-test-value"), "config baseline");
        host_fail_after(at);
        int rc = _zp_config_insert(&config, Z_CONFIG_PASSWORD_KEY, "new-test-value");
        host_fail_after(-1);
        const char *got = _z_config_get(&config, Z_CONFIG_PASSWORD_KEY);
        if (rc) failed |= check(replace ? got && !strcmp(got, "old-test-value") : got == NULL, "failed replace preserved old value");
        else failed |= check(got && !strcmp(got, "new-test-value"), "successful insert owns value");
        _z_config_clear(&config);
        failed |= check(host_allocations()==base && host_allocation_bytes()==bytes, "config failure leak");
    }
    _z_config_t src; _z_config_init(&src);
    _z_string_t str = _z_string_copy_from_str("owned-string-input");
    failed |= check(!_zp_config_insert_string(&src, Z_CONFIG_MODE_KEY, &str), "config insert string");
    _z_string_clear(&str);
    failed |= check(!strcmp(_z_config_get(&src, Z_CONFIG_MODE_KEY), "owned-string-input"), "insert string lifetime");
    failed |= check(!_zp_config_insert(&src, Z_CONFIG_PASSWORD_KEY, "synthetic-password"), "password config");
    for (int at = 0; at < 12; ++at) {
        _z_config_t dst; host_fail_after(at); int rc = _z_config_duplicate(&dst, &src); host_fail_after(-1);
        if (!rc) failed |= check(!strcmp(_z_config_get(&dst,Z_CONFIG_PASSWORD_KEY),"synthetic-password"),"config duplicate contents");
        else failed |= check(_z_config_is_empty(&dst), "failed duplicate empty");
        _z_config_clear(&dst);
    }
    failed |= check(!_zp_config_insert(&src,Z_CONFIG_CONNECT_KEY,"tcp/first:1"),"first locator");
    failed |= check(!_zp_config_insert(&src,0x51,"collision"),"collision config");
    failed |= check(!_zp_config_insert(&src,Z_CONFIG_CONNECT_KEY,"tcp/second:2"),"second locator");
    _z_config_t copied; failed |= check(!_z_config_duplicate(&copied,&src),"duplicate locators");
    failed |= check(!strcmp(_z_config_get(&src,Z_CONFIG_CONNECT_KEY),_z_config_get(&copied,Z_CONFIG_CONNECT_KEY)),"clone locator order");
    for(int at=0;at<12;++at){
        _z_string_svec_t locators=_z_string_svec_make(0);host_fail_after(at);
        int rc=_z_config_get_all(&copied,&locators,Z_CONFIG_CONNECT_KEY);host_fail_after(-1);
        if(!rc){failed |= check(_z_string_svec_len(&locators)==2,"get_all collision filter");
            failed |= check(_z_string_len(_z_string_svec_get(&locators,0))==12 && !memcmp(_z_string_data(_z_string_svec_get(&locators,0)),"tcp/second:2",12),"get_all order");}
        _z_string_svec_clear(&locators);
    }
    _z_string_t invalid=_z_string_alias_substr("x\0tail",6);
    failed |= check(_zp_config_insert_string(&src,Z_CONFIG_USER_KEY,&invalid)==_Z_ERR_AUTH_CONFIG,"embedded NUL credential");
    _z_config_clear(&copied);
    _z_config_clear(&src);
    return failed | check(host_allocations()==base && host_allocation_bytes()==bytes,"config final leak");
}
static int codec_cases(void) {
    int failed = 0;
    long base = host_allocations(); size_t bytes = host_allocation_bytes();
    for (int phase=0;phase<4;++phase) for (int boundary=0;boundary<2;++boundary) {
        _z_id_t id = _z_id_empty(); id.id[0]=1;
        _z_transport_message_t msg = phase==0 ? _z_t_msg_make_init_syn(Z_WHATAMI_CLIENT,id) :
            phase==1 ? _z_t_msg_make_init_ack(Z_WHATAMI_ROUTER,id,_z_slice_null()) :
            phase==2 ? _z_t_msg_make_open_syn(10000,31,_z_slice_null()) : _z_t_msg_make_open_ack(10000,31);
        _Z_SET_FLAG(msg._header,_Z_FLAG_T_Z);
        if (phase<2) { msg._body._init._auth_present=true; msg._body._init._auth_nonce=boundary ? UINT64_MAX : 0; }
        else { msg._body._open._auth_present=true; msg._body._open._auth_user_len=boundary ? 128 : 1;
            memset(msg._body._open._auth_user,'u',msg._body._open._auth_user_len);memset(msg._body._open._auth_hmac,0xa5,32); }
        _z_wbuf_t w=_z_wbuf_make(1024,false);
        failed |= check(!_z_transport_message_encode(&w,&msg),"auth encode");
        _z_zbuf_t b=_z_wbuf_to_zbuf(&w); size_t length=_z_zbuf_len(&b);
        _z_transport_message_t decoded={0};
        failed |= check(!_z_transport_message_decode(&decoded,&b) && !_z_zbuf_len(&b),"auth decode complete");
        if (phase<2) failed |= check(decoded._body._init._auth_present && (phase==0 || decoded._body._init._auth_nonce==msg._body._init._auth_nonce),"auth nonce");
        else failed |= check(decoded._body._open._auth_present && (phase==3 ||
            (decoded._body._open._auth_user_len==msg._body._open._auth_user_len && !memcmp(decoded._body._open._auth_hmac,msg._body._open._auth_hmac,32))),"auth proof");
        _z_t_msg_clear(&decoded);
        for (size_t n=0;n<length;++n) {
            _z_zbuf_set_rpos(&b,0);_z_zbuf_set_wpos(&b,n);decoded=(_z_transport_message_t){0};
            failed |= check(_z_transport_message_decode(&decoded,&b)!=0,"truncated auth accepted");
            _z_t_msg_clear(&decoded);
        }
        for (size_t capacity=1;capacity<length;++capacity) {
            _z_wbuf_t small=_z_wbuf_make(capacity,false);
            failed |= check(_z_transport_message_encode(&small,&msg)!=0,"small auth encoder buffer accepted");
            _z_wbuf_clear(&small);
        }
        _z_t_msg_clear(&msg);_z_zbuf_clear(&b);_z_wbuf_clear(&w);
        failed |= check(host_allocations()==base && host_allocation_bytes()==bytes,"auth codec leak");
    }
    _z_id_t id=_z_id_empty();id.id[0]=1;
    _z_slice_t cookie=_z_slice_copy_from_buf((const uint8_t*)"cookie",6);
    _z_transport_message_t original=_z_t_msg_make_init_ack(Z_WHATAMI_ROUTER,id,cookie), copy={0};
    host_fail_after(0);int rc=_z_t_msg_copy(&copy,&original);host_fail_after(-1);
    failed |= check(rc==_Z_ERR_SYSTEM_OUT_OF_MEMORY,"cookie copy OOM lost");
    _z_t_msg_clear(&copy);_z_t_msg_clear(&original);
    return failed | check(host_allocations()==base && host_allocation_bytes()==bytes,"cookie failure leak");
}
static int patch_cases(void) {
    int failed=0; long base=host_allocations();size_t bytes=host_allocation_bytes();
    const uint64_t values[]={0,1,2,255,256,257,UINT64_MAX};
    for(size_t i=0;i<sizeof(values)/sizeof(values[0]);++i)for(int auth_first=0;auth_first<2;++auth_first){
        _z_id_t id=_z_id_empty();id.id[0]=1;
        _z_transport_message_t msg=_z_t_msg_make_init_ack(Z_WHATAMI_ROUTER,id,_z_slice_null());
        msg._body._init._patch=0;_Z_SET_FLAG(msg._header,_Z_FLAG_T_Z);
        _z_wbuf_t w=_z_wbuf_make(128,false);
        failed |= check(!_z_transport_message_encode(&w,&msg),"patch base encode");
        if(auth_first){const uint8_t a[]={0xc3,2,0x22,0};failed |= check(!_z_wbuf_write_bytes(&w,a,0,sizeof(a)),"auth before patch");}
        failed |= check(!_z_wbuf_write(&w,auth_first?0x27:0xa7) && !_z_zint64_encode(&w,values[i]),"patch extension encode");
        if(!auth_first){const uint8_t a[]={0x43,2,0x22,0};failed |= check(!_z_wbuf_write_bytes(&w,a,0,sizeof(a)),"auth after patch");}
        _z_zbuf_t b=_z_wbuf_to_zbuf(&w);_z_transport_message_t got={0};int rc=_z_transport_message_decode(&got,&b);
        if(values[i]>UINT8_MAX)failed |= check(rc!=0,"oversize patch wrapped");
        else failed |= check(!rc && got._body._init._patch==values[i] && got._body._init._auth_present,"patch/auth decode value");
        _z_t_msg_clear(&got);_z_t_msg_clear(&msg);_z_zbuf_clear(&b);_z_wbuf_clear(&w);
    }
    return failed | check(host_allocations()==base && host_allocation_bytes()==bytes,"patch leak");
}
int main(int argc,char **argv) {
    if (argc==3 && !strcmp(argv[1],"hash")) {
        size_t len=strlen(argv[2])/2;uint8_t input[1024],digest[32];
        if (len>sizeof(input) || strlen(argv[2])%2) return 2;
        for (size_t i=0;i<len;++i) { unsigned byte;if(sscanf(argv[2]+2*i,"%2x",&byte)!=1)return 2;input[i]=(uint8_t)byte; }
        _z_usrpwd_sha3_256(digest,input,len);for(int i=0;i<32;++i)printf("%02x",digest[i]);puts("");return 0;
    }
    if (argc==4 && !strcmp(argv[1],"hmac")) {
        char *end;uint64_t nonce=strtoull(argv[2],&end,16);uint8_t digest[32];
        if (*end || _z_usrpwd_hmac(digest,nonce,argv[3]))return 2;
        for(int i=0;i<32;++i)printf("%02x",digest[i]);puts("");return 0;
    }
    if (argc!=1)return 2;
    int failed=check(!_z_usrpwd_selftest(),"SHA3 selftest");
    failed |= config_cases(); failed |= codec_cases(); failed |= patch_cases();
    _z_wbuf_t empty=_z_wbuf_null();_z_zbuf_t b=_z_wbuf_to_zbuf(&empty);
    failed |= check(!_z_zbuf_len(&b),"empty wbuf");_z_zbuf_clear(&b);_z_wbuf_clear(&empty);
    printf("AUTH_UNIT_%s\n",failed?"FAIL":"PASS");return failed?1:0;
}
