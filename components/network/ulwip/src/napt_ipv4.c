/*
NAPT(Network Address Port Translation)
IPv4版本的NAPT，支持TCP/UDP/ICMP协议
原版代码来源:
https://gitee.com/openLuat/luatos-soc-air101
https://www.winnermicro.com/html/1/156/158/558.html

为适应luatos环境做了大量修改, 脱离了平台依赖性
*/
#include "luat_base.h"
#include <stdio.h>
#include <string.h>
#include "lwip/ip.h"
#include "lwip/udp.h"
#include "lwip/icmp.h"
#include "lwip/dns.h"
#include "lwip/priv/tcp_priv.h"
#include "lwip/timeouts.h"

#include "luat_napt.h"
#include "luat_mem.h"

#define LUAT_LOG_TAG "napt"
#include "luat_log.h"

//#define NAPT_ALLOC_DEBUG
#ifdef  NAPT_ALLOC_DEBUG
static u16 napt4ic_cnt;
static u16 napt4tcp_cnt;
static u16 napt4udp_cnt;
#endif

//#define NAPT_DEBUG
#ifdef  NAPT_DEBUG
#define NAPT_PRINT printf
#else
#define NAPT_PRINT(...)
#endif

#define IP_PROTO_GRE                 47

#define NAPT_ETH_HDR_LEN             sizeof(struct ethhdr)

#define NAPT_CHKSUM_16BIT_LEN        sizeof(u16)

#define NAPT_TABLE_FOREACH(pos, head)\
         for (pos = head.next; NULL != pos; pos = pos->next)

/* napt tcp/udp */
struct napt_addr_4tu{
    struct napt_addr_4tu *next;
    u16 src_port;
    u16 new_port;
    u8 src_ip;
    u8 time_stamp;
    u8 mac[6];
};

/* napt icmp */
struct napt_addr_4ic{
    struct napt_addr_4ic *next;
    u16 src_id;/* icmp id */
    u16 new_id;
    u8 src_ip;
    u8 time_stamp;
    u8 mac[6];
};

struct napt_addr_gre{
    u8 src_ip;
    u8 time_stamp;
    u8 is_used;
    u8 mac[6];
};

struct napt_table_head_4tu{
    struct napt_addr_4tu *next;
#ifdef NAPT_TABLE_LIMIT
    u16 cnt;
#endif
};

struct napt_table_head_4ic{
    struct napt_addr_4ic *next;
#ifdef NAPT_TABLE_LIMIT
    u16 cnt;
#endif
};

/* napt head */
static struct napt_table_head_4tu napt_table_4tcp;
static struct napt_table_head_4tu napt_table_4udp;
static struct napt_table_head_4ic napt_table_4ic;

//#define NAPT_USE_HW_TIMER

//#define NAPT_TABLE_MUTEX_LOCK
#ifdef  NAPT_TABLE_MUTEX_LOCK
static tls_os_sem_t *napt_table_lock_4tcp;
static tls_os_sem_t *napt_table_lock_4udp;
static tls_os_sem_t *napt_table_lock_4ic;
#ifdef  NAPT_USE_HW_TIMER
static bool napt_check_tcp = FALSE;
static bool napt_check_udp = FALSE;
static bool napt_check_ic  = FALSE;
#endif /* NAPT_USE_HW_TIMER */
#endif /* NAPT_TABLE_MUTEX_LOCK */

/* tcp&udp */
static u16 napt_curr_port;

/* icmp id */
static u16 napt_curr_id;

/* gre for vpn */
static struct napt_addr_gre gre_info;

static inline void *luat_napt_mem_alloc(u32 size)
{
    return luat_heap_malloc(size);
}

static inline void luat_napt_mem_free(void *p)
{
    luat_heap_free(p);
}

/*****************************************************************************
 Prototype    : luat_napt_try_lock
 Description  : try hold lock
 Input        : tls_os_sem_t *lock  point lock
 Output       : None
 Return Value : int  0  success
                    -1  failed
 ------------------------------------------------------------------------------
 
  History        :
  1.Date         : 2019/2/1
    Author       : Li Limin, lilm@winnermicro.com
    Modification : Created function

*****************************************************************************/
// static inline int luat_napt_try_lock(tls_os_sem_t *lock)
// {
//     return (tls_os_sem_acquire(lock, HZ / 10) == TLS_OS_SUCCESS) ? 0 : -1;
//     return 0;
// }

/*****************************************************************************
 Prototype    : luat_napt_lock
 Description  : hold lock
 Input        : tls_os_sem_t *lock  point lock
 Output       : None
 Return Value : void
 ------------------------------------------------------------------------------
 
  History        :
  1.Date         : 2019/2/1
    Author       : Li Limin, lilm@winnermicro.com
    Modification : Created function

*****************************************************************************/
// static inline void luat_napt_lock(tls_os_sem_t *lock)
// {
//     tls_os_sem_acquire(lock, 0);
//     return;
// }

/*****************************************************************************
 Prototype    : luat_napt_unlock
 Description  : release lock
 Input        : tls_os_sem_t *lock  point lock
 Output       : None
 Return Value : void
 ------------------------------------------------------------------------------
 
  History        :
  1.Date         : 2019/2/1
    Author       : Li Limin, lilm@winnermicro.com
    Modification : Created function

*****************************************************************************/
// static inline void luat_napt_unlock(tls_os_sem_t *lock)
// {
//     tls_os_sem_release(lock);
// }

#ifdef NAPT_TABLE_LIMIT
/*****************************************************************************
 Prototype    : luat_napt_table_is_full
 Description  : the napt table is full
 Input        : void
 Output       : None
 Return Value : bool    true   the napt table is full
                        false  the napt table not is full
 ------------------------------------------------------------------------------
 
  History        :
  1.Date         : 2015/3/10
    Author       : Li Limin, lilm@winnermicro.com
    Modification : Created function

*****************************************************************************/
static inline bool luat_napt_table_is_full(void)
{
    bool is_full = false;

    if ((napt_table_4tcp.cnt + napt_table_4udp.cnt + napt_table_4ic.cnt) >= NAPT_TABLE_SIZE_MAX)
    {
#ifdef NAPT_ALLOC_DEBUG
        printf("@@@ napt batle: limit is reached for tcp/udp.\r\n");
#endif
        NAPT_PRINT("napt batle: limit is reached for tcp/udp.\n");
        is_full = true;
    }

    return is_full;
}
#endif

static inline u16 luat_napt_port_alloc(void)
{
    u8_t i;
    u16 cnt = 0;
    struct udp_pcb *udp_pcb;
    struct tcp_pcb *tcp_pcb;
    struct napt_addr_4tu *napt_tcp;
    struct napt_addr_4tu *napt_udp;

again:
    if (napt_curr_port++ == NAPT_LOCAL_PORT_RANGE_END)
    {
        napt_curr_port = NAPT_LOCAL_PORT_RANGE_START;
    }

    /* udp */
    for(udp_pcb = udp_pcbs; udp_pcb != NULL; udp_pcb = udp_pcb->next)
    {
        if (udp_pcb->local_port == napt_curr_port)
        {
            if (++cnt > (NAPT_LOCAL_PORT_RANGE_END - NAPT_LOCAL_PORT_RANGE_START))
            {
                return 0;
            }
            goto again;
        }
    }

    /* tcp */
    for (i = 0; i < NUM_TCP_PCB_LISTS; i++)
    {
        for(tcp_pcb = *tcp_pcb_lists[i]; tcp_pcb != NULL; tcp_pcb = tcp_pcb->next)
        {
            if (tcp_pcb->local_port == napt_curr_port)
            {
                if (++cnt > (NAPT_LOCAL_PORT_RANGE_END - NAPT_LOCAL_PORT_RANGE_START))
                {
                    return 0;
                }
                goto again;
            }
        }
    }

    /* tcp napt */
    NAPT_TABLE_FOREACH(napt_tcp, napt_table_4tcp)
    {
        if (napt_tcp->new_port == napt_curr_port)
        {
            if (++cnt > (NAPT_LOCAL_PORT_RANGE_END - NAPT_LOCAL_PORT_RANGE_START))
            {
                return 0;
            }
            goto again;
        }
    }

    /* udp napt */
    NAPT_TABLE_FOREACH(napt_udp, napt_table_4udp)
    {
        if (napt_udp->new_port == napt_curr_port)
        {
            if (++cnt > (NAPT_LOCAL_PORT_RANGE_END - NAPT_LOCAL_PORT_RANGE_START))
            {
                return 0;
            }
            goto again;
        }
    }

    return napt_curr_port;
}

static inline struct napt_addr_4ic *luat_napt_get_by_src_id(u16 id, u8 ip)
{
    struct napt_addr_4ic *ret = NULL;
    struct napt_addr_4ic *napt;

    NAPT_TABLE_FOREACH(napt, napt_table_4ic)
    {
        if ((id == napt->src_id) && (ip == napt->src_ip))
        {
	       ret = napt;
	       break;
        }
    }

    return ret;
}

static inline struct napt_addr_4ic *luat_napt_get_by_dst_id(u16 id)
{
    struct napt_addr_4ic *ret = NULL;
    struct napt_addr_4ic *napt;

    NAPT_TABLE_FOREACH(napt, napt_table_4ic)
    {
        if (id == napt->new_id)
        {
	       ret = napt;
	       break;
        }
    }

    return ret;
}

static u16 luat_napt_icmp_id_alloc(void)
{
    u16 cnt = 0;
    struct napt_addr_4ic *napt;

again:
    if (napt_curr_id++ == NAPT_ICMP_ID_RANGE_END)
    {
        napt_curr_id = NAPT_ICMP_ID_RANGE_START;
    }

    NAPT_TABLE_FOREACH(napt, napt_table_4ic)
    {
        if (napt_curr_id == napt->new_id)
        {
            if (++cnt > (NAPT_ICMP_ID_RANGE_END - NAPT_ICMP_ID_RANGE_START))
            {
                return 0;
            }

	       goto again;
        }
    }

    return napt_curr_id;
}

static inline struct napt_addr_4ic *luat_napt_table_insert_4ic(u16 id, u8 ip)
{
    struct napt_addr_4ic *napt;

#ifdef NAPT_TABLE_LIMIT
    if (true == luat_napt_table_is_full())
    {
        return NULL;
    }
#endif

    napt = luat_napt_mem_alloc(sizeof(struct napt_addr_4ic));
    if (NULL == napt)
    {
        return NULL;
    }

    memset(napt, 0, sizeof(struct napt_addr_4ic));
    napt->src_id = id;

    napt->new_id = luat_napt_icmp_id_alloc();
    if (0 == napt->new_id)
    {
        luat_napt_mem_free(napt);
        return NULL;
    }

    napt->src_ip = ip;
    napt->time_stamp++;

#ifdef NAPT_TABLE_LIMIT
    napt_table_4ic.cnt++;
#endif
    napt->next = napt_table_4ic.next;
    napt_table_4ic.next = napt;
    
#ifdef NAPT_ALLOC_DEBUG
    printf("@@ napt id alloc %hu\r\n", ++napt4ic_cnt);
#endif

    return napt;
}

static inline void luat_napt_table_update_4ic(struct napt_addr_4ic *napt)
{
    if (!++napt->time_stamp)
        napt->time_stamp++;

    return;
}

static inline struct napt_addr_4tu *luat_napt_get_tcp_port_by_dest(u16 port)
{
    struct napt_addr_4tu *ret = NULL;
    struct napt_addr_4tu *napt;

    NAPT_TABLE_FOREACH(napt, napt_table_4tcp)
    {
        if (napt->new_port == port)
        {
            ret = napt;
            break;
        }
    }

    return ret;
}

static inline struct napt_addr_4tu *luat_napt_get_tcp_port_by_src(u16 port, u8 ip)
{
    struct napt_addr_4tu *ret = NULL;
    struct napt_addr_4tu *napt;

    NAPT_TABLE_FOREACH(napt, napt_table_4tcp)
    {
        if (port == napt->src_port)
        {
            if (ip == napt->src_ip)
            {
                ret = napt;
                break;
            }
        }
    }

    return ret;
}

static inline struct napt_addr_4tu *luat_napt_table_insert_4tcp(u16 src_port, u8 ip)
{
    u16 new_port;
    struct napt_addr_4tu *napt;

#ifdef NAPT_TABLE_LIMIT
    if (true == luat_napt_table_is_full())
    {
        return NULL;
    }
#endif

    napt = luat_napt_mem_alloc(sizeof(struct napt_addr_4tu));
    if (NULL == napt)
    {
        return NULL;
    }

    memset(napt, 0, sizeof(struct napt_addr_4tu));
    napt->src_port = src_port;

    new_port = luat_napt_port_alloc();
    if (0 == new_port)
    {
        luat_napt_mem_free(napt);
        return NULL;
    }

    napt->new_port = htons(new_port);
    napt->src_ip = ip;
    napt->time_stamp++;

#ifdef NAPT_TABLE_LIMIT
    napt_table_4tcp.cnt++;
#endif
    napt->next = napt_table_4tcp.next;
    napt_table_4tcp.next = napt;

#ifdef NAPT_ALLOC_DEBUG
    printf("@@ napt tcp port alloc %hu\r\n", ++napt4tcp_cnt);
#endif

    return napt;
}

static inline void luat_napt_table_update_4tcp(struct napt_addr_4tu *napt)
{
    if (!++napt->time_stamp)
        napt->time_stamp++;

    return;
}

static inline struct napt_addr_4tu *luat_napt_get_udp_port_by_dest(u16 port)
{
    struct napt_addr_4tu *ret = NULL;
    struct napt_addr_4tu *napt;

    NAPT_TABLE_FOREACH(napt, napt_table_4udp)
    {
        if (napt->new_port == port)
        {
            ret = napt;
            break;
        }
    }

    return ret;
}

static inline struct napt_addr_4tu *luat_napt_get_udp_port_by_src(u16 port, u8 ip)
{
    struct napt_addr_4tu *ret = NULL;
    struct napt_addr_4tu *napt;

    NAPT_TABLE_FOREACH(napt, napt_table_4udp)
    {
        if (port == napt->src_port)
        {
            if (ip == napt->src_ip)
            {
                ret = napt;
                break;
            }
        }
    }

    return ret;
}
static inline struct napt_addr_4tu *luat_napt_table_insert_4udp(u16 src_port, u8 ip)
{
    u16 new_port;
    struct napt_addr_4tu *napt;

#ifdef NAPT_TABLE_LIMIT
    if (true == luat_napt_table_is_full())
    {
        return NULL;
    }
#endif

    napt = luat_napt_mem_alloc(sizeof(struct napt_addr_4tu));
    if (NULL == napt)
    {
        return NULL;
    }

    memset(napt, 0, sizeof(struct napt_addr_4tu));
    napt->src_port = src_port;

    new_port = luat_napt_port_alloc();
    if (0 == new_port)
    {
        luat_napt_mem_free(napt);
        return NULL;
    }

    napt->new_port = htons(new_port);
    napt->src_ip = ip;
    napt->time_stamp++;

#ifdef NAPT_TABLE_LIMIT
    napt_table_4udp.cnt++;
#endif
    napt->next = napt_table_4udp.next;
    napt_table_4udp.next = napt;

#ifdef NAPT_ALLOC_DEBUG
    printf("@@ napt udp port alloc %hu\r\n", ++napt4udp_cnt);
#endif

    return napt;
}

static inline void luat_napt_table_update_4udp(struct napt_addr_4tu *napt)
{
    if (!++napt->time_stamp)
        napt->time_stamp++;

    return;
}

static void luat_napt_table_check_4tcp(void)
{
    struct napt_addr_4tu *napt4tcp;
    struct napt_addr_4tu *napt4tcp_prev;

    /* tcp */
#ifdef NAPT_TABLE_MUTEX_LOCK
#ifdef NAPT_USE_HW_TIMER
    if (luat_napt_try_lock(napt_table_lock_4tcp))
    {
        //printf("## try tcp\r\n");
        napt_check_tcp = TRUE;
        return;
    }
    napt_check_tcp = FALSE;
#else
    luat_napt_lock(napt_table_lock_4tcp);
#endif
#endif
    for (napt4tcp_prev = napt_table_4tcp.next;\
         NULL != napt4tcp_prev;\
         napt4tcp_prev = napt4tcp_prev->next)
    {
        napt4tcp = napt4tcp_prev->next;
        if (NULL != napt4tcp)
        {
            if (0 == napt4tcp->time_stamp)
            {
#ifdef NAPT_TABLE_LIMIT
                napt_table_4tcp.cnt--;
#endif
                napt4tcp_prev->next = napt4tcp->next;
                napt4tcp->next = NULL;
                luat_napt_mem_free(napt4tcp);
#ifdef NAPT_ALLOC_DEBUG
                printf("@@ napt tcp port free %hu\r\n", --napt4tcp_cnt);
#endif
            }
            else
            {
                napt4tcp->time_stamp = 0;
            }
        }
        
    }
    napt4tcp = napt_table_4tcp.next;
    if (NULL != napt4tcp)
    {
        if (0 == napt4tcp->time_stamp)
        {
#ifdef NAPT_TABLE_LIMIT
            napt_table_4tcp.cnt--;
#endif
            napt_table_4tcp.next = napt4tcp->next;
            napt4tcp->next = NULL;
            luat_napt_mem_free(napt4tcp);
#ifdef NAPT_ALLOC_DEBUG
            printf("@@ napt tcp port free %hu\r\n", --napt4tcp_cnt);
#endif
        }
        else
        {
            napt4tcp->time_stamp = 0;
        }
    }
#ifdef NAPT_TABLE_MUTEX_LOCK
    luat_napt_unlock(napt_table_lock_4tcp);
#endif
    return;
}

static void luat_napt_table_check_4udp(void)
{
    struct napt_addr_4tu *napt4udp;
    struct napt_addr_4tu *napt4udp_prev;

    /* udp */
#ifdef NAPT_TABLE_MUTEX_LOCK
#ifdef NAPT_USE_HW_TIMER
    if (luat_napt_try_lock(napt_table_lock_4udp))
    {
        //printf("## try udp\r\n");
        napt_check_udp = TRUE;
        return;
    }
    napt_check_udp = FALSE;
#else
    luat_napt_lock(napt_table_lock_4udp);
#endif
#endif
    for (napt4udp_prev = napt_table_4udp.next;\
         NULL != napt4udp_prev;\
         napt4udp_prev = napt4udp_prev->next)
    {
        napt4udp = napt4udp_prev->next;
        if (NULL != napt4udp)
        {
            if (0 == napt4udp->time_stamp)
            {
#ifdef NAPT_TABLE_LIMIT
                napt_table_4udp.cnt--;
#endif
                napt4udp_prev->next = napt4udp->next;
                napt4udp->next = NULL;
                luat_napt_mem_free(napt4udp);
#ifdef NAPT_ALLOC_DEBUG
                printf("@@ napt udp port free %hu\r\n", --napt4udp_cnt);
#endif
            }
            else
            {
                napt4udp->time_stamp = 0;
            }
        }
        
    }
    napt4udp = napt_table_4udp.next;
    if (NULL != napt4udp)
    {
        if (0 == napt4udp->time_stamp)
        {
#ifdef NAPT_TABLE_LIMIT
            napt_table_4udp.cnt--;
#endif
            napt_table_4udp.next = napt4udp->next;
            napt4udp->next = NULL;
            luat_napt_mem_free(napt4udp);
#ifdef NAPT_ALLOC_DEBUG
            printf("@@ napt udp port free %hu\r\n", --napt4udp_cnt);
#endif
        }
        else
        {
            napt4udp->time_stamp = 0;
        }
    }
#ifdef NAPT_TABLE_MUTEX_LOCK
    luat_napt_unlock(napt_table_lock_4udp);
#endif
    return;
}

static void luat_napt_table_check_4ic(void)
{
    struct napt_addr_4ic *napt4ic;
    struct napt_addr_4ic *napt4ic_prev;

    /* icmp */
#ifdef NAPT_TABLE_MUTEX_LOCK
#ifdef NAPT_USE_HW_TIMER
    if (luat_napt_try_lock(napt_table_lock_4ic))
    {
        //printf("## try ic\r\n");
        napt_check_ic = TRUE;
        return;
    }
    napt_check_ic = FALSE;
#else
    luat_napt_lock(napt_table_lock_4ic);
#endif
#endif
    /* skip the first item */
    for (napt4ic_prev = napt_table_4ic.next;\
         NULL != napt4ic_prev;\
         napt4ic_prev = napt4ic_prev->next)
    {
        napt4ic = napt4ic_prev->next;
        if (NULL != napt4ic)
        {
            if (0 == napt4ic->time_stamp)
            {
#ifdef NAPT_TABLE_LIMIT
                napt_table_4ic.cnt--;
#endif
                napt4ic_prev->next = napt4ic->next;
                napt4ic->next = NULL;
                luat_napt_mem_free(napt4ic);
#ifdef NAPT_ALLOC_DEBUG
                printf("@@ napt id free %hu\r\n", --napt4ic_cnt);
#endif
            }
            else
            {
                napt4ic->time_stamp = 0;
            }
        }
        
    }
    /* check the first item */
    napt4ic = napt_table_4ic.next;
    if (NULL != napt4ic)
    {
        if (0 == napt4ic->time_stamp)
        {
#ifdef NAPT_TABLE_LIMIT
            napt_table_4ic.cnt--;
#endif
            napt_table_4ic.next = napt4ic->next;
            napt4ic->next = NULL;
            luat_napt_mem_free(napt4ic);
#ifdef NAPT_ALLOC_DEBUG
            printf("@@ napt id free %hu\r\n", --napt4ic_cnt);
#endif
        }
        else
        {
            napt4ic->time_stamp = 0;
        }
    }
#ifdef NAPT_TABLE_MUTEX_LOCK
    luat_napt_unlock(napt_table_lock_4ic);
#endif
    return;
}

static void luat_napt_table_check_4gre(void)
{
    if (0 == gre_info.time_stamp)
    {
        gre_info.is_used = 0;
        //gre_info.src_ip = 0;
    }
    else
    {
        gre_info.time_stamp = 0;
    }

    return;
}

void luat_napt_table_check(void *arg)
{
    luat_napt_table_check_4tcp();
    luat_napt_table_check_4udp();
    luat_napt_table_check_4ic();
    luat_napt_table_check_4gre();

    return;
}

#ifdef NAPT_USE_HW_TIMER
static void luat_napt_table_check_try(void)
{
    if (napt_check_tcp)
        luat_napt_table_check_4tcp();

    if (napt_check_udp)
        luat_napt_table_check_4udp();

    if (napt_check_ic)
        luat_napt_table_check_4ic();

    return;
}
#endif

static inline u32 alg_hdr_16bitsum(const u16 *buff, u16 len)
{
    u32 sum = 0;

    u16 *pos = (u16 *)buff;
    u16 remainder_size = len;

    while (remainder_size > 1)
    {
        sum += *pos ++;
        remainder_size -= NAPT_CHKSUM_16BIT_LEN;
    }

    if (remainder_size > 0)
    {
        sum += *(u8*)pos;
    }

    return sum;
}

static inline u16 alg_iphdr_chksum(const u16 *buff, u16 len)
{
    u32 sum = alg_hdr_16bitsum(buff, len);

    sum = (sum >> 16) + (sum & 0xFFFF);
    sum += (sum >> 16);

    return (u16)(~sum);
}

static inline u16 alg_tcpudphdr_chksum(u32 src_addr, u32 dst_addr, u8 proto,
                                       const u16 *buff, u16 len)
{
    u32 sum = 0;

    sum += (src_addr & 0xffffUL);
    sum += ((src_addr >> 16) & 0xffffUL);
    sum += (dst_addr & 0xffffUL);
    sum += ((dst_addr >> 16) & 0xffffUL);
    sum += (u32)htons((u16)proto);
    sum += (u32)htons(len);

    sum += alg_hdr_16bitsum(buff, len);

    sum = (sum >> 16) + (sum & 0xFFFF);
    sum += (sum >> 16);

    return (u16)(~sum);
}

static int alg_icmp_proc(u8 is_inet,
                         struct ip_hdr *ip_hdr,
                         ip_addr_t* gw_ip)
{
    int err = -1;
    struct napt_addr_4ic *napt;
    struct icmp_echo_hdr *icmp_hdr;
    u8* ptr = ((u8*)ip_hdr) - 14;
    u8 iphdr_len;

    iphdr_len = (ip_hdr->_v_hl & 0x0F) * 4;
    icmp_hdr = (struct icmp_echo_hdr *)((u8 *)ip_hdr + iphdr_len);

    if (is_inet)
    {

#ifdef NAPT_TABLE_MUTEX_LOCK
        luat_napt_lock(napt_table_lock_4ic);
#endif
        napt = luat_napt_get_by_src_id(icmp_hdr->id, ip_hdr->src.addr >> 24);
        if (NULL == napt)
        {
            napt = luat_napt_table_insert_4ic(icmp_hdr->id, ip_hdr->src.addr >> 24);
            if (NULL == napt)
            {
#ifdef NAPT_TABLE_MUTEX_LOCK
                luat_napt_unlock(napt_table_lock_4ic);
#endif
                return -1;
            }
        }
        else
        {
            luat_napt_table_update_4ic(napt);
        }

        icmp_hdr->id = napt->new_id;
        memcpy(napt->mac, ptr + 6, 6);
#ifdef NAPT_TABLE_MUTEX_LOCK
        luat_napt_unlock(napt_table_lock_4ic);
#endif

        icmp_hdr->chksum = 0;
        icmp_hdr->chksum = alg_iphdr_chksum((u16 *)icmp_hdr, ntohs(ip_hdr->_len) - iphdr_len);

        ip_hdr->src.addr = ip_addr_get_ip4_u32(gw_ip);
        ip_hdr->_chksum = 0;
        ip_hdr->_chksum = alg_iphdr_chksum((u16 *)ip_hdr, iphdr_len);

        return 0; // 已经改造完成, 可以返回了
    }
    else
    {
#ifdef NAPT_TABLE_MUTEX_LOCK
        luat_napt_lock(napt_table_lock_4ic);
#endif
        napt = luat_napt_get_by_dst_id(icmp_hdr->id);
        if (NULL != napt)
        {
            //luat_napt_table_update_4ic(napt);

            icmp_hdr->id = napt->src_id;
            icmp_hdr->chksum = 0;
            icmp_hdr->chksum = alg_iphdr_chksum((u16 *)icmp_hdr, ntohs(ip_hdr->_len) - iphdr_len);

            ip_hdr->dest.addr = ((napt->src_ip) << 24) | (ip_addr_get_ip4_u32(gw_ip) & 0x00ffffff);

#ifdef NAPT_TABLE_MUTEX_LOCK
            luat_napt_unlock(napt_table_lock_4ic);
#endif

            ip_hdr->_chksum = 0;
            ip_hdr->_chksum = alg_iphdr_chksum((u16 *)ip_hdr, iphdr_len);

            memcpy(ptr, napt->mac, 6);
            return 0; // 已经改造完成, 可以返回了
        }
        else
        {
#ifdef NAPT_TABLE_MUTEX_LOCK
            luat_napt_unlock(napt_table_lock_4ic);
#endif

        }
    }

    return -1;
}

static int alg_tcp_proc(u8 is_inet,
                        struct ip_hdr *ip_hdr,
                        ip_addr_t* gw_ip)
{
    int err;
    u8 src_ip;
    struct napt_addr_4tu *napt;
    struct tcp_hdr *tcp_hdr;
    u8* ptr = ((u8*)ip_hdr) - 14;
    u8 iphdr_len;

    iphdr_len = (ip_hdr->_v_hl & 0x0F) * 4;
    tcp_hdr = (struct tcp_hdr *)((u8 *)ip_hdr + iphdr_len);

    if (is_inet)
    {

#ifdef NAPT_TABLE_MUTEX_LOCK
        luat_napt_lock(napt_table_lock_4tcp);
#endif
        src_ip = ip_hdr->src.addr >> 24;
        napt = luat_napt_get_tcp_port_by_src(tcp_hdr->src, src_ip);
        if (NULL == napt)
        {
            napt = luat_napt_table_insert_4tcp(tcp_hdr->src, src_ip);
            if (NULL == napt)
            {
#ifdef NAPT_TABLE_MUTEX_LOCK
                luat_napt_unlock(napt_table_lock_4tcp);
#endif
                return -1;
            }
            // LLOGD("分配新的TCP映射 ip %d port %d -> %d", src_ip, tcp_hdr->src, napt->new_port);
        }
        else
        {
            luat_napt_table_update_4tcp(napt);
            // LLOGD("复用老的TCP映射 ip %d port %d -> %d", src_ip, tcp_hdr->src, napt->new_port);
        }
        memcpy(napt->mac, ptr + 6, 6); //保存源mac地址
        // LLOGD("记录内网-->外网的源MAC %02X%02X%02X%02X%02X%02X", napt->mac[0], napt->mac[1], napt->mac[2], napt->mac[3], napt->mac[4], napt->mac[5]);
        tcp_hdr->src = napt->new_port;
#ifdef NAPT_TABLE_MUTEX_LOCK
        luat_napt_unlock(napt_table_lock_4tcp);
#endif

        ip_hdr->src.addr = ip_addr_get_ip4_u32(gw_ip);
        ip_hdr->_chksum = 0;
        ip_hdr->_chksum = alg_iphdr_chksum((u16 *)ip_hdr, iphdr_len);

        tcp_hdr->chksum = 0;
        tcp_hdr->chksum = alg_tcpudphdr_chksum(ip_hdr->src.addr,
                                               ip_hdr->dest.addr,
                                               IP_PROTO_TCP,
                                               (u16 *)tcp_hdr,
                                               ntohs(ip_hdr->_len) - iphdr_len);

        return 0; 
    }
    /* from ap... */
    else
    {
#ifdef NAPT_TABLE_MUTEX_LOCK
        luat_napt_lock(napt_table_lock_4tcp);
#endif
        napt = luat_napt_get_tcp_port_by_dest(tcp_hdr->dest);
        /* forward to sta... */
        if (NULL != napt)
        {
            //luat_napt_table_update_4tcp(napt);

            ip_hdr->dest.addr = (napt->src_ip << 24) | (ip_addr_get_ip4_u32(gw_ip) & 0x00ffffff);
            ip_hdr->_chksum = 0;
            ip_hdr->_chksum = alg_iphdr_chksum((u16 *)ip_hdr, iphdr_len);

            tcp_hdr->dest = napt->src_port;

#ifdef NAPT_TABLE_MUTEX_LOCK
            luat_napt_unlock(napt_table_lock_4tcp);
#endif

            tcp_hdr->chksum = 0;
            tcp_hdr->chksum = alg_tcpudphdr_chksum(ip_hdr->src.addr,
                                                   ip_hdr->dest.addr,
                                                   IP_PROTO_TCP,
                                                   (u16 *)tcp_hdr,
                                                   ntohs(ip_hdr->_len) - iphdr_len);

            memcpy(ptr, napt->mac, 6); // 还原MAC地址
            return 0;
        }
        /* deliver to default gateway */
        else
        {
#ifdef NAPT_TABLE_MUTEX_LOCK
            luat_napt_unlock(napt_table_lock_4tcp);
#endif

        }
    }

    return -1;
}

static int alg_udp_proc(u8 is_inet,
                        struct ip_hdr *ip_hdr,
                        ip_addr_t* gw_ip)
{
    int err = 0;
    u8 src_ip;
    struct napt_addr_4tu *napt;
    struct udp_hdr *udp_hdr;
    u8* ptr = ((u8*)ip_hdr) - 14;
    u8 iphdr_len;

    iphdr_len = (ip_hdr->_v_hl & 0x0F) * 4;
    udp_hdr = (struct udp_hdr *)((u8 *)ip_hdr + iphdr_len);

    /* from sta... */
    if (is_inet)
    {
        /* create/update napt item */
#ifdef NAPT_TABLE_MUTEX_LOCK
        luat_napt_lock(napt_table_lock_4udp);
#endif
        src_ip = ip_hdr->src.addr >> 24;
        napt = luat_napt_get_udp_port_by_src(udp_hdr->src, src_ip);
        if (NULL == napt)
        {
            napt = luat_napt_table_insert_4udp(udp_hdr->src, src_ip);
            if (NULL == napt)
            {
#ifdef NAPT_TABLE_MUTEX_LOCK
                luat_napt_unlock(napt_table_lock_4udp);
#endif
                return -1;
            }
        }
        else
        {
            luat_napt_table_update_4udp(napt);
        }

        udp_hdr->src = napt->new_port;
        memcpy(napt->mac, ptr + 6, 6); // 拷贝源MAC地址

#ifdef NAPT_TABLE_MUTEX_LOCK
        luat_napt_unlock(napt_table_lock_4udp);
#endif

// redo:

        ip_hdr->src.addr = ip_addr_get_ip4_u32(gw_ip);
        ip_hdr->_chksum = 0;
        ip_hdr->_chksum = alg_iphdr_chksum((u16 *)ip_hdr, iphdr_len);

        if (0 != udp_hdr->chksum)
        {
            udp_hdr->chksum = 0;
            udp_hdr->chksum = alg_tcpudphdr_chksum(ip_hdr->src.addr,
                                                   ip_hdr->dest.addr,
                                                   IP_PROTO_UDP,
                                                   (u16 *)udp_hdr,
                                                   ntohs(ip_hdr->_len) - iphdr_len);
        }

        return 0;
    }
    /* form ap... */
    else
    {
#ifdef NAPT_TABLE_MUTEX_LOCK
        luat_napt_lock(napt_table_lock_4udp);
#endif
        napt = luat_napt_get_udp_port_by_dest(udp_hdr->dest);
        /* forward to sta... */
        if (NULL != napt)
        {
            luat_napt_table_update_4udp(napt);

            ip_hdr->dest.addr = (napt->src_ip << 24) | (ip_addr_get_ip4_u32(gw_ip) & 0x00ffffff);

            udp_hdr->dest = napt->src_port;

#ifdef NAPT_TABLE_MUTEX_LOCK
            luat_napt_unlock(napt_table_lock_4udp);
#endif

            ip_hdr->_chksum = 0;
            ip_hdr->_chksum = alg_iphdr_chksum((u16 *)ip_hdr, iphdr_len);

            if (0 != udp_hdr->chksum)
            {
                udp_hdr->chksum = 0;
                udp_hdr->chksum = alg_tcpudphdr_chksum(ip_hdr->src.addr,
                                                       ip_hdr->dest.addr,
                                                       IP_PROTO_UDP,
                                                       (u16 *)udp_hdr,
                                                       ntohs(ip_hdr->_len) - iphdr_len);
            }

            memcpy(ptr, napt->mac, 6);
            return 0;
        }
        /* deliver to default gateway */
        else
        {
#ifdef NAPT_TABLE_MUTEX_LOCK
            luat_napt_unlock(napt_table_lock_4udp);
#endif

        }
    }

// end:
    return -1;
}

static int alg_gre_proc(u8 is_inet, struct ip_hdr *ip_hdr, ip_addr_t* gw_ip)
{
    // int err;
    u8 src_ip;
    u8 iphdr_len;

    iphdr_len = (ip_hdr->_v_hl & 0x0F) * 4;

    /* from sta... */
    if (is_inet)
    {
        src_ip = ip_hdr->src.addr >> 24;

        if (src_ip == gre_info.src_ip)    /* current vpn */
        {
            gre_info.time_stamp++;
        }
        else if (1 == gre_info.is_used)/* vpn used */
        {
            return -1;
        }
        else                              /* new vpn */
        {
            gre_info.is_used = 1;
            gre_info.src_ip = src_ip;
            if (!++gre_info.time_stamp)
                gre_info.time_stamp++;
        }

        ip_hdr->src.addr = ip_addr_get_ip4_u32(gw_ip);
        ip_hdr->_chksum = 0;
        ip_hdr->_chksum = alg_iphdr_chksum((u16 *)ip_hdr, iphdr_len);

        return 0;
    }
    /* from ap... */
    else
    {
        ip_hdr->dest.addr = (gre_info.src_ip << 24) | (ip_addr_get_ip4_u32(gw_ip) & 0x00ffffff);
        ip_hdr->_chksum = 0;
        ip_hdr->_chksum = alg_iphdr_chksum((u16 *)ip_hdr, iphdr_len);

        return 0;
    }

}

int luat_napt_input(u8 is_inet, u8 *pkt_body, u32 pkt_len, ip_addr_t* gw_ip)
{
    int err = -1;
    struct ip_hdr *ip_hdr = NULL;

#ifdef NAPT_USE_HW_TIMER
    luat_napt_table_check_try();
#endif

    ip_hdr = (struct ip_hdr *)(pkt_body + 14);
    switch(ip_hdr->_proto)
    {
        case IP_PROTO_ICMP:
        {
            err = alg_icmp_proc(is_inet, ip_hdr, gw_ip);
            if (err)
                LLOGD("ICMP包 rc %d", err);
            break;
        }
        case IP_PROTO_TCP:
        {
            err = alg_tcp_proc(is_inet, ip_hdr, gw_ip);
            if (err)
                LLOGD("TCP包 rc %d", err);
            break;
        }
        case IP_PROTO_UDP:
        {
            err = alg_udp_proc(is_inet, ip_hdr, gw_ip);
            if (err)
                LLOGD("UDP包 rc %d", err);
            break;
        }
        case IP_PROTO_GRE:/* vpn */
        {
            err = alg_gre_proc(is_inet, ip_hdr, gw_ip);
            if (err)
                LLOGD("GRE包 rc %d", err);
            break;
        }
        default:
        {
            LLOGW("不认识的协议包 0x%02X", ip_hdr->_proto);
            err = -1;
            break;
        }
    }

    return err;
}

u8 luat_napt_port_is_used(u16 port)
{
    u8 is_used = 0;
    struct napt_addr_4tu *napt_tcp;
    struct napt_addr_4tu *napt_udp;

#ifdef NAPT_TABLE_MUTEX_LOCK
    luat_napt_lock(napt_table_lock_4tcp);
#endif
    NAPT_TABLE_FOREACH(napt_tcp, napt_table_4tcp)
    {
        if (port == napt_tcp->new_port)
        {
            is_used = 1;
            break;
        }
    }
#ifdef NAPT_TABLE_MUTEX_LOCK
    luat_napt_unlock(napt_table_lock_4tcp);
#endif

    if (1 != is_used)
    {
#ifdef NAPT_TABLE_MUTEX_LOCK
        luat_napt_lock(napt_table_lock_4udp);
#endif
        NAPT_TABLE_FOREACH(napt_udp, napt_table_4udp)
        {
            if (port == napt_udp->new_port)
            {
                is_used = 1;
                break;
            }
        }
#ifdef NAPT_TABLE_MUTEX_LOCK
        luat_napt_unlock(napt_table_lock_4udp);
#endif
    }

    return is_used;
}

int luat_napt_init(void)
{
    int err = 0;
#ifdef NAPT_USE_HW_TIMER
    struct tls_timer_cfg timer_cfg;
#endif

    memset(&napt_table_4tcp, 0, sizeof(struct napt_table_head_4tu));
    memset(&napt_table_4udp, 0, sizeof(struct napt_table_head_4tu));
    memset(&napt_table_4ic, 0, sizeof(struct napt_table_head_4ic));

    napt_curr_port = NAPT_LOCAL_PORT_RANGE_START;
    napt_curr_id   = NAPT_ICMP_ID_RANGE_START;

#ifdef NAPT_TABLE_MUTEX_LOCK
    err = tls_os_sem_create(&napt_table_lock_4tcp, 1);
    if (TLS_OS_SUCCESS != err)
    {
        NAPT_PRINT("failed to init alg.\n");
        return err;
    }

    err = tls_os_sem_create(&napt_table_lock_4udp, 1);
    if (TLS_OS_SUCCESS != err)
    {
        NAPT_PRINT("failed to init alg.\n");
        return err;
    }

    err = tls_os_sem_create(&napt_table_lock_4ic, 1);
    if (TLS_OS_SUCCESS != err)
    {
        NAPT_PRINT("failed to init alg.\n");
    }
#endif

#ifdef NAPT_ALLOC_DEBUG
    napt4ic_cnt = 0;
    napt4tcp_cnt = 0;
    napt4udp_cnt = 0;
#endif

#ifdef NAPT_USE_HW_TIMER
    memset(&timer_cfg, 0, sizeof(timer_cfg));
    timer_cfg.unit = TLS_TIMER_UNIT_MS;
    timer_cfg.timeout = NAPT_TMR_INTERVAL;
    timer_cfg.is_repeat = TRUE;
    timer_cfg.callback = luat_napt_table_check;
    err = tls_timer_create(&timer_cfg);
    if (WM_TIMER_ID_INVALID != err)
    {
        tls_timer_start(err);
        err = 0;
    }
    else
    {
        NAPT_PRINT("failed to init alg timer.\n");
    }
#else

#endif

    return err;
}

