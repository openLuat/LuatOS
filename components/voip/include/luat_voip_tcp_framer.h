#ifndef LUAT_VOIP_TCP_FRAMER_H
#define LUAT_VOIP_TCP_FRAMER_H

#include <stdint.h>
#include <string.h>

/* RTP over TCP 的单帧上限。音频包（PCMA 20ms）只有 172 字节，1024 是余量；
   超过它的按长度前缀跳过整帧，不按"畸形"处理 —— 平台发大包时收不到不该
   连累后面所有帧。 */
#define VOIP_TCP_FRAME_MAX 1024

/* 长度前缀的字节数（RFC 4571 规定 2 字节大端） */
#define VOIP_TCP_PREFIX_LEN 2

/*
 * RTP over TCP 的定界（RFC 4571）：[2 字节大端长度][RTP 包]。
 * TCP 是字节流，一次读到的可能是半帧、也可能是好几帧 —— 收发两端都要靠
 * 这个前缀找回包边界，规则必须一致（gb28181 的 stream 是同一套）。
 *
 * 长度前缀**必须校验**：不校验的话，一个畸形前缀就能让收端一直等到 65535
 * 字节才肯回调。
 */
typedef struct {
    uint8_t  len_bytes[2];
    uint8_t  len_have;      /* 已收到的长度字节数 */
    uint16_t frame_need;    /* 当前帧总长；0 = 正在收长度前缀 */
    uint16_t frame_have;
    uint16_t skip_need;     /* 超长帧的剩余丢弃字节数 */
} voip_tcp_framer_t;

static inline void voip_tcp_framer_reset(voip_tcp_framer_t *f)
{
    memset(f, 0, sizeof(*f));
}

/* 发端：在 RTP 包前写上长度。调用方要先在缓冲头部留出 VOIP_TCP_PREFIX_LEN 字节 */
static inline void voip_tcp_prefix_write(uint8_t *out, uint16_t frame_len)
{
    out[0] = (uint8_t)(frame_len >> 8);
    out[1] = (uint8_t)(frame_len & 0xFF);
}

/*
 * 收端：喂一块字节，每拼出一个完整帧回调一次。
 * @return 本次拼出的完整帧数；丢弃的整帧数累加在 dropped 上
 */
static inline int voip_tcp_framer_feed(voip_tcp_framer_t *f,
        const uint8_t *p, uint16_t n,
        uint8_t *frame, uint16_t frame_cap,
        void (*on_frame)(void *user, const uint8_t *data, uint16_t len),
        void *user, uint32_t *dropped)
{
    int done = 0;

    while (n > 0) {
        uint16_t take;

        if (f->skip_need > 0) {
            take = (n < f->skip_need) ? n : f->skip_need;
            p += take;
            n -= take;
            f->skip_need -= take;
            continue;
        }

        if (f->frame_need == 0) {
            take = (uint16_t)(VOIP_TCP_PREFIX_LEN - f->len_have);
            if (take > n) take = n;
            memcpy(f->len_bytes + f->len_have, p, take);
            f->len_have = (uint8_t)(f->len_have + take);
            p += take;
            n -= take;
            if (f->len_have < VOIP_TCP_PREFIX_LEN) break;   /* 长度还没收全 */
            f->frame_need = (uint16_t)(((uint16_t)f->len_bytes[0] << 8) | f->len_bytes[1]);
            f->frame_have = 0;
            f->len_have = 0;
            /* 空帧没有内容，直接跳过；超长的整帧丢掉 —— 但**要按前缀跳过它**，
               原地复位会让后面的字节被当成长度前缀，一错全错 */
            if (f->frame_need == 0) continue;
            if (f->frame_need > frame_cap) {
                f->skip_need = f->frame_need;
                f->frame_need = 0;
                if (dropped) (*dropped)++;
                continue;
            }
        }

        take = (uint16_t)(f->frame_need - f->frame_have);
        if (take > n) take = n;
        memcpy(frame + f->frame_have, p, take);
        f->frame_have = (uint16_t)(f->frame_have + take);
        p += take;
        n -= take;
        if (f->frame_have < f->frame_need) break;   /* 半帧，等下一块 */

        if (on_frame) on_frame(user, frame, f->frame_need);
        done++;
        f->frame_need = 0;
    }

    return done;
}

#endif
