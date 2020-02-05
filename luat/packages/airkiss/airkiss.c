/*
 * Copyright (c) 2006-2018, RT-Thread Development Team
 *
 * SPDX-License-Identifier: Apache-2.0
 *
 * Change Logs:
 * Date           Author           Notes
 * 2019-05-16     heyuanjie87      first version
*/

#include "airkiss.h"

#include <string.h>
#include <stdint.h>

#ifdef AIRKISS_LOG_ENABLE
#define AKLOG_D                     \
    if (lc->cfg && lc->cfg->printf) \
    lc->cfg->printf
#else
#define AKLOG_D(...)
#endif

#define AKSTATE_WFG 0
#define AKSTATE_WFM 1
#define AKSTATE_WFP 2
#define AKSTATE_WFD 4
#define AKSTATE_CMP 5

typedef uint16_t akwire_seq_t;

typedef struct
{
    uint16_t val[6];
    uint8_t pos;
    uint8_t scnt; /* 成功计数 */
    uint8_t err;
    uint8_t rcnt; /* 接收计数 */
} akcode_t;

typedef struct
{
    akwire_seq_t ws;
    uint8_t crc;
    uint8_t ind;
}akdatf_seq_t;

typedef struct
{
    uint8_t crc;
    uint8_t ind;
}akdatf_header_t;

typedef struct
{
    uint8_t id[4];
}akaddr_t;

typedef struct
{
    akwire_seq_t ws;
    uint8_t val[4];
    uint8_t pos : 4;
    uint8_t scnt : 4;
    uint8_t err;
    uint8_t wval;
    uint8_t seqcnt;
    akaddr_t sa;
} akcode_guide_t;

typedef struct
{
    char data[16]; /* 保留后4个 */
    uint8_t pos[16];
}akdatf_conflict_t;

typedef struct
{
    union {
        akcode_guide_t code1[3];
        akcode_t code2[1];
    } uc;

    akdatf_conflict_t dcfl; /* 记录有冲突的数据 */
    akwire_seq_t prews;
    akdatf_seq_t preseq;
    akdatf_seq_t curseq;
    akdatf_header_t pendseq[10]; /* 未完成的序列 */
    akaddr_t locked;

    uint8_t seqstep;/* 序列增量 */
    uint8_t reclen;
    uint8_t state;
    uint8_t nossid;
    uint8_t seq[16]; /* 标记已完成的序列 */

    char data[66];
    uint8_t random;
    uint8_t baselen;
    uint8_t prslen;
    uint8_t ssidcrc;
    uint8_t pwdlen;
    const airkiss_config_t *cfg;
} akloc_context_t;

#define AKLOC_CODE1(x, i) ((x)->uc.code1[i])
#define AKLOC_CODE2(x) (&(x)->uc.code2[0])

#define AKLOC_DFSEQ_PREV(lc) ((lc)->preseq)
#define AKLOC_DFSEQ_CUR(lc) ((lc)->curseq)

unsigned char airkiss_crc8(unsigned char *message, unsigned char len)
{
    uint8_t crc = 0;
    uint8_t i;

    while (len--)
    {
        crc ^= *message++;
        for (i = 0; i < 8; i++)
        {
            if (crc & 0x01)
                crc = (crc >> 1) ^ 0x8c;
            else
                crc >>= 1;
        }
    }

    return crc;
}

static akwire_seq_t akwseq_make(uint8_t seq[2])
{
    akwire_seq_t ws = 0;

    ws = (seq[1] << 4) | (seq[0] >> 4);

    return ws;
}

static void akloc_reset(akloc_context_t *lc)
{
    const airkiss_config_t *cfg;

    cfg = lc->cfg;
    memset(lc, 0, sizeof(*lc));
    lc->cfg = cfg;
}

static uint8_t akinfo_getu8(uint16_t v[2])
{
    uint8_t ret = 0;

    ret = ((v[0] & 0xF) << 4) | (v[1] & 0xF);

    return ret;
}

static uint16_t aklen_udp(akloc_context_t *lc, uint16_t len)
{
    return (len - lc->baselen);
}

static int ak_get_magicfield(akloc_context_t *lc, akcode_t *ac)
{
    int ret = 1;

    if (ac->val[0] == 8)
        ac->val[0] = 0;
    lc->prslen = akinfo_getu8(&ac->val[0]);
    lc->ssidcrc = akinfo_getu8(&ac->val[2]);

    if (lc->prslen > (sizeof(lc->data) - 1))
    {
        ret = 0;
        AKLOG_D("prslen(%d) large than(%d)", lc->prslen, (sizeof(lc->data) - 1));
    }

    return ret;
}

static int ak_magicfield_input(akcode_t *ac, uint16_t len)
{
    int mc;

    mc = len >> 4;
    if (mc == 0)
    {
        ac->val[0] = len;
        ac->pos = 1;
    }
    else if (mc == ac->pos)
    {
        ac->val[ac->pos] = len;
        ac->pos ++;
    }
    else
    {
        ac->pos = 0;
    }

    return (ac->pos == 4);
}

static int ak_get_prefixfield(akloc_context_t *lc, akcode_t *ac)
{
    int ret;
    uint8_t crc;

    lc->pwdlen = akinfo_getu8(&ac->val[0]);
    crc = akinfo_getu8(&ac->val[2]);
    if (airkiss_crc8(&lc->pwdlen, 1) != crc)
        ret = 0;

    return ret;
}

static int ak_prefixfield_input(akcode_t *ac, uint16_t len)
{
    int mc;

    mc = len >> 4;
    if (mc == 4)
    {
        ac->val[0] = len;
        ac->pos = 1;
    }
    else if (mc == (ac->pos + 4))
    {
        ac->val[ac->pos] = len;
        ac->pos ++;
    }
    else
    {
        ac->pos = 0;
    }

    return (ac->pos == 4);
}

static int ak_get_datafield(akloc_context_t *lc, akcode_t *ac)
{
    uint8_t tmp[6];
    int n;
    int ret = 0;
    int pos;
    int seqi;

    seqi = ac->val[1] & 0x7f;
    if (seqi > (lc->prslen/4))
    {
        return 0;
    }

    if (lc->seq[seqi])
        return 0;

    pos = seqi * 4;
    n = lc->prslen - pos;
    if (n > 4)
        n = 4;

    tmp[0] = ac->val[0] & 0x7F;
    tmp[1] = ac->val[1] & 0x7F;
    tmp[2] = ac->val[2] & 0xFF;
    tmp[3] = ac->val[3] & 0xFF;
    tmp[4] = ac->val[4] & 0xFF;
    tmp[5] = ac->val[5] & 0xFF;

    ret = ((airkiss_crc8(&tmp[1], n + 1) & 0x7F) == tmp[0]);
    if (ret)
    {
        memcpy(&lc->data[pos], &tmp[2], n);
        lc->reclen += n;
        lc->seq[seqi] = 1;

#ifdef AIRKISS_LOG_GDO_ENABLE
        AKLOG_D("getdata(%d, %d)\n", seqi, n);
#endif
    }

    return ret;
}

static void akaddr_fromframe(akaddr_t *a, uint8_t *f)
{
    f += 10;

    a->id[0] = f[4];
    a->id[1] = f[5];
    a->id[2] = f[10];
    a->id[3] = f[11];
}

static akcode_guide_t *ak_guide_getcode(akloc_context_t *lc, unsigned char *f)
{
    akcode_guide_t *ac;

    if (f == NULL) /* 是模拟测试 */
    {
        ac = &AKLOC_CODE1(lc, 2);
    }
    else
    {
        akaddr_t sa;
        unsigned i;
        int found = 0;
        akcode_guide_t *imin;

        akaddr_fromframe(&sa, f);
        imin = &AKLOC_CODE1(lc, 0);
        ac = imin;
        for (i = 0; i < sizeof(lc->uc.code1) / sizeof(lc->uc.code1[0]); i++)
        {
            /* 匹配地址 */
            found = !memcmp(&sa, &ac->sa, sizeof(ac->sa));
            if (found)
                break;
            /* 记录权值最小的 */
            if (ac->wval < imin->wval)
                imin = ac;
            ac++;
        }

        if (!found)
        {
            /* 淘汰输入最少的 */
            ac = imin;
            ac->pos = 0;
            ac->err = 0;
            ac->scnt = 0;
            ac->wval = 0;
            ac->sa = sa;
        }
    }

    return ac;
}

static int ak_guidefield_input(akcode_guide_t *ac, uint8_t *f, uint16_t len)
{
    akwire_seq_t ws = 0;

    if (f)
        ws = akwseq_make(f + 22);

    if (ac->pos < 4)
    {
        if ((ac->pos != 0) && ((len - ac->val[ac->pos - 1]) != 1))
        {
            ac->pos = 0;
            if (ac->wval > 0)
                ac->wval--;
        }

        if (ac->pos == 0)
        {
            ac->ws = ws;
            ac->seqcnt = 0;
        }
        ac->seqcnt += (ws - ac->ws);

        ac->val[ac->pos] = len;
        ac->pos++;
        ac->wval += ac->pos;
    }

    return (ac->pos == 4);
}

static int ak_waitfor_guidefield(akloc_context_t *lc, uint8_t *f, uint16_t len)
{
    int ret = AIRKISS_STATUS_CONTINUE;
    akcode_guide_t *ac;

    ac = ak_guide_getcode(lc, f);

    if (ak_guidefield_input(ac, f, len))
    {
        ac->pos = 0;
        ac->scnt++;

        /* 至少两次相同的guide code才算获取成功 */
        if ((ac->scnt >= 2) && ac->wval >= 20)
        {
            lc->state = AKSTATE_WFM;
            lc->baselen = ac->val[0] - 1;
            lc->seqstep = ac->seqcnt/6;

            AKLOG_D("guide baselen(%d) seqstep(%d)\n", lc->baselen, lc->seqstep);
        }

        if (lc->state == AKSTATE_WFM)
        {
            lc->locked = ac->sa;
            memset(&lc->uc, 0, sizeof(lc->uc));
            ret = AIRKISS_STATUS_CHANNEL_LOCKED;
        }
    }

    return ret;
}

static int ak_waitfor_magicfield(akloc_context_t *lc, uint16_t len)
{
    int ret = AIRKISS_STATUS_CONTINUE;
    akcode_t *ac = AKLOC_CODE2(lc);
    int udplen;

    udplen = aklen_udp(lc, len);

    if (ak_magicfield_input(ac, udplen))
    {
        ac->pos = 0;

        if (ak_get_magicfield(lc, ac))
        {
            lc->state = AKSTATE_WFP;

            AKLOG_D("magic: prslen(%d) ssidcrc(%X)\n", lc->prslen, lc->ssidcrc);
        }
    }

    if (ac->rcnt++ > 250)
    {
        akloc_reset(lc);
        AKLOG_D("reset from magic\n");
    }

    return ret;
}

static int ak_waitfor_prefixfield(akloc_context_t *lc, uint16_t len)
{
    int ret = AIRKISS_STATUS_CONTINUE;
    akcode_t *ac = AKLOC_CODE2(lc);
    int udplen;

    udplen = aklen_udp(lc, len);

    if (ak_prefixfield_input(ac, udplen))
    {
        ac->pos = 0;

        if (ak_get_prefixfield(lc, ac))
        {
            lc->state = AKSTATE_WFD;

            AKLOG_D("prefix: pwdlen(%d)\n", lc->pwdlen);
        }
    }

    return ret;
}

#ifdef AIRKISS_LOG_DFDUMP_ENABLE
static void akdata_dump(akloc_context_t *lc, uint8_t *f, uint16_t len)
{
    uint8_t seq[2];
    uint16_t dseq;

    seq[0] = f[22];
    seq[1] = f[23];

    dseq = (seq[1] << 4) | (seq[0]>> 4);
    if (len & 0x100)
    {
        AKLOG_D("(%d) %X %c", dseq, len, len & 0xff);
    }
    else
    {
        AKLOG_D("(%d) %X", dseq, len);
    }
}
#endif

/*
  只判断密码和random是否收完
*/
static int ak_is_pwdrand_complete(akloc_context_t *lc)
{
    int ret = 0;
    unsigned i;
    int n = 0;

    for (i = 0; i < (sizeof(lc->seq) / sizeof(lc->seq[0])); i++)
    {
        if (lc->seq[i] == 0)
            break;

        n += 4;
        if (n >= (lc->pwdlen + 1))
        {
            ret = 1;
            break;
        }
    }

    return ret;
}

static int ak_datainput_onlylength(akloc_context_t *lc, akcode_t *ac, uint16_t len)
{
    int n = 6;

    if (len & 0x100)
    {
        if (ac->pos > 1)
        {
            int size;

            ac->val[ac->pos] = len;
            ac->pos ++;

            size = (ac->val[1] & 0x7f) * 4;
            if (size <  lc->prslen)
            {
                size = lc->prslen - size;
                if (size < 4) /* 最后一个包不足4 */
                {
                    n = size + 2;
                }
            }
        }
        else
        {
            ac->pos = 0;
        }
    }
    else
    {
        if (ac->pos < 2)
        {
            ac->val[ac->pos] = len;
            ac->pos ++;
        }
        else
        {
            ac->val[0] = len;
            ac->pos = 1;
        }
    }

    return (ac->pos == n);
}

static akdatf_header_t* akseq_getpend(akloc_context_t *lc, uint8_t ind)
{
    akdatf_header_t* ret = 0;
    unsigned i;

    for (i = 0; i < sizeof(lc->pendseq)/sizeof(lc->pendseq[0]); i ++)
    {
        akdatf_header_t *p = &lc->pendseq[i];

        if (p->ind == ind)
        {
            ret = p;
            break;
        }
    }

    return ret;
}

static int ak_pendinput_mark(akloc_context_t *lc, uint8_t ind)
{
    int ret = 0;
    akdatf_header_t* pd;

    pd = akseq_getpend(lc, ind);
    if (pd)
    {
        int size, pos, i;
        char d[6] = {0};
        uint8_t crc;

        ind = ind & 0x7f;
        pos = ind * 4;
        size = lc->prslen - pos;
        if (size > 4)
            size = 4;

        for (i = 0; i < size; i ++)
        {
            if (lc->data[pos + i] == 0)
                return 0;
        }

        d[0] = ind;
        memcpy(&d[1], &lc->data[pos], size);
        crc = airkiss_crc8((uint8_t*)d, size + 1) & 0x7f;
        if (crc == (pd->crc & 0x7f))
        {
            memset(pd, 0, sizeof(*pd));
            lc->seq[ind] = 1;
            lc->reclen += size;
            ret = 1;

#ifdef AIRKISS_LOG_GDO_ENABLE
            AKLOG_D("getdata-p(%d, %d)[%s]", ind, size, &d[1]);
#endif
        }
    }

    return ret;
}

static int ak_penddata_getpos(akloc_context_t *lc, akdatf_seq_t *ref, akwire_seq_t ws)
{
    int ret = -1;
    uint8_t refind, ind;
    int offs;

    if (ws < ref->ws)
    {//todo
        AKLOG_D("ws-d overflow(%d, %d)", ws, ref->ws);
    }
    else
    {
        int maxoffs;
        int fmpos;

        offs = (ws - ref->ws)/lc->seqstep;
        if ((offs % 6) < 2)
            return -1;
        maxoffs = lc->prslen + ((lc->prslen + 3)/4) * 2;
        if (offs > maxoffs) /* 相差太大出错几率增大 */
            return ret;

        refind = ref->ind & 0x7f;
        fmpos = refind * 6 + offs;
        fmpos = fmpos % maxoffs; /* 指向下一轮 */
        ind = fmpos/6;

        ret = ind * 4 + (fmpos % 6) - 2;
    }

    return ret;
}

static int ak_pendcrc_getpos(akloc_context_t *lc, akdatf_seq_t *ref, akwire_seq_t ws)
{
    int offs;
    int pos = -1;
    int maxoffs;

    maxoffs = lc->prslen + ((lc->prslen + 3)/4) * 2;

    if (ws < ref->ws)
    {//todo
        AKLOG_D("ws-c overflow(%d, %d)", ws, ref->ws);
    }
    else
    {
        offs = (ws - ref->ws)/lc->seqstep;
        if (offs > maxoffs)
            return -1;
        offs = offs + (ref->ind & 0x7f) * 6;
        offs = offs % maxoffs;
        pos = (offs/6) | 0x80;
    }

    return pos;
}

static void ak_dataconflict_add(akloc_context_t *lc, uint8_t pos, uint8_t d, int mode)
{
    unsigned i;
    int zi = -1;
    int s, e;

    pos ++;
    if (mode == 0)
    {
        s = 0;
        e = sizeof(lc->dcfl.pos) - 4;
    }
    else
    {
        s = sizeof(lc->dcfl.pos) - 4;
        e = sizeof(lc->dcfl.pos);
    }

    for (i = s; i < e; i ++)
    {
        if ((lc->dcfl.pos[i] == pos) && (lc->dcfl.data[i] == d))
            return;
        if (lc->dcfl.pos[i] == 0)
            zi = i;
    }

    if (zi >= 0)
    {
        lc->dcfl.data[zi] = d;
        lc->dcfl.pos[zi] = pos;
    }
}

static int ak_dataconflict_getchar(akloc_context_t *lc, uint8_t pos, uint8_t *cpos)
{
    int ch = -1;
    uint8_t i;

    if (*cpos >= sizeof(lc->dcfl.pos))
        return -1;

    pos ++;
    for (i = *cpos; i < sizeof(lc->dcfl.pos); i ++)
    {
        if (lc->dcfl.pos[i] == pos)
        {
            ch = lc->dcfl.data[i];
            i ++;
            break;
        }
    }

    *cpos = i;

    return ch;
}

static void ak_dataconflict_clear(akloc_context_t *lc, int pos)
{
    unsigned i;

    if (pos < 0)
    {
        i = sizeof(lc->dcfl.pos) - 4;
        for (; i < sizeof(lc->dcfl.pos); i ++)
        {
            lc->dcfl.pos[i] = 0;
            lc->dcfl.data[i] = 0;
        }
    }
    else
    {
        pos ++;
        for (i = 0; i < sizeof(lc->dcfl.pos) - 4; i ++)
        {
            if (lc->dcfl.pos[i] == pos)
            {
                lc->dcfl.pos[i] = 0;
                lc->dcfl.data[i] = 0;
            }
        }
    }
}

static int _dataconflict_crccheck(akloc_context_t *lc, akdatf_header_t* pd, uint8_t dpos, char *d, int size)
{
    int ret = 0;
    uint8_t crc;

    crc = airkiss_crc8((uint8_t*)d, size + 1) & 0x7f;
    if (crc == (pd->crc & 0x7f))
    {
        int pos;

        pos = (pd->ind & 0x7f) * 4;
        memcpy(&lc->data[pos], &d[1], size);
        memset(pd, 0, sizeof(*pd));
        lc->seq[(uint8_t)d[0]] = 1;
        lc->reclen += size;
        ak_dataconflict_clear(lc, dpos);
        ret = 1;

#ifdef AIRKISS_LOG_GDO_ENABLE
        AKLOG_D("getdata-c(%d, %d)[%s]", d[0], size, &d[1]);
#endif
    }

    return ret;
}

static int ak_dataconflict_crccheck(akloc_context_t *lc, akdatf_header_t* pd, int size)
{
    char d[6] = {0};
    uint8_t spos;
    uint8_t cflpos0 = 0, cflpos1 = 0, cflpos2 = 0, cflpos3 = 0;
    int i;

    d[0] = pd->ind & 0x7f;
    spos = d[0] * 4;

    /* 把所有冲突的数据都校验一遍 */

    for (i = 0; i < size; i ++)
    {
        ak_dataconflict_add(lc, spos + i, lc->data[spos + i], 1);
    }

    while (size > 0)
    {
        int ch;

        ch = ak_dataconflict_getchar(lc, spos + 0, &cflpos0);
        if (ch < 0)
            break;
        d[1] = ch;
        cflpos1 = 0;

        while (size > 1)
        {
            int ch;

            ch = ak_dataconflict_getchar(lc, spos + 1, &cflpos1);
            if (ch < 0)
                break;
            d[2] = ch;
            cflpos2 = 0;

            while (size > 2)
            {
                int ch;

                ch = ak_dataconflict_getchar(lc, spos + 2, &cflpos2);
                if (ch < 0)
                    break;
                d[3] = ch;
                cflpos3 = 0;

                while (size > 3)
                {
                    int ch;

                    ch = ak_dataconflict_getchar(lc, spos + 3, &cflpos3);
                    if (ch < 0)
                        break;
                    d[4] = ch;

                    if (_dataconflict_crccheck(lc, pd, spos + 3, d, size))
                    {
                        goto _out;
                    }
                }
            }
        }
    }

_out:
    ak_dataconflict_clear(lc, -1);

    return 0;
}

static int ak_dataconflict_input(akloc_context_t *lc, uint8_t ind, uint8_t pos, uint8_t data)
{
    int ret = 0;
    int i;
    int size;
    int spos;
    akdatf_header_t* pd;

    spos = ind * 4;
    size = lc->prslen - spos;
    if (size > 4)
        size = 4;

    ak_dataconflict_add(lc, pos, data, 0);

    /* 检查接收是否足够 */
    for (i = 0; i < size; i ++)
    {
        if (lc->data[spos + i] == 0)
        {
            return 0;
        }
    }

    /* 查找包头 */
    pd = akseq_getpend(lc, ind | 0x80);
    if (!pd)
        return 0;

    ret = ak_dataconflict_crccheck(lc, pd, size);

    return ret;
}

static int ak_databody_input(akloc_context_t *lc, akdatf_seq_t *ref, akwire_seq_t ws, uint8_t data)
{
    int pos;
    uint8_t ind;
    uint8_t dif;

    /* 与上一个帧相差太大则不接受 */
    dif = (ws - lc->prews)/lc->seqstep;
    if (dif > 5)
        return 0;

    pos = ak_penddata_getpos(lc, ref, ws);
    if (pos < 0)
    {
        return 0;
    }

    ind = pos / 4;
    if (lc->seq[ind])
    {
        return 0;
    }

#if AIRKISS_LOG_RIO_ENABLE
    AKLOG_D("ref(%d %X) input(%d) %c", ref->ws, ref->ind, pos, data);
#endif

    if (lc->data[pos] == 0)
    {
        lc->data[pos] = data;
        ak_pendinput_mark(lc, ind | 0x80);
    }
    else if (lc->data[pos] != data)
    {
        /* 出现数据冲突 */
        ak_dataconflict_input(lc, ind, (uint8_t)pos, data);
    }

    return 1;
}

static void akseq_allocpend(akloc_context_t *lc, uint8_t crc, uint8_t ind)
{
    akdatf_header_t *found = 0, *idle = 0;
    unsigned i;

    if (lc->seq[ind & 0x7f])
        return;

    AKLOG_D("{%X %X}", crc, ind);
    idle = &lc->pendseq[0];
    for (i = 0; i < sizeof(lc->pendseq)/sizeof(lc->pendseq[0]); i ++)
    {
        akdatf_header_t *p = &lc->pendseq[i];

        if (p->ind == ind)
        {
            found = p;
            p->crc = crc;
            break;
        }

        if (p->crc == 0)
            idle = p;
    }

    if (found == NULL)
    {
        found = idle;
        found->crc = crc;
        found->ind = ind;
    }
}

static void ak_datahead_input(akloc_context_t *lc, akdatf_seq_t *cur, akwire_seq_t ws, uint8_t head)
{
    int seqmax;
    uint8_t dif;

    seqmax = (lc->prslen/4) | 0x80;

    if (cur->crc != 0)
    {
        dif = (ws - cur->ws)/lc->seqstep;

        if (head <= seqmax)
        {
            cur->ind = head;
            cur->ws = ws - lc->seqstep;
            AKLOC_DFSEQ_PREV(lc) = *cur;

            if (dif < 3)
            {
                /* 暂存包头 */
                akseq_allocpend(lc, cur->crc, cur->ind);
            }
        }

        if (head > seqmax)
        {
            cur->crc = head;
            cur->ind = 0;
            cur->ws = ws;
        }
    }
    else
    {
        if (head > seqmax) //很大几率是crc
        {
            cur->crc = head;
            cur->ws = ws;
            cur->ind = 0;
        }
        else if (ak_pendcrc_getpos(lc, cur, ws) == head)
        {
            /* 没收到crc */
            cur->ind = head;
            cur->ws = ws - lc->seqstep; /* 设置crc的帧序号 */
        }
    }
}

static int ak_datainput_withwireseq(akloc_context_t *lc, uint8_t *f, uint16_t len)
{
    akwire_seq_t ws;
    akdatf_seq_t *cur;

    ws = akwseq_make(f + 22);
    cur = &AKLOC_DFSEQ_CUR(lc);

    if (len & 0x100) /* 输入数据 */
    {
        akdatf_seq_t *ref;

        ref = &AKLOC_DFSEQ_PREV(lc);

        if ((cur->ind == 0) && (cur->crc != 0))
        {
            int pos;

            /* 如果只收到了crc就根据前一个包推测一个序号 */
            pos = ak_pendcrc_getpos(lc, ref, ws);
            if (pos > 0)
            {
                cur->ind = (uint8_t)pos;
                akseq_allocpend(lc, cur->crc, cur->ind);
            }
        }

        if (cur->ind)
        {
            if (!ak_databody_input(lc, cur, ws, len))
            {
                memset(&AKLOC_DFSEQ_CUR(lc), 0 , sizeof(*cur));
            }

            if (lc->reclen == lc->prslen)
            {
                lc->state = AKSTATE_CMP;
            }
        }

        AKLOC_DFSEQ_CUR(lc).crc = 0;/* 标记已收到数据 */
    }
    else
    {
        /* 输入包头 */
        ak_datahead_input(lc, cur, ws, len);
    }

    lc->prews = ws;

    return 0;
}

static int ak_waitfor_datafield(akloc_context_t *lc, uint8_t *f, uint16_t len, int nossid)
{
    int ret = AIRKISS_STATUS_CONTINUE;
    akcode_t *ac = AKLOC_CODE2(lc);
    uint16_t udplen;

    udplen = aklen_udp(lc, len);
    if (udplen < 0x80)
    {
        return ret;
    }

#ifdef AIRKISS_LOG_DFDUMP_ENABLE
    if (f)
    {
        akdata_dump(lc, f, udplen);
    }
#endif

    if (ak_datainput_onlylength(lc, ac, udplen))
    {
        ac->pos = 0;

        ak_get_datafield(lc, ac);

        if (lc->reclen == lc->prslen)
        {
            lc->state = AKSTATE_CMP;
            goto _out;
        }
    }

    if (f)
    {
        ak_datainput_withwireseq(lc, f, udplen);
    }

    if (nossid && ak_is_pwdrand_complete(lc))
    {
        lc->state = AKSTATE_CMP;
        AKLOG_D("data complete nossid\n");
    }

_out:
    if (lc->state == AKSTATE_CMP)
    {
        lc->nossid = nossid;
        ret = AIRKISS_STATUS_COMPLETE;
    }

    return ret;
}

static int ak_sa_filter(akloc_context_t *lc, uint8_t *f)
{
    int ret = 0;

    if (lc->state != AKSTATE_WFG)
    {
        akaddr_t sa;

        akaddr_fromframe(&sa, f);
        ret = memcmp(&lc->locked, &sa, sizeof(sa));
    }

    return ret;
}

int airkiss_filter(const void *f, int len)
{
    int ret = 0;
    unsigned char *da, *p;
    int i;

    p = (unsigned char *)f;
    if ((len < 25) || (p[0] != 0x08))
        return 1;

    da = p + 4;

    for (i = 0; i < 6; i++)
    {
        if (da[i] != 0xFF)
        {
            ret = 1;
            break;
        }
    }

    return ret;
}

static int _ak_recv(airkiss_context_t *c, const void *frame, uint16_t length, int nossid)
{
    int ret = AIRKISS_STATUS_CONTINUE;
    akloc_context_t *lc = (akloc_context_t *)c;
    unsigned char *f = (unsigned char *)frame;

    if (frame != NULL) /* 模拟测试时可只传length */
    {
        if (airkiss_filter(frame, length))
            return ret;
        if (ak_sa_filter(lc, f))
            return ret;
    }

    switch (lc->state)
    {
    case AKSTATE_WFG:
    {
        ret = ak_waitfor_guidefield(lc, f, length);
    }
    break;
    case AKSTATE_WFM:
    {
        ret = ak_waitfor_magicfield(lc, length);
    }
    break;
    case AKSTATE_WFP:
    {
        ret = ak_waitfor_prefixfield(lc, length);
    }
    break;
    case AKSTATE_WFD:
    {
        ret = ak_waitfor_datafield(lc, f, length, nossid);
    }
    break;
    case AKSTATE_CMP:
    {
        ret = AIRKISS_STATUS_COMPLETE;
    }
    break;
    }

    return ret;
}

const char *airkiss_version(void)
{
    return "airkiss-1.0.0-open";
}

int airkiss_init(airkiss_context_t *c, const airkiss_config_t *config)
{
    akloc_context_t *lc = (akloc_context_t *)c;

    lc->cfg = config;
    akloc_reset(lc);

    return 0;
}

int airkiss_recv(airkiss_context_t *c, const void *frame, unsigned short length)
{
    return _ak_recv(c, frame, length, 0);
}

int airkiss_get_result(airkiss_context_t *c, airkiss_result_t *res)
{
    akloc_context_t *lc = (akloc_context_t *)c;

    if (lc->state != AKSTATE_CMP)
        return -1;

    res->pwd = (char *)&lc->data[0];
    res->pwd_length = lc->pwdlen;
    if (lc->data[lc->pwdlen] == 0)
    {
        res->random = lc->random;
    }
    else
    {
        res->random = lc->data[lc->pwdlen];
        lc->random = lc->data[lc->pwdlen];
        lc->data[lc->pwdlen] = 0;
    }

    res->ssid_crc = lc->ssidcrc;
    if (lc->nossid)
    {
        res->ssid = "";
        res->ssid_length = 0;
    }
    else
    {
        res->ssid = (char *)&lc->data[lc->pwdlen + 1];
        res->ssid_length = lc->prslen - lc->pwdlen - 1;
    }
    lc->data[lc->prslen] = 0;

    return 0;
}

int airkiss_recv_nossid(airkiss_context_t *c, const void *frame, unsigned short length)
{
    return _ak_recv(c, frame, length, 1);
}

int airkiss_change_channel(airkiss_context_t *c)
{
    akloc_context_t *lc = (akloc_context_t *)c;

    akloc_reset(lc);

    return 0;
}
