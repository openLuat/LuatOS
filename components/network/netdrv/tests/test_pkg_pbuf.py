"""Run real pkg/capture code and extracted CH390 routing/event code with C stubs."""
from pathlib import Path
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parent
NET = Path(__file__).resolve().parents[1]
HEADERS = {
    'luat_netdrv_pkg.h': (NET / 'include/luat_netdrv_pkg.h').read_text(encoding='utf-8'),
    'luat_netdrv_capture.h': (NET / 'include/luat_netdrv_capture.h').read_text(encoding='utf-8'),
    'luat_base.h': '#include <stdint.h>\n#include <stddef.h>\n#include <string.h>\n',
    'luat_mem.h': 'void *luat_heap_malloc(size_t);\nvoid luat_heap_free(void *);\n',
    'luat_mcu.h': '#include <stdint.h>\nuint64_t luat_mcu_tick64_ms(void);\n',
    'luat_log.h': '#define LLOGW(...) ((void)0)\n#define LUAT_LOG_INFO 1\nvoid luat_log_log(int, const char *, const char *, ...);\n',
    'lwip/err.h': '''#pragma once
typedef int err_t;
#define ERR_MEM (-1)
#define ERR_BUF (-2)
#define ERR_IF (-12)
#define ERR_ARG (-16)
''',
    'lwip/pbuf.h': '''#pragma once
#include <stdint.h>
struct pbuf { struct pbuf *next; void *payload; uint16_t len, tot_len, ref; };
uint16_t pbuf_copy_partial(const struct pbuf *, void *, uint16_t, uint16_t);
''',
    'luat_netdrv.h': '''#pragma once
#include "lwip/err.h"
#include "lwip/pbuf.h"
#define __NETDRV_CODE_IN_RAM__
#define NW_ADAPTER_INDEX_LWIP_NETIF_QTY 17
#define NW_ADAPTER_INDEX_LWIP_NONE 0
#define NW_ADAPTER_QTY 17
#define NETIF_FLAG_ETHARP 2
#define NETIF_FLAG_ETHERNET 4
struct netif;
typedef err_t (*netif_linkoutput_fn)(struct netif *, struct pbuf *);
struct netif { unsigned flags; netif_linkoutput_fn linkoutput; };
struct luat_netdrv;
typedef void (*luat_netdrv_dataout_cb)(struct luat_netdrv *, void *, uint8_t *, uint16_t);
typedef struct luat_netdrv { int id; struct netif *netif; luat_netdrv_dataout_cb dataout; void *userdata; } luat_netdrv_t;
luat_netdrv_t *luat_netdrv_get(int);
''',
    'luat_netdrv_event.h': '''#pragma once
#include "lwip/pbuf.h"
#define LUAT_NETDRV_CH_HW 0x10
#define LUAT_NETDRV_CH_LWIP 0x20
#define LUAT_NETDRV_CH_NAPT 0x30
typedef struct { uint8_t id, event; uint8_t *buff; uint16_t len; } luat_netdrv_pkg_evt_t;
typedef void (*luat_netdrv_pkg_evt_cb)(luat_netdrv_pkg_evt_t *, void *);
typedef struct { uint8_t id, pkg_layers; luat_netdrv_pkg_evt_cb cb; void *pkg_userdata; } netdrv_pkg_evt_reg_t;
int luat_netdrv_has_pkg_cb(uint8_t);
int luat_netdrv_has_pkg_cb_on(uint8_t, uint8_t);
void luat_netdrv_fire_pkg_event(uint8_t, uint8_t, uint8_t *, uint16_t);
''',
    'luat_netdrv_napt.h': '#include "luat_netdrv_pkg.h"\nint luat_netdrv_napt_pkg_input(int, uint8_t *, size_t);\nint luat_netdrv_napt_get_gw_adapter(void);\n',
}
PRELUDE = r'''
#include <assert.h>
#include <stdlib.h>
#include <stdio.h>
#include <string.h>
#include "luat_netdrv.h"
#include "luat_netdrv_pkg.h"
#include "luat_netdrv_capture.h"
static netdrv_pkg_evt_reg_t s_pkg_evt_regs[NW_ADAPTER_QTY];
static struct netif eth = {NETIF_FLAG_ETHARP, NULL}, wifi = {NETIF_FLAG_ETHARP, NULL}, raw = {0, NULL};
static luat_netdrv_t drv = {4, &eth, NULL, NULL}, native = {2, &wifi, NULL, NULL}, rawdrv = {5, &raw, NULL, NULL};
static unsigned full_copies, allocations, frees, outstanding, records, event_calls, napt_calls, queued, native_calls;
static int gateway = -1, fail_size, short_copy, reject_capture, napt_consume;
static uint8_t last_record[1520];
static size_t last_length, expected_length;
static const uint8_t *expected_data;
static uint8_t expected_layer;
luat_netdrv_t *luat_netdrv_get(int id) { return id == 4 ? &drv : id == 2 ? &native : id == 5 ? &rawdrv : NULL; }
void luat_log_log(int level, const char *tag, const char *fmt, ...) { (void)level; (void)tag; (void)fmt; }
uint64_t luat_mcu_tick64_ms(void) { return 1234; }
void *luat_heap_malloc(size_t n) {
    if (fail_size && n == (size_t)fail_size) return NULL;
    void *p = malloc(n); assert(p); ++allocations; ++outstanding; return p;
}
void luat_heap_free(void *p) { assert(p && outstanding); --outstanding; ++frees; free(p); }
uint16_t pbuf_copy_partial(const struct pbuf *p, void *out, uint16_t count, uint16_t offset) {
    if (count == p->tot_len && offset == 0) {
        ++full_copies;
        if (short_copy) return 0;
    }
    unsigned copied = 0;
    while (p && offset >= p->len) { offset -= p->len; p = p->next; }
    while (p && copied < count) {
        unsigned n = p->len - offset;
        if (n > count - copied) n = count - copied;
        memcpy((uint8_t *)out + copied, (uint8_t *)p->payload + offset, n);
        copied += n; offset = 0; p = p->next;
    }
    return copied;
}
int luat_netdrv_capture_log_write(const uint8_t *p, size_t len) {
    if (reject_capture) return -1;
    assert(len <= sizeof(last_record)); ++records; last_length = len; memcpy(last_record, p, len); return 0;
}
int luat_netdrv_napt_get_gw_adapter(void) { return gateway; }
int luat_netdrv_napt_pkg_input(int id, uint8_t *buff, size_t len) {
    assert(id == 4 || id == 2); ++napt_calls;
    if (gateway < 0) return 0;
    assert(len == expected_length);
    if (napt_consume) buff[44] ^= 1;
    return napt_consume;
}
static void observe(luat_netdrv_pkg_evt_t *evt, void *userdata) {
    (void)userdata; ++event_calls;
    assert(evt->event == expected_layer && evt->len == expected_length);
    assert(memcmp(evt->buff, expected_data, expected_length) == 0);
}
static void reset(void) {
    assert(outstanding == 0 && allocations == frees);
    full_copies = records = event_calls = napt_calls = queued = native_calls = 0;
    allocations = frees = 0; fail_size = short_copy = reject_capture = napt_consume = 0;
    gateway = -1; memset(s_pkg_evt_regs, 0, sizeof(s_pkg_evt_regs));
}
static void subscription(uint8_t layer) { s_pkg_evt_regs[4].cb = observe; s_pkg_evt_regs[4].pkg_layers = layer; expected_layer = layer; }
static void expect_records(unsigned n, int tx) {
#ifdef LUAT_USE_NETDRV_IP_CAPTURE
    assert(records == n);
    if (n) assert(last_record[2] == tx && last_length >= 20);
#else
    (void)n; (void)tx; assert(records == 0);
#endif
}
#define CH390H_STATUS_STOPPED 4
#define MAX_CH390H_NUM 2
typedef struct { int status, pkg_mem_type; luat_netdrv_t *netdrv; } ch390h_t;
typedef struct { uint16_t len; uint8_t buff[1600]; } luat_ch390h_cstring_t;
static ch390h_t ch = {0, 0, &drv};
static ch390h_t *ch390h_drvs[MAX_CH390H_NUM] = {&ch, NULL};
static luat_ch390h_cstring_t *new_cstring(ch390h_t *c, uint16_t len) {
    assert(c == &ch && len <= 1600); return calloc(1, sizeof(luat_ch390h_cstring_t));
}
static void send_msg_cs(ch390h_t *c, luat_ch390h_cstring_t *cs) {
    assert(c == &ch && cs->len == expected_length && memcmp(cs->buff, expected_data, expected_length) == 0);
    ++queued; free(cs);
}
static void luat_heap_opt_free(int type, void *p) { (void)type; free(p); }
'''
TEST = r'''
static err_t native_send(struct netif *n, struct pbuf *p) { assert(n == &wifi && p); ++native_calls; return -7; }
static void native_raw_send(luat_netdrv_t *d, void *u, uint8_t *buff, uint16_t len) {
    (void)u; assert(d == &native);
    struct pbuf p = {NULL, buff, len, len, 1};
    assert(d->netif->linkoutput(d->netif, &p) == -7 && p.ref == 1);
}
static err_t generic_send(void *u, struct pbuf *p) { assert(u == &rawdrv && p); return -9; }
int main(void) {
    uint8_t frame[114] = {0}; frame[12] = 8; frame[14] = 0x45; frame[17] = 100;
    struct pbuf tail = {NULL, frame + 17, 97, 97, 1};
    struct pbuf head = {&tail, frame, 17, 114, 1};
    struct pbuf flat = {NULL, frame, 114, 114, 1};
    expected_data = frame; expected_length = sizeof(frame); drv.dataout = ch390h_dataout; drv.userdata = &ch;
#ifdef LUAT_USE_NETDRV_IP_CAPTURE
    assert(luat_netdrv_capture_config(4, 64) == 0);
    assert(luat_netdrv_capture_config(2, 64) == 0);
    assert(luat_netdrv_capture_config(5, 64) == 0);
#endif
    assert(ch390_netif_output(&eth, &head) == 0 && queued == 1 && full_copies == 1);
    expect_records(1, 1); assert(head.ref == 1 && tail.ref == 1 && head.next == &tail && head.payload == frame); reset();
    assert(luat_netdrv_pkg_output(4, LUAT_NETDRV_CH_HW, frame, sizeof(frame)) == 0);
    assert(queued == 1 && full_copies == 1); expect_records(1, 1); reset();
    subscription(LUAT_NETDRV_CH_HW);
    assert(ch390_netif_output(&eth, &head) == 0 && queued == 1 && event_calls == 0 && full_copies == 1);
    expect_records(1, 1); reset();
    subscription(LUAT_NETDRV_CH_LWIP);
    assert(ch390_netif_output(&eth, &head) == 0 && event_calls == 1 && queued == 0 && full_copies == 1);
    expect_records(0, 0); reset();
    subscription(LUAT_NETDRV_CH_LWIP);
    assert(ch390_netif_output(&eth, &flat) == 0 && event_calls == 1 && allocations == 0 && queued == 0); reset();
    subscription(LUAT_NETDRV_CH_LWIP); fail_size = 114;
    assert(ch390_netif_output(&eth, &head) == ERR_MEM && event_calls == 0 && queued == 0); reset();
    subscription(LUAT_NETDRV_CH_LWIP); short_copy = 1;
    assert(ch390_netif_output(&eth, &head) == ERR_BUF && event_calls == 0 && queued == 0); reset();
    subscription(LUAT_NETDRV_CH_HW);
    assert(luat_netdrv_pkg_input(4, LUAT_NETDRV_CH_HW, frame, sizeof(frame)) == 0);
    assert(event_calls == 1 && napt_calls == 1); expect_records(1, 0); reset();
    subscription(LUAT_NETDRV_CH_HW); gateway = 4; napt_consume = 1;
    assert(luat_netdrv_pkg_input_pbuf(4, LUAT_NETDRV_CH_HW, &head) == 1);
    assert(event_calls == 1 && napt_calls == 1 && frame[44] == 0 && full_copies == 1);
    expect_records(1, 0);
#ifdef LUAT_USE_NETDRV_IP_CAPTURE
    assert(memcmp(last_record + 20, frame + 14, 64) == 0);
#endif
    reset(); assert(luat_netdrv_pkg_input_pbuf(4, LUAT_NETDRV_CH_HW, &head) == 0 && full_copies == 0);
    expect_records(1, 0); reset();
    subscription(LUAT_NETDRV_CH_HW); gateway = 4; fail_size = 114;
    assert(luat_netdrv_pkg_input_pbuf(4, LUAT_NETDRV_CH_HW, &head) == 0 && event_calls == 0 && napt_calls == 0); reset();
    uint8_t vlan[1522] = {0}; vlan[12] = 0x88; vlan[13] = 0xa8; vlan[16] = 0x81; vlan[20] = 8;
    vlan[22] = 0x45; vlan[24] = 5; vlan[25] = 0xdc;
    struct pbuf vlan_tail = {NULL, vlan + 15, 1507, 1507, 1};
    struct pbuf vlan_head = {&vlan_tail, vlan, 15, 1522, 1};
    expected_data = vlan; expected_length = sizeof(vlan); subscription(LUAT_NETDRV_CH_HW); gateway = 4;
    assert(luat_netdrv_pkg_input_pbuf(4, LUAT_NETDRV_CH_HW, &vlan_head) == 0);
    assert(event_calls == 1 && napt_calls == 0 && full_copies == 1); expect_records(1, 0); reset();
    expected_data = frame; expected_length = sizeof(frame); wifi.linkoutput = native_send;
    assert(luat_netdrv_pkg_attach_native(2) == 0 && luat_netdrv_pkg_attach_native(2) == 0);
    assert(wifi.linkoutput(&wifi, &head) == -7 && native_calls == 1); expect_records(1, 1); reset();
    native.dataout = native_raw_send;
    assert(luat_netdrv_pkg_output(2, LUAT_NETDRV_CH_HW, frame, sizeof(frame)) == 0 && native_calls == 1);
    expect_records(1, 1); reset();
    struct pbuf rawp = {NULL, frame + 14, 100, 100, 1};
    assert(luat_netdrv_pkg_output_pbuf(5, LUAT_NETDRV_CH_HW, &rawp, generic_send, &rawdrv) == -9);
    expect_records(1, 1); reset();
    reject_capture = 1;
    assert(ch390_netif_output(&eth, &head) == 0 && queued == 1); expect_records(0, 0); reset();
    ch.status = CH390H_STATUS_STOPPED;
    assert(ch390_netif_output(&eth, &head) == ERR_IF && queued == 0); ch.status = 0;
    assert(luat_netdrv_pkg_input_pbuf(4, 99, &head) < 0);
    assert(luat_netdrv_pkg_output_pbuf(4, LUAT_NETDRV_CH_HW, NULL, generic_send, NULL) == ERR_ARG);
    assert(luat_netdrv_pkg_attach_native(99) == -1 && luat_netdrv_pkg_attach_native(1) == -1);
    struct pbuf empty = {0};
    assert(luat_netdrv_napt_pkg_input_pbuf(4, &empty) == 0);
    assert(luat_netdrv_napt_pkg_input_pbuf(-1, &head) == 0);
    assert(luat_netdrv_napt_pkg_input_pbuf(260, &head) == 0);
    assert(head.ref == 1 && tail.ref == 1 && head.next == &tail && outstanding == 0);
    puts("PASS public pbuf routing: chain interception, HW-only subscription, single-copy TX, one capture/path, NAPT, VLAN, native, errors and ownership");
}
'''

event = (NET / 'src/luat_netdrv_event.c').read_text(encoding='utf-8')
event = event[event.index('int luat_netdrv_has_pkg_cb('):]
ch390 = (NET / 'src/luat_netdrv_ch390h_task.c').read_text(encoding='utf-8')
ch390 = ch390[ch390.index('static err_t ch390h_send_pbuf('):ch390.index('static int check_vid_pid(')]
napt = (NET / 'src/luat_netdrv_napt.c').read_text(encoding='utf-8')
napt = napt[napt.index('int luat_netdrv_napt_pkg_input_pbuf('):napt.index('void luat_netdrv_napt_enable(')]
with tempfile.TemporaryDirectory(dir=ROOT) as temp:
    path = Path(temp)
    for name, content in HEADERS.items():
        file = path / name
        file.parent.mkdir(parents=True, exist_ok=True)
        file.write_text(content, encoding='utf-8')
    code = PRELUDE + '\n' + event + '\n#include "luat_netdrv_pkg.c"\n#include "luat_netdrv_capture.c"\n' + ch390 + napt + TEST
    (path / 'test.c').write_text(code, encoding='utf-8')
    for enabled in (True, False):
        binary = path / ('capture.exe' if enabled else 'disabled.exe')
        command = ['gcc', '-std=c11', '-Wall', '-Wextra', '-Werror', '-DLUAT_CONF_RNDIS_NAT_DBG=1']
        if enabled:
            command.append('-DLUAT_USE_NETDRV_IP_CAPTURE=1')
        subprocess.run(command + ['-I', str(path), '-I', str(NET / 'include'), '-I', str(NET / 'src'), str(path / 'test.c'), '-o', str(binary)], check=True)
        subprocess.run([str(binary)], check=True)
