#include <rtthread.h>
#include <rtdevice.h>

#ifdef RT_WLAN_MANAGE_ENABLE
#include <sys/socket.h>

#include "airkiss.h"

#include <stdlib.h>

#define AKDEMO_BUFSZ 16

static rt_list_t _bflist;
static struct rt_mailbox _bfready;
static int _akrun = 0;
static airkiss_callback airkiss_cb;

typedef struct
{
    rt_list_t list;
    short fmlen;
    char f[24];
} akbuf_t;

typedef struct
{
    char n;
    unsigned char tm;
    unsigned short cnt;
} akchn_t;

static akbuf_t *ak_bufinit(int cnt)
{
    int i;
    akbuf_t *buf, *p;

    rt_list_init(&_bflist);

    buf = (akbuf_t *)rt_calloc(cnt, sizeof(akbuf_t));
    p = buf;
    for (i = 0; (i < cnt) && buf; i++)
    {
        p->fmlen = 0;
        rt_list_init(&p->list);
        rt_list_insert_after(&_bflist, &p->list);
        p++;
    }

    return buf;
}

static int _airkiss_filter(const void *f, int len)
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

static void prom_callback(struct rt_wlan_device *device, void *d, int s)
{
    akbuf_t *buf;

    if (_airkiss_filter(d, s))
        return;

    if (rt_list_isempty(&_bflist))
    {
        rt_kprintf("ak no buf\n");
        return;
    }

    buf = rt_list_first_entry(&_bflist, akbuf_t, list);
    rt_list_remove(&buf->list);

    rt_memcpy(buf->f, d, 24);
    buf->fmlen = s;
    if (rt_mb_send(&_bfready, (rt_ubase_t)buf) != 0)
    {
        rt_list_insert_before(&_bflist, &buf->list);
        rt_kprintf("ak send fail\n");
    }
}

static int ak_recv(airkiss_context_t *ac, int ms, int *rcnt)
{
    akbuf_t *buf = 0;
    int status = AIRKISS_STATUS_CONTINUE;
    rt_tick_t st, max;
    int len = 0;

    st = rt_tick_get();

    while (1)
    {
        if (rt_mb_recv(&_bfready, (rt_ubase_t *)&buf, rt_tick_from_millisecond(10)) == 0)
        {
            status = airkiss_recv(ac, buf->f, buf->fmlen);
            rt_list_insert_after(&_bflist, &buf->list);
            if (status != AIRKISS_STATUS_CONTINUE)
                break;

            if (rcnt && (buf->fmlen != len))
            {
                (*rcnt)++;
                len = buf->fmlen;
                if (ms < 180)
                    ms += 12;
            }
        }
        else
        {
            if ((ms > 30) && rcnt)
                ms -= 2;
        }

        max = rt_tick_from_millisecond(ms);
        if ((rt_tick_get() - st) > max)
            break;
    }

    return status;
}

static int ak_recv_chn(struct rt_wlan_device *dev,
                       airkiss_context_t *ac, akchn_t *chn)
{
    int status;
    int t;
    int rcnt = 0;

    rt_wlan_dev_set_channel(dev, chn->n);
    airkiss_change_channel(ac);

    status = ak_recv(ac, chn->tm, &rcnt);

    if (status == AIRKISS_STATUS_CHANNEL_LOCKED)
    {
        rt_kprintf("airkiss locked chn %d\n", chn->n);
        status = ak_recv(ac, 1000 * 30, RT_NULL);
    }

    chn->cnt += rcnt;
    if (chn->cnt > 5)
        chn->cnt -= 3;
    t = chn->cnt * chn->cnt * chn->cnt;

    if (t)
    {
        if (t > 170)
            t = 170;
        chn->tm = 30 + t;

        rt_kprintf("tm(%d) cnt(%d) on chn %d\n", chn->tm, chn->cnt, chn->n);
    }

    return status;
}

static void akchn_init(akchn_t *chn, int n)
{
    int i;

    for (i = 0; i < n; i++)
    {
        chn[i].n = i + 1;
        chn[i].cnt = 0;
        chn[i].tm = 20;
    }
}

static int ak_wifi_connetct(char *ssid, char *passwd)
{
    int result = RT_EOK;
    rt_uint8_t time_cnt = 0;

#define NET_READY_TIME_OUT (rt_tick_from_millisecond(8 * 1000))

    result = rt_wlan_connect(ssid, passwd);
    if (result != RT_EOK)
    {
        rt_kprintf("\nconnect ssid %s error:%d!\n", ssid, result);
        return result;
    };

    do
    {
        rt_thread_mdelay(1000);
        time_cnt++;
        if (rt_wlan_is_ready())
        {
            break;
        }
    } while (time_cnt <= (NET_READY_TIME_OUT / 1000));

    if (time_cnt <= (NET_READY_TIME_OUT / 1000))
    {
        rt_kprintf("networking ready!\n");
    }
    else
    {
        rt_kprintf("wait ip got timeout!\n");
        result = -1;
    }

    return result;
}

static void airkiss_send_notification(uint8_t random)
{
    int sock = -1;
    int udpbufsize = 2;
    struct sockaddr_in UDPBCAddr, UDPBCServerAddr;

    sock = socket(AF_INET, SOCK_DGRAM, 0);
    if (sock < 0)
    {
        rt_kprintf("notify create socket error!\n");
        goto _exit;
    }

    UDPBCAddr.sin_family = AF_INET;
    UDPBCAddr.sin_port = htons(10000);
    UDPBCAddr.sin_addr.s_addr = htonl(0xffffffff);
    rt_memset(&(UDPBCAddr.sin_zero), 0, sizeof(UDPBCAddr.sin_zero));

    UDPBCServerAddr.sin_family = AF_INET;
    UDPBCServerAddr.sin_port = htons(10000);
    UDPBCServerAddr.sin_addr.s_addr = htonl(INADDR_ANY);
    rt_memset(&(UDPBCServerAddr.sin_zero), 0, sizeof(UDPBCServerAddr.sin_zero));

    if (setsockopt(sock, SOL_SOCKET, SO_BROADCAST, &udpbufsize, sizeof(int)) != 0)
    {
        rt_kprintf("notify socket setsockopt error\n");
        goto _exit;
    }

    if (bind(sock, (struct sockaddr *)&UDPBCServerAddr, sizeof(UDPBCServerAddr)) != 0)
    {
        rt_kprintf("notify socket bind error\n");
        goto _exit;
    }

    for (int i = 0; i <= 20; i++)
    {
        int ret = sendto(sock, (char *)&random, 1, 0, (struct sockaddr *)&UDPBCAddr, sizeof(UDPBCAddr));
        rt_thread_mdelay(10);
    }

_exit:
    if (sock >= 0)
    {
        closesocket(sock);
    }
}

void airkiss_set_callback(airkiss_callback cb) {
    airkiss_cb = cb;
}

static void do_airkiss_configwifi(void)
{
    airkiss_context_t ac;
    struct rt_wlan_device *dev;
    akbuf_t *pbuf;
    int n;
    akchn_t chns[13];
    int round = 120;
    int re = -1;
    airkiss_config_t acfg =
        {
            (airkiss_memset_fn)&rt_memset,
            (airkiss_memcpy_fn)&rt_memcpy,
            (airkiss_memcmp_fn)&rt_memcmp,
            (airkiss_printf_fn)&rt_kprintf};
    int _mbuf[AKDEMO_BUFSZ];

    rt_kprintf("airkiss thread start\n");
    if ((pbuf = ak_bufinit(AKDEMO_BUFSZ)) == RT_NULL)
    {
        rt_kprintf("akdemo init buf err\n");
        return;
    }

    airkiss_init(&ac, &acfg);

    rt_mb_init(&_bfready, "ak", _mbuf, AKDEMO_BUFSZ, 0);
    rt_wlan_config_autoreconnect(0);
    rt_wlan_disconnect();
    dev = (struct rt_wlan_device *)rt_device_find(RT_WLAN_DEVICE_STA_NAME);
    rt_wlan_dev_set_promisc_callback(dev, prom_callback);

    rt_wlan_dev_enter_promisc(dev);

    akchn_init(chns, sizeof(chns) / sizeof(chns[0]));

    rt_kprintf("%s\n", airkiss_version());

    while (round-- > 0)
    {
        //rt_kprintf("ak round\n");
        for (n = 0; n < sizeof(chns) / sizeof(chns[0]); n++)
        {
            if (ak_recv_chn(dev, &ac, &chns[n]) == AIRKISS_STATUS_COMPLETE)
            {
                airkiss_result_t res;

                rt_wlan_dev_exit_promisc(dev);

                airkiss_get_result(&ac, &res);
                rt_kprintf("ssid %s pwd %s\n", res.ssid, res.pwd);
                if (airkiss_cb) {
                    re = 0;
                    airkiss_cb(0, res.ssid, res.pwd);
                }

                if (ak_wifi_connetct(res.ssid, res.pwd) == 0)
                {
                    airkiss_send_notification(res.random);
                }

                goto _out;
            }
        }
    }

    rt_wlan_dev_exit_promisc(dev);

_out:
    rt_wlan_dev_set_promisc_callback(dev, RT_NULL);
    rt_wlan_config_autoreconnect(1);
    rt_mb_detach(&_bfready);
    rt_free(pbuf);
    _akrun = 0;
    if (airkiss_cb && re != 0) {
        airkiss_cb(re, RT_NULL, RT_NULL);
    }
    rt_kprintf("airkiss exit\n");
}

static void airkiss_thread(void *p)
{
    do_airkiss_configwifi();
}

int airkiss_start(void)
{
    rt_thread_t tid;
    int ret = -1;

    if (_akrun)
        return ret;

    tid = rt_thread_create("airkiss",
                           airkiss_thread,
                           0,
                           2048,
                           22,
                           20);

    if (tid)
    {
        ret = rt_thread_startup(tid);
    }
    _akrun = (ret == 0);

    return ret;
}

#ifdef RT_USING_FINSH
/* 用于测试 */

typedef struct
{
    char isrun;
    char schn;
    char echn;
    char omode;
} akcap_t;

static void showakbuf(akbuf_t *buf, int mode)
{
    char str[58];
    int i, pos = 0;
    int fs = mode & 0x1f;

    if (fs < 24)
    {
        for (i = fs; i < 24; i++)
        {
            rt_sprintf(str + pos, "%02X", buf->f[i]);
            pos += 2;
        }
        rt_sprintf(str + pos, ":%d\n", buf->fmlen);

        if (mode & 0x80)
        {
            pos = rt_strlen(str) - 1;
            rt_sprintf(str + pos, ":%d\n", rt_tick_get());
        }

        rt_kprintf(str);
    }
}

static int recv_no_change(airkiss_context_t *ac, int omode)
{
    akbuf_t *buf = 0;
    int status;

    if (rt_mb_recv(&_bfready, (rt_ubase_t *)&buf, rt_tick_from_millisecond(10)) == 0)
    {
        status = airkiss_recv(ac, buf->f, buf->fmlen);
        showakbuf(buf, omode);
        rt_list_insert_after(&_bflist, &buf->list);
    }

    return (status == AIRKISS_STATUS_COMPLETE);
}

static void airkiss_thread_cap(void *p)
{
    akcap_t *cap = (akcap_t *)p;
    airkiss_context_t ac;
    struct rt_wlan_device *dev;
    akbuf_t *pbuf;
    akchn_t chns[14];
    int _mbuf[AKDEMO_BUFSZ];

    if ((pbuf = ak_bufinit(AKDEMO_BUFSZ)) == RT_NULL)
    {
        rt_kprintf("akdemo init buf err\n");
        return;
    }

    airkiss_init(&ac, RT_NULL);

    rt_mb_init(&_bfready, "ak", _mbuf, AKDEMO_BUFSZ, 0);
    if (rt_wlan_is_connected()) {
        rt_wlan_disconnect();
        rt_wlan_config_autoreconnect(0);
    }
    dev = (struct rt_wlan_device *)rt_device_find(RT_WLAN_DEVICE_STA_NAME);
    rt_wlan_set_mode(RT_WLAN_DEVICE_STA_NAME, RT_WLAN_NONE);
    rt_wlan_dev_set_promisc_callback(dev, prom_callback);

    rt_wlan_dev_enter_promisc(dev);

    akchn_init(chns, sizeof(chns) / sizeof(chns[0]));

    rt_kprintf("airkiss cap start\n");

    if (cap->schn == cap->echn)
    {
        rt_wlan_dev_set_channel(dev, cap->schn);

        while (cap->isrun)
        {
            if (recv_no_change(&ac, cap->omode))
            {
                airkiss_result_t res;

                rt_wlan_dev_exit_promisc(dev);

                airkiss_get_result(&ac, &res);
                rt_kprintf("pwd %s ssid %s\n", res.pwd, res.ssid);
                break;
            }
        }
    }
    else
    {
    }

    rt_wlan_dev_exit_promisc(dev);
    rt_wlan_dev_set_promisc_callback(dev, RT_NULL);
    rt_mb_detach(&_bfready);
    rt_free(pbuf);
    _akrun = 0;

    rt_kprintf("airkiss exit\n");
}

static int airkiss_cap_start(akcap_t *cap)
{
    rt_thread_t tid;
    int ret = -1;

    if (_akrun)
        return ret;

    tid = rt_thread_create("airkiss",
                           airkiss_thread_cap,
                           cap,
                           2048,
                           22,
                           20);

    if (tid)
    {
        ret = rt_thread_startup(tid);
    }
    _akrun = (ret == 0);

    return ret;
}

static void airkiss(int c, char **v)
{
    static akcap_t cap = {0};
    int chn = 0;
    int op = 0;

    while (c)
    {
        switch (c)
        {
        case 5:
            if (v[4][0] == 't')
                cap.omode = 0x80;
            break;
        case 4:
            cap.omode |= atoi(&(v[3][1]));
            break;
        case 3:
            chn = atoi(v[2]);
            break;
        case 2:
            op = v[1][0];
            break;
        }

        c--;
    }

    if (op == 0)
    {
        airkiss_start();
    }
    else if (op == 'c')
    {
        if (chn == 0)
        {
            cap.schn = 1;
            cap.echn = 13;
        }
        else
        {
            cap.schn = chn;
            cap.echn = chn;
        }
        cap.isrun = 1;
        airkiss_cap_start(&cap);
    }
}
MSH_CMD_EXPORT(airkiss, start airkiss);
#endif

#endif
