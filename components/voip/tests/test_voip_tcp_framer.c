/* RFC 4571 定界的收端重组测试。纯逻辑、无平台依赖，gcc 直接编：
 *     gcc -o /tmp/t tests/test_voip_tcp_framer.c && /tmp/t
 */
#include <assert.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>

#include "../include/luat_voip_tcp_framer.h"

#define CAP VOIP_TCP_FRAME_MAX
#define OVERSIZE 2048           /* 一定要大于 CAP，否则不算超长 */

struct collect {
    uint8_t  buf[8][CAP];
    uint16_t len[8];
    int      count;
};

static void on_frame(void *user, const uint8_t *data, uint16_t len)
{
    struct collect *c = (struct collect *)user;
    assert(c->count < 8);
    memcpy(c->buf[c->count], data, len);
    c->len[c->count] = len;
    c->count++;
}

static struct collect c;
static voip_tcp_framer_t f;
static uint8_t frame[CAP];
static uint32_t dropped;
static uint8_t w[OVERSIZE + 16];

static void reset(void)
{
    voip_tcp_framer_reset(&f);
    memset(&c, 0, sizeof(c));
    dropped = 0;
}

/* 组一块 [前缀][载荷] 的线上字节 */
static uint16_t wire(uint8_t *out, const uint8_t *payload, uint16_t len)
{
    voip_tcp_prefix_write(out, len);
    if (len) memcpy(out + 2, payload, len);
    return (uint16_t)(len + 2);
}

static int feed(const uint8_t *p, uint16_t n)
{
    return voip_tcp_framer_feed(&f, p, n, frame, CAP, on_frame, &c, &dropped);
}

int main(void)
{
    uint8_t a[4] = {1, 2, 3, 4};
    uint8_t b[3] = {9, 8, 7};
    uint16_t wn;

    /* 一帧就是一块 */
    reset();
    wn = wire(w, a, sizeof(a));
    assert(feed(w, wn) == 1 && c.count == 1);
    assert(c.len[0] == sizeof(a) && memcmp(c.buf[0], a, sizeof(a)) == 0);
    assert(dropped == 0);

    /* 逐字节喂：长度前缀本身也会被劈开 */
    reset();
    wn = wire(w, a, sizeof(a));
    for (uint16_t i = 0; i < wn; i++) assert(feed(w + i, 1) == (i + 1 == wn));
    assert(c.count == 1 && c.len[0] == sizeof(a));

    /* 一块里塞两帧 */
    reset();
    wn = wire(w, a, sizeof(a));
    wn += wire(w + wn, b, sizeof(b));
    assert(feed(w, wn) == 2 && c.count == 2);
    assert(c.len[0] == sizeof(a) && c.len[1] == sizeof(b));
    assert(memcmp(c.buf[1], b, sizeof(b)) == 0);

    /* 帧尾和下一帧头落在同一个块里 */
    reset();
    wn = wire(w, a, sizeof(a));
    wn += wire(w + wn, b, sizeof(b));
    assert(feed(w, 3) == 0);                    /* 长度 + 第一个载荷字节 */
    assert(feed(w + 3, (uint16_t)(wn - 3)) == 2 && c.count == 2);

    /* 空帧：没有内容，不回调 */
    reset();
    wn = wire(w, NULL, 0);
    wn += wire(w + wn, a, sizeof(a));
    assert(feed(w, wn) == 1 && c.count == 1 && c.len[0] == sizeof(a));

    /* 超长帧按前缀整帧跳过 —— 关键是**后面那帧不能被带错位** */
    reset();
    voip_tcp_prefix_write(w, OVERSIZE);
    memset(w + 2, 0xEE, OVERSIZE);
    wn = (uint16_t)(OVERSIZE + 2);
    wn += wire(w + wn, a, sizeof(a));
    assert(feed(w, wn) == 1 && c.count == 1 && dropped == 1);
    assert(c.len[0] == sizeof(a) && memcmp(c.buf[0], a, sizeof(a)) == 0);

    /* 超长帧跨块丢弃 */
    reset();
    voip_tcp_prefix_write(w, OVERSIZE);
    assert(feed(w, 2) == 0);                    /* 只来一个长度 */
    assert(feed(w + 2, OVERSIZE) == 0);
    wn = wire(w, a, sizeof(a));
    assert(feed(w, wn) == 1 && dropped == 1 && c.len[0] == sizeof(a));

    /* reset 丢掉半帧状态：下一条链路不该继承上一条的半帧 */
    reset();
    wn = wire(w, a, sizeof(a));
    assert(feed(w, wn) == 1);
    voip_tcp_prefix_write(w, 20);
    assert(feed(w, 2) == 0 && f.frame_need == 20);
    voip_tcp_framer_reset(&f);
    assert(f.frame_need == 0 && f.len_have == 0 && f.skip_need == 0);
    wn = wire(w, b, sizeof(b));
    assert(feed(w, wn) == 1);
    assert(c.count == 2 && c.len[1] == sizeof(b));

    printf("test_voip_tcp_framer: OK\n");
    return 0;
}
