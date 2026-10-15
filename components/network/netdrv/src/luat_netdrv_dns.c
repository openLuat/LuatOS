/*
 * luat_netdrv_dns.c
 *
 * netdrv 现代 DNS 客户端实现.
 *
 * 设计约束见同目录头文件 luat_netdrv_dns.h 顶部的说明:
 *   - 不调用任何 lwIP API, 收发由 net_lwip2.c 负责
 *   - 全部状态只在 tcpip 线程内访问, 内部不加锁
 *   - 报文解析的任何一次读取前都必须做边界检查
 */

#include "luat_netdrv_dns.h"
/*
 * 本文件刻意不包含 c_common.h: 它与各芯片 SDK 的 bsp_common.h 重复定义了一批类型,
 * 而本模块的头又会被两类编译单元包含, 详见 luat_netdrv_dns.h 顶部说明.
 * 需要的东西(memcpy/memset 来自 luat_base.h 已经带入的 string.h)都不依赖它.
 */

#ifdef LUAT_USE_NETDRV_DNS_CLIENT

#include "luat_mcu.h"
#include "luat_malloc.h"
#include "luat_crypto.h"

#define LUAT_LOG_TAG "netdrv.dns"
#include "luat_log.h"

/* ===================================================================== */
/* 私有双向链表                                                          */
/* ===================================================================== */

/*
 * 与 linux 内核 llist 同语义的一组最小操作.
 * 之所以不复用 c_common.h 的 llist: 见本文件顶部说明, 类型名会与 SDK 头撞名.
 * 链表都是模块私有的, 这里实现够用即可(只用到 init/add_tail/del/empty/num).
 */
static void dns_node_init(luat_netdrv_dns_node_t *node)
{
	node->next = node;
	node->prev = node;
}

static void dns_node_add_tail(luat_netdrv_dns_node_t *node, luat_netdrv_dns_node_t *head)
{
	node->next = head;
	node->prev = head->prev;
	head->prev->next = node;
	head->prev = node;
}

static void dns_node_del(luat_netdrv_dns_node_t *node)
{
	node->prev->next = node->next;
	node->next->prev = node->prev;
	node->next = node;
	node->prev = node;
}

static uint32_t dns_list_num(const luat_netdrv_dns_node_t *head)
{
	uint32_t n = 0;
	const luat_netdrv_dns_node_t *p;
	for (p = head->next; p != head; p = p->next)
	{
		n++;
	}
	return n;
}

static uint8_t dns_list_empty(const luat_netdrv_dns_node_t *head)
{
	return head->next == head ? 1 : 0;
}

#define DNS_LOGD	LLOGD
#define DNS_LOGI	LLOGI
#define DNS_LOGE	LLOGE
#define DNS_LOGW	LLOGW

#define DNS_HDR_LEN			12
#define DNS_CLASS_IN			1
#define DNS_MAX_LABEL			63
#define DNS_MAX_WIRE_NAME		255
#define DNS_MAX_JUMP			8		/* 压缩指针跳转次数上限, 防环 */
#define DNS_COMPRESS_FLAG		0xC0
#define DNS_RCODE_MASK			0x000F
#define DNS_RCODE_NXDOMAIN		3

/* 换服务器后的额外等待, 避免连续打同一台 */
#define DNS_SERVER_SWITCH_GAP_MS	20
/* 发送失败后的短退避, 不消耗重试次数 */
#define DNS_SEND_ERR_GAP_MS		50
/*
 * 无符号时间比较. 差值按 int32 解释即可正确处理 49 天回绕:
 *   now == deadline  -> 差值 0    -> REACHED 为真(到期时刻一到就生效)
 *   now == deadline+1-> 差值 1    -> REACHED 为真
 *   now == deadline-1-> 差值 -1   -> BEFORE 为真(还没到)
 * 注意不能用 (uint32)(now-deadline) >= 0x80000000 判断"已到期":
 * 那表示"已经过去半个取值空间", 会导致时间点正好落在 deadline 上时判成未到期,
 * 表现为查询永远发不出去 / 超时永远不触发.
 */
#define DNS_TIME_REACHED(now, deadline) \
	((int32_t)((uint32_t)(now) - (uint32_t)(deadline)) >= 0)
#define DNS_TIME_BEFORE(now, deadline) \
	((int32_t)((uint32_t)(now) - (uint32_t)(deadline)) < 0)

/* ===================================================================== */
/* 小工具                                                                */
/* ===================================================================== */

static inline uint8_t dns_lower(uint8_t c)
{
	return (c >= 'A' && c <= 'Z') ? (uint8_t)(c + 32) : c;
}

/* 大小写不敏感的域名比较 */
static int dns_name_cmp(const uint8_t *a, uint32_t alen, const uint8_t *b, uint32_t blen)
{
	uint32_t i;
	if (a == NULL || b == NULL || alen != blen)
	{
		return -1;
	}
	for (i = 0; i < alen; i++)
	{
		if (dns_lower(a[i]) != dns_lower(b[i]))
		{
			return -1;
		}
	}
	return 0;
}

/*
 * 域名合法性校验. 规则与旧 dns_client.c 的 dns_check_uri 保持一致:
 * 长度 1~255, 首字符为字母, 末字符为字母或数字,
 * 只允许 alnum/'.'/'-', 每个 label 1~63 字符, 至少含一个 '.'.
 */
static int dns_name_valid(const uint8_t *name, uint32_t len)
{
	uint32_t i, label_len = 0, dot_num = 0;
	uint8_t c;

	if (name == NULL || len == 0 || len > DNS_MAX_WIRE_NAME)
	{
		return -1;
	}
	c = name[0];
	if (!((c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z')))
	{
		return -1;
	}
	c = name[len - 1];
	if (!((c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') ||
		  (c >= '0' && c <= '9')))
	{
		return -1;
	}
	for (i = 0; i < len; i++)
	{
		c = name[i];
		if (!((c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') ||
			  (c >= '0' && c <= '9') || c == '.' || c == '-'))
		{
			return -1;
		}
		if (c == '.')
		{
			dot_num++;
			if (label_len == 0 || label_len > DNS_MAX_LABEL)
			{
				return -1;
			}
			label_len = 0;
		}
		else
		{
			label_len++;
		}
	}
	if (dot_num == 0 || label_len == 0 || label_len > DNS_MAX_LABEL)
	{
		return -1;
	}
	return 0;
}

/* 取 [0, range) 内的随机数, 用于退避抖动. TRNG 不可用时退化为 0. */
static uint32_t dns_rand(uint32_t range)
{
	uint32_t v = 0;
	if (range == 0)
	{
		return 0;
	}
	if (luat_crypto_trng((char *)&v, sizeof(v)) != 0)
	{
		return 0;
	}
	return v % range;
}

/* ===================================================================== */
/* 报文构造                                                              */
/* ===================================================================== */

/*
 * 构造标准查询报文. RD=1, opcode=0, 单 question, QDCOUNT=1.
 * @return 报文长度; < 0 失败(域名非法或空间不足)
 */
static int dns_make_query(uint8_t *out, uint32_t cap, uint16_t txid,
		const uint8_t *name, uint32_t name_len, uint16_t qtype)
{
	uint32_t i, p = DNS_HDR_LEN, lstart, llen;

	if (dns_name_valid(name, name_len) != 0)
	{
		return -1;
	}
	if (cap < DNS_HDR_LEN + 6)
	{
		return -1;
	}

	/* 头部 */
	out[0] = (uint8_t)(txid >> 8);
	out[1] = (uint8_t)(txid & 0xFF);
	out[2] = 0x01;					/* QR=0, OPCODE=0, AA=0, TC=0, RD=1 */
	out[3] = 0x00;
	out[4] = 0x00;
	out[5] = 0x01;					/* QDCOUNT = 1 */
	out[6] = 0x00;
	out[7] = 0x00;
	out[8] = 0x00;
	out[9] = 0x00;					/* ANCOUNT */
	out[10] = 0x00;
	out[11] = 0x00;					/* NSCOUNT/ARCOUNT */

	/* QNAME: 点分串 -> label 长度前缀序列 */
	i = 0;
	while (i < name_len)
	{
		lstart = i;
		while (i < name_len && name[i] != '.')
		{
			i++;
		}
		llen = i - lstart;
		if (llen == 0 || llen > DNS_MAX_LABEL)
		{
			return -1;
		}
		if (p + 1 + llen + 1 + 4 > cap)
		{
			return -1;
		}
		out[p++] = (uint8_t)llen;
		memcpy(out + p, name + lstart, llen);
		p += llen;
		if (i < name_len)
		{
			i++;				/* 跳过 '.' */
		}
	}
	out[p++] = 0x00;				/* 名字结束 */

	/* QTYPE + QCLASS */
	out[p++] = (uint8_t)(qtype >> 8);
	out[p++] = (uint8_t)(qtype & 0xFF);
	out[p++] = (uint8_t)(DNS_CLASS_IN >> 8);
	out[p++] = (uint8_t)(DNS_CLASS_IN & 0xFF);
	return (int)p;
}

/* ===================================================================== */
/* 报文解析                                                              */
/* ===================================================================== */

typedef struct
{
	const uint8_t *data;
	uint32_t len;
	uint32_t pos;
}dns_rd_t;

static int dns_rd_be16(dns_rd_t *r, uint16_t *v)
{
	if (r->pos + 2 > r->len)
	{
		return -1;
	}
	*v = (uint16_t)(((uint16_t)r->data[r->pos] << 8) | r->data[r->pos + 1]);
	r->pos += 2;
	return 0;
}

static int dns_rd_be32(dns_rd_t *r, uint32_t *v)
{
	if (r->pos + 4 > r->len)
	{
		return -1;
	}
	*v = ((uint32_t)r->data[r->pos] << 24) | ((uint32_t)r->data[r->pos + 1] << 16) |
		((uint32_t)r->data[r->pos + 2] << 8) | (uint32_t)r->data[r->pos + 3];
	r->pos += 4;
	return 0;
}

/*
 * 跳过一段域名(可能是压缩指针形式), 把读指针留在报文中的"下一个字段"上.
 * 压缩指针只允许回指(offset < 当前 pos), 跳转次数有上限, 防止构造出环.
 */
static int dns_skip_name(dns_rd_t *r)
{
	uint32_t after = 0;
	uint32_t jumps = 0;
	int jumped = 0;
	uint8_t c;

	for (;;)
	{
		if (r->pos >= r->len)
		{
			return -1;
		}
		c = r->data[r->pos];
		if ((c & DNS_COMPRESS_FLAG) == DNS_COMPRESS_FLAG)
		{
			uint16_t off;
			if (r->pos + 2 > r->len)
			{
				return -1;
			}
			off = (uint16_t)(((uint16_t)(c & 0x3F) << 8) | r->data[r->pos + 1]);
			if (!jumped)
			{
				after = r->pos + 2;
				jumped = 1;
			}
			if (off >= r->pos || ++jumps > DNS_MAX_JUMP)
			{
				return -1;		/* 前向指针或成环, 判定为恶意/损坏 */
			}
			r->pos = off;
			continue;
		}
		if (c & 0xC0)
		{
			return -1;			/* 保留位非零 */
		}
		if (c == 0x00)
		{
			if (!jumped)
			{
				after = r->pos + 1;
			}
			break;
		}
		if (c > DNS_MAX_LABEL || r->pos + 1 + c > r->len)
		{
			return -1;
		}
		r->pos += 1 + c;
	}
	r->pos = after;
	return 0;
}

/*
 * 读取一段域名并与期望域名逐 label 比较(大小写不敏感, 支持压缩指针).
 * 匹配则消耗该域名并把读指针留在报文中的下一个字段; 不匹配返回非 0.
 */
static int dns_name_match(dns_rd_t *r, const uint8_t *name, uint32_t name_len)
{
	uint32_t after = 0;
	uint32_t jumps = 0;
	uint32_t i = 0;
	int jumped = 0;
	uint8_t c;

	for (;;)
	{
		if (r->pos >= r->len)
		{
			return -1;
		}
		c = r->data[r->pos];
		if ((c & DNS_COMPRESS_FLAG) == DNS_COMPRESS_FLAG)
		{
			uint16_t off;
			if (r->pos + 2 > r->len)
			{
				return -1;
			}
			off = (uint16_t)(((uint16_t)(c & 0x3F) << 8) | r->data[r->pos + 1]);
			if (!jumped)
			{
				after = r->pos + 2;
				jumped = 1;
			}
			if (off >= r->pos || ++jumps > DNS_MAX_JUMP)
			{
				return -1;
			}
			r->pos = off;
			continue;
		}
		if (c & 0xC0)
		{
			return -1;
		}
		if (c == 0x00)
		{
			if (!jumped)
			{
				after = r->pos + 1;
			}
			break;
		}
		if (c > DNS_MAX_LABEL || r->pos + 1 + c > r->len)
		{
			return -1;
		}
		/* 逐字节比较当前 label 与域名中对应部分 */
		for (uint8_t j = 0; j < c; j++)
		{
			if (i >= name_len)
			{
				return -1;
			}
			if (dns_lower(r->data[r->pos + 1 + j]) != dns_lower(name[i]))
			{
				return -1;
			}
			i++;
		}
		r->pos += 1 + c;
		/* label 之间域名里应是 '.' */
		if (i < name_len)
		{
			if (name[i] != '.')
			{
				return -1;
			}
			i++;
			if (i >= name_len)
			{
				return -1;	/* 域名不能以 '.' 结尾 */
			}
		}
	}
	if (i != name_len)
	{
		return -1;
	}
	r->pos = after;
	return 0;
}

/*
 * 把 4/16 字节原始地址写进 luat_ip_addr_t.
 *
 * 注意: lwIP 的 ip4_addr.addr 以【网络字节序】存放. 旧实现用 BytesGetLe32 取值,
 * 那只在小端平台上正确(大端会得到反序地址). 这里直接 memcpy 原始字节, 与字节序无关.
 */
static void dns_ip_from_a(luat_ip_addr_t *ip, const uint8_t *raw)
{
	memset(ip, 0, sizeof(*ip));
#ifdef LUAT_USE_LWIP
#if LWIP_IPV6
	ip->type = IPADDR_TYPE_V4;
	memcpy(&ip->u_addr.ip4.addr, raw, 4);
#else
	memcpy(&ip->addr, raw, 4);
#endif
#else
	memcpy(&ip->ipv4, raw, 4);
#endif
}

static void dns_ip_from_aaaa(luat_ip_addr_t *ip, const uint8_t *raw)
{
	memset(ip, 0, sizeof(*ip));
#ifdef LUAT_USE_LWIP
#if LWIP_IPV6
	ip->type = IPADDR_TYPE_V6;
	memcpy(ip->u_addr.ip6.addr, raw, 16);
	/* zone 已在上面的 memset 中清零 */
#else
	/* 构建未开启 IPv6, 无法表达 AAAA 结果 */
#endif
#else
	ip->is_ipv6 = 1;
	memcpy(ip->ipv6_u8_addr, raw, 16);
#endif
}

/* 当前构建能否表达 AAAA 结果 */
static int dns_can_ipv6(void)
{
#ifdef LUAT_USE_LWIP
#if LWIP_IPV6
	return 1;
#else
	return 0;
#endif
#else
	return 1;
#endif
}

/*
 * 遍历一段 RR 区里的前 count 条记录.
 * 必须显式传条数: 报文里没有"记录区结束标记", 读到读不动为止只会跑到
 * 报文末尾并因越界返回失败, 那是把"刚好用完"误判成"结构非法".
 * @param want_qtype 只提取该类型的记录; 传 0 表示"纯结构校验模式", 不提取任何记录
 * @return 0 成功; -1 报文结构非法
 */
static int dns_parse_rrs(dns_rd_t *r, uint16_t count, uint16_t want_qtype, int ipv6_allowed,
		luat_dns_ip_result *out, uint8_t cap, uint8_t *out_num, uint32_t *min_ttl)
{
	uint16_t type, cls, rdlen;
	uint32_t ttl;
	uint16_t i;

	for (i = 0; i < count; i++)
	{
		if (dns_skip_name(r) != 0)
		{
			return -1;
		}
		/* type(2) + class(2) + ttl(4) + rdlength(2) */
		if (r->pos + 10 > r->len)
		{
			return -1;
		}
		if (dns_rd_be16(r, &type) != 0 || dns_rd_be16(r, &cls) != 0 ||
			dns_rd_be32(r, &ttl) != 0 || dns_rd_be16(r, &rdlen) != 0)
		{
			return -1;
		}
		if (r->pos + rdlen > r->len)
		{
			return -1;
		}

		if (want_qtype != 0 && cls == DNS_CLASS_IN && *out_num < cap)
		{
			if (want_qtype == LUAT_NETDRV_DNS_TYPE_A && type == LUAT_NETDRV_DNS_TYPE_A &&
				rdlen == 4)
			{
				dns_ip_from_a(&out[*out_num].ip, r->data + r->pos);
				out[*out_num].ttl_end = ttl;	/* 原始 TTL, 绝对化在写缓存时做 */
				(*out_num)++;
				if (ttl < *min_ttl)
				{
					*min_ttl = ttl;
				}
			}
			else if (want_qtype == LUAT_NETDRV_DNS_TYPE_AAAA &&
				type == LUAT_NETDRV_DNS_TYPE_AAAA && rdlen == 16 && ipv6_allowed)
			{
				dns_ip_from_aaaa(&out[*out_num].ip, r->data + r->pos);
				out[*out_num].ttl_end = ttl;
				(*out_num)++;
				if (ttl < *min_ttl)
				{
					*min_ttl = ttl;
				}
			}
		}
		r->pos += rdlen;
	}
	return 0;
}

/* ===================================================================== */
/* 缓存                                                                  */
/* ===================================================================== */

static luat_netdrv_dns_cache_ent_t *dns_cache_find(luat_netdrv_dns_ctx_t *ctx,
		const uint8_t *name, uint32_t name_len, uint16_t qtype)
{
	luat_netdrv_dns_node_t *node;
	for (node = ctx->cache_head.next; node != &ctx->cache_head; node = node->next)
	{
		luat_netdrv_dns_cache_ent_t *ent = LUAT_NETDRV_DNS_ENTRY(node, luat_netdrv_dns_cache_ent_t, node);
		if (ent->qtype == qtype && dns_name_cmp(ent->name, ent->name_len, name, name_len) == 0)
		{
			return ent;
		}
	}
	return NULL;
}

static void dns_cache_unlink(luat_netdrv_dns_cache_ent_t *ent)
{
	dns_node_del(&ent->node);
	luat_heap_free(ent);
}

static void dns_cache_count_update(luat_netdrv_dns_ctx_t *ctx)
{
	ctx->stat.cache_used = (uint16_t)dns_list_num(&ctx->cache_head);
}

void luat_netdrv_dns_cache_flush(luat_netdrv_dns_ctx_t *ctx)
{
	if (ctx == NULL)
	{
		return;
	}
	while (!dns_list_empty(&ctx->cache_head))
	{
		luat_netdrv_dns_cache_ent_t *ent =
			LUAT_NETDRV_DNS_ENTRY(ctx->cache_head.next, luat_netdrv_dns_cache_ent_t, node);
		dns_cache_unlink(ent);
	}
	dns_cache_count_update(ctx);
}

/* 清理过期条目 */
static void dns_cache_gc(luat_netdrv_dns_ctx_t *ctx, uint32_t now)
{
	luat_netdrv_dns_node_t *node, *next;
	for (node = ctx->cache_head.next; node != &ctx->cache_head; node = next)
	{
		luat_netdrv_dns_cache_ent_t *ent = LUAT_NETDRV_DNS_ENTRY(node, luat_netdrv_dns_cache_ent_t, node);
		next = node->next;
		if (DNS_TIME_REACHED(now, ent->expire_ms))
		{
			dns_cache_unlink(ent);
		}
	}
	dns_cache_count_update(ctx);
}

static void dns_cache_store(luat_netdrv_dns_ctx_t *ctx, const uint8_t *name, uint32_t name_len,
		uint16_t qtype, const luat_dns_ip_result *ip, uint8_t ip_num, uint32_t min_ttl_ms,
		uint8_t is_negative, uint32_t now)
{
	luat_netdrv_dns_cache_ent_t *ent;
	uint32_t ttl;

	if (!ctx->cfg.cache_enable || ctx->cfg.cache_num == 0)
	{
		return;
	}
	/*
	 * 负缓存用 neg_ttl_ms; 正缓存用 min(记录 TTL, 上限).
	 * min_ttl_ms == 0 表示所有记录 TTL 都是 0, 按口径不缓存.
	 */
	if (is_negative)
	{
		if (ctx->cfg.neg_ttl_ms == 0)
		{
			return;
		}
		ttl = ctx->cfg.neg_ttl_ms;
	}
	else
	{
		if (ip_num == 0 || min_ttl_ms == 0)
		{
			return;
		}
		ttl = min_ttl_ms;
		if (ctx->cfg.cache_ttl_ms && ttl > ctx->cfg.cache_ttl_ms)
		{
			ttl = ctx->cfg.cache_ttl_ms;
		}
		if (ttl == 0)
		{
			return;
		}
	}

	ent = dns_cache_find(ctx, name, name_len, qtype);
	if (ent == NULL)
	{
		/* 超上限时按 LRU 淘汰队首 */
		while (dns_list_num(&ctx->cache_head) >= ctx->cfg.cache_num)
		{
			luat_netdrv_dns_cache_ent_t *victim =
				LUAT_NETDRV_DNS_ENTRY(ctx->cache_head.next, luat_netdrv_dns_cache_ent_t, node);
			dns_cache_unlink(victim);
			ctx->stat.evict++;
		}
		ent = luat_heap_zalloc(sizeof(luat_netdrv_dns_cache_ent_t));
		if (ent == NULL)
		{
			DNS_LOGE("cache entry alloc failed");
			return;
		}
		dns_node_init(&ent->node);
		ent->name_len = (uint8_t)name_len;
		memcpy(ent->name, name, name_len);
		ent->qtype = qtype;
		dns_node_add_tail(&ent->node, &ctx->cache_head);
	}
	else
	{
		/* 命中同一条目: 移到队尾刷新 LRU 位置 */
		dns_node_del(&ent->node);
		dns_node_add_tail(&ent->node, &ctx->cache_head);
		ent->hit = 0;
	}

	ent->ip_num = ip_num;
	if (ip_num && ip)
	{
		uint32_t now_s = now / 1000;
		memcpy(ent->ip, ip, sizeof(luat_dns_ip_result) * ip_num);
		/* 对外暴露的 ttl_end 沿用旧实现语义: 当前秒 + TTL */
		for (uint8_t i = 0; i < ip_num; i++)
		{
			ent->ip[i].ttl_end = now_s + (ttl / 1000);
		}
	}
	ent->expire_ms = now + ttl;
	ent->is_negative = is_negative;
	dns_cache_count_update(ctx);
}

/* ===================================================================== */
/* 请求 / 事务                                                           */
/* ===================================================================== */

static void dns_waiter_free(luat_netdrv_dns_waiter_t *w)
{
	dns_node_del(&w->node);
	luat_heap_free(w);
}

static luat_netdrv_dns_waiter_t *dns_waiter_new(void *param, uint8_t adapter_index)
{
	luat_netdrv_dns_waiter_t *w = luat_heap_zalloc(sizeof(luat_netdrv_dns_waiter_t));
	if (w == NULL)
	{
		return NULL;
	}
	dns_node_init(&w->node);
	w->param = param;
	w->adapter_index = adapter_index;
	return w;
}

/* 把 src 上已收集的结果与等待者并入 dst, 然后释放 src */
static void dns_req_absorb(luat_netdrv_dns_req_t *dst, luat_netdrv_dns_req_t *src)
{
	uint8_t i;
	if (dst == src)
	{
		return;		/* 防御: 理论上不会发生 */
	}
	for (i = 0; i < src->ip_num && dst->ip_num < LUAT_NETDRV_DNS_MAX_RR; i++)
	{
		uint8_t dup = 0;
		uint8_t j;
		for (j = 0; j < dst->ip_num; j++)
		{
			if (memcmp(&dst->ip[j].ip, &src->ip[i].ip, sizeof(luat_ip_addr_t)) == 0)
			{
				dup = 1;
				break;
			}
		}
		if (!dup)
		{
			dst->ip[dst->ip_num++] = src->ip[i];
		}
	}
	while (!dns_list_empty(&src->waiter_head))
	{
		luat_netdrv_dns_waiter_t *w =
			LUAT_NETDRV_DNS_ENTRY(src->waiter_head.next, luat_netdrv_dns_waiter_t, node);
		dns_node_del(&w->node);
		dns_node_add_tail(&w->node, &dst->waiter_head);
	}
	dst->leg_done = (uint8_t)(dst->leg_done + src->leg_done);
	dns_node_del(&src->node);
	luat_heap_free(src);
}

/* 结果去重后并入 req */
static void dns_req_add_ip(luat_netdrv_dns_req_t *req, const luat_dns_ip_result *ip, uint8_t num)
{
	for (uint8_t i = 0; i < num; i++)
	{
		uint8_t dup = 0;
		if (req->ip_num >= LUAT_NETDRV_DNS_MAX_RR)
		{
			return;
		}
		for (uint8_t j = 0; j < req->ip_num; j++)
		{
			if (memcmp(&req->ip[j].ip, &ip[i].ip, sizeof(luat_ip_addr_t)) == 0)
			{
				dup = 1;
				break;
			}
		}
		if (!dup)
		{
			req->ip[req->ip_num++] = ip[i];
		}
	}
}

/* 通知所有等待者并释放整个 req */
static void dns_req_finish(luat_netdrv_dns_ctx_t *ctx, luat_netdrv_dns_req_t *req)
{
	if (req->notified)
	{
		return;
	}
	req->notified = 1;

	while (!dns_list_empty(&req->waiter_head))
	{
		luat_netdrv_dns_waiter_t *w =
			LUAT_NETDRV_DNS_ENTRY(req->waiter_head.next, luat_netdrv_dns_waiter_t, node);
		luat_dns_ip_result *copy = NULL;
		uint8_t n = 0;
		if (req->ip_num)
		{
			copy = luat_heap_zalloc(sizeof(luat_dns_ip_result) * req->ip_num);
			if (copy)
			{
				memcpy(copy, req->ip, sizeof(luat_dns_ip_result) * req->ip_num);
				n = req->ip_num;
			}
		}
		if (ctx->done_cb)
		{
			/* ip 的所有权转移给回调方, 与 EV_NW_DNS_RESULT 的既有约定一致 */
			ctx->done_cb(ctx->done_user, w->param, w->adapter_index, n, copy);
		}
		else if (copy)
		{
			luat_heap_free(copy);
		}
		dns_waiter_free(w);
	}
	dns_node_del(&req->node);
	luat_heap_free(req);
}

/* req 全部腿进入终态则通知 */
static void dns_req_check_done(luat_netdrv_dns_ctx_t *ctx, luat_netdrv_dns_req_t *req)
{
	if (req->notified || req->leg_done < req->leg_total)
	{
		return;
	}
	dns_req_finish(ctx, req);
}

/*
 * 把一条腿标记为终态并释放事务.
 * 注意 req 指针必须在释放 txn 之前取出 —— txn 一旦释放就读不到了.
 */
static void dns_leg_finish(luat_netdrv_dns_ctx_t *ctx, luat_netdrv_dns_txn_t *txn)
{
	luat_netdrv_dns_req_t *req = txn->req;
	uint8_t need_check;

	if (txn->done)
	{
		return;
	}
	txn->done = 1;
	need_check = (req != NULL && !req->notified);
	if (need_check)
	{
		req->leg_done++;
	}
	dns_node_del(&txn->node);
	luat_heap_free(txn);
	if (need_check)
	{
		dns_req_check_done(ctx, req);
	}
}

static luat_netdrv_dns_txn_t *dns_txn_find(luat_netdrv_dns_ctx_t *ctx,
		const uint8_t *name, uint32_t name_len, uint16_t qtype)
{
	luat_netdrv_dns_node_t *node;
	for (node = ctx->txn_head.next; node != &ctx->txn_head; node = node->next)
	{
		luat_netdrv_dns_txn_t *txn = LUAT_NETDRV_DNS_ENTRY(node, luat_netdrv_dns_txn_t, node);
		if (!txn->done && txn->qtype == qtype &&
			dns_name_cmp(txn->name, txn->name_len, name, name_len) == 0)
		{
			return txn;
		}
	}
	return NULL;
}

static luat_netdrv_dns_txn_t *dns_txn_find_by_txid(luat_netdrv_dns_ctx_t *ctx, uint16_t txid)
{
	luat_netdrv_dns_node_t *node;
	for (node = ctx->txn_head.next; node != &ctx->txn_head; node = node->next)
	{
		luat_netdrv_dns_txn_t *txn = LUAT_NETDRV_DNS_ENTRY(node, luat_netdrv_dns_txn_t, node);
		if (!txn->done && txn->txid == txid)
		{
			return txn;
		}
	}
	return NULL;
}

static int dns_server_valid(luat_netdrv_dns_server_cb cb, void *user,
		uint8_t adapter_index, uint8_t server_idx, luat_ip_addr_t *ip)
{
	luat_ip_addr_t tmp;
	if (ip == NULL)
	{
		ip = &tmp;
	}
	memset(ip, 0, sizeof(*ip));
	if (cb == NULL || cb(adapter_index, server_idx, ip, user) == 0)
	{
		return 0;
	}
	return network_ip_is_vaild(ip);
}

/*
 * 把 txn 的 server_idx 推进到下一台可用服务器.
 * @return 1 找到; 0 全部服务器都不可用(server_idx 被标记为 MAX_DNS_SERVER)
 */
static int dns_server_advance(luat_netdrv_dns_txn_t *txn, luat_netdrv_dns_server_cb cb, void *user)
{
	for (uint8_t i = 0; i < MAX_DNS_SERVER; i++)
	{
		txn->server_idx = (uint8_t)((txn->server_idx + 1) % MAX_DNS_SERVER);
		if (dns_server_valid(cb, user, txn->adapter_index, txn->server_idx, NULL))
		{
			return 1;
		}
	}
	txn->server_idx = MAX_DNS_SERVER;
	return 0;
}

/* 为某条腿挑选初始服务器: 从轮转游标开始找第一台可用服务器 */
static void dns_server_pick(luat_netdrv_dns_ctx_t *ctx, luat_netdrv_dns_txn_t *txn,
		luat_netdrv_dns_server_cb cb, void *user)
{
	txn->server_idx = MAX_DNS_SERVER;
	for (uint8_t i = 0; i < MAX_DNS_SERVER; i++)
	{
		uint8_t idx = (uint8_t)((ctx->rr_server + i) % MAX_DNS_SERVER);
		if (dns_server_valid(cb, user, txn->adapter_index, idx, NULL))
		{
			txn->server_idx = idx;
			ctx->rr_server = (uint8_t)((idx + 1) % MAX_DNS_SERVER);
			return;
		}
	}
}

/* 退避: timeout << retry, 上限 timeout*4, 叠加 0~25% 抖动 */
static uint32_t dns_backoff_ms(const luat_netdrv_dns_cfg_t *cfg, uint8_t retry)
{
	uint32_t base = (uint32_t)cfg->query_timeout_ms << (retry > 4 ? 4 : retry);
	uint32_t cap = (uint32_t)cfg->query_timeout_ms * 4;
	if (base > cap)
	{
		base = cap;
	}
	return base + (base * dns_rand(26)) / 100;
}

/* ===================================================================== */
/* 生命周期                                                              */
/* ===================================================================== */

int luat_netdrv_dns_init(luat_netdrv_dns_ctx_t *ctx)
{
	if (ctx == NULL)
	{
		return -1;
	}
	memset(ctx, 0, sizeof(*ctx));
	dns_node_init(&ctx->cache_head);
	dns_node_init(&ctx->txn_head);
	dns_node_init(&ctx->req_head);

	ctx->cfg.cache_enable = 1;
	ctx->cfg.cache_num = LUAT_NETDRV_DNS_DEF_CACHE_NUM;
	ctx->cfg.cache_ttl_ms = LUAT_NETDRV_DNS_DEF_CACHE_TTL_MS;
	ctx->cfg.neg_ttl_ms = LUAT_NETDRV_DNS_DEF_NEG_TTL_MS;
	ctx->cfg.max_inflight = LUAT_NETDRV_DNS_DEF_MAX_INFLIGHT;
	ctx->cfg.max_retry = LUAT_NETDRV_DNS_DEF_MAX_RETRY;
	ctx->cfg.query_timeout_ms = LUAT_NETDRV_DNS_DEF_TIMEOUT_MS;
	ctx->cfg.min_gap_ms = LUAT_NETDRV_DNS_DEF_MIN_GAP_MS;

	/* txid 随机起点, 避免跨会话可预测(RFC 5452), 之后仍递增防同 ctx 内重复 */
	luat_crypto_trng((char *)&ctx->txid_seq, sizeof(ctx->txid_seq));
	if (ctx->txid_seq == 0)
	{
		ctx->txid_seq = 1;
	}
	ctx->token = LUAT_NETDRV_DNS_DEF_MAX_INFLIGHT;
	ctx->rr_server = 0;
	ctx->inited = 1;
	return 0;
}

void luat_netdrv_dns_set_done_cb(luat_netdrv_dns_ctx_t *ctx, luat_netdrv_dns_done_cb cb, void *user)
{
	if (ctx)
	{
		ctx->done_cb = cb;
		ctx->done_user = user;
	}
}

void luat_netdrv_dns_set_server_cb(luat_netdrv_dns_ctx_t *ctx, luat_netdrv_dns_server_cb cb, void *user)
{
	if (ctx)
	{
		ctx->server_cb = cb;
		ctx->server_user = user;
	}
}

void luat_netdrv_dns_deinit(luat_netdrv_dns_ctx_t *ctx)
{
	if (ctx == NULL || !ctx->inited)
	{
		return;
	}
	while (!dns_list_empty(&ctx->txn_head))
	{
		luat_netdrv_dns_txn_t *txn = LUAT_NETDRV_DNS_ENTRY(ctx->txn_head.next, luat_netdrv_dns_txn_t, node);
		dns_leg_finish(ctx, txn);
	}
	while (!dns_list_empty(&ctx->req_head))
	{
		luat_netdrv_dns_req_t *req = LUAT_NETDRV_DNS_ENTRY(ctx->req_head.next, luat_netdrv_dns_req_t, node);
		dns_req_finish(ctx, req);
	}
	luat_netdrv_dns_cache_flush(ctx);
	ctx->inited = 0;
}

/* ===================================================================== */
/* 配置 / 统计                                                           */
/* ===================================================================== */

static void dns_cache_drop_negative(luat_netdrv_dns_ctx_t *ctx)
{
	luat_netdrv_dns_node_t *node, *next;
	for (node = ctx->cache_head.next; node != &ctx->cache_head; node = next)
	{
		luat_netdrv_dns_cache_ent_t *ent = LUAT_NETDRV_DNS_ENTRY(node, luat_netdrv_dns_cache_ent_t, node);
		next = node->next;
		if (ent->is_negative)
		{
			dns_cache_unlink(ent);
		}
	}
	dns_cache_count_update(ctx);
}

void luat_netdrv_dns_cfg_apply(luat_netdrv_dns_ctx_t *ctx, const luat_netdrv_dns_cfg_t *cfg,
		uint32_t now)
{
	uint32_t old_cap;
	luat_netdrv_dns_node_t *node;
	if (ctx == NULL || cfg == NULL)
	{
		return;
	}
	old_cap = ctx->cfg.cache_num;
	ctx->cfg = *cfg;
	/* 强制不变量, 防止上层传入 0 造成除零或队列自锁 */
	if (ctx->cfg.max_inflight == 0)
	{
		ctx->cfg.max_inflight = 1;
	}
	/*
	 * 令牌桶容量就是 max_inflight, 缩容时必须立刻重新钳位.
	 * 否则运行时把 max_inflight 从 8 调到 2 之后, 桶里还剩 8 个令牌,
	 * 下一次 pump 会一口气把 8 条全放出去, 直接绕过在途上限的限速语义.
	 */
	if (ctx->token > ctx->cfg.max_inflight)
	{
		ctx->token = ctx->cfg.max_inflight;
	}
	if (ctx->cfg.cache_num < old_cap)
	{
		while (dns_list_num(&ctx->cache_head) > ctx->cfg.cache_num)
		{
			luat_netdrv_dns_cache_ent_t *victim =
				LUAT_NETDRV_DNS_ENTRY(ctx->cache_head.next, luat_netdrv_dns_cache_ent_t, node);
			dns_cache_unlink(victim);
			ctx->stat.evict++;
		}
		dns_cache_count_update(ctx);
	}
	if (!ctx->cfg.cache_enable)
	{
		luat_netdrv_dns_cache_flush(ctx);
	}
	else if (ctx->cfg.neg_ttl_ms == 0)
	{
		dns_cache_drop_negative(ctx);
	}
	else
	{
		/*
		 * 上限被调小时, 已有条目必须跟着收紧.
		 * 只对新查询生效的话, 用户把 TTL 从 60s 调到 2s 后, 老条目还能再活 60s,
		 * "运行时改配置立刻生效"就变成了半句话.
		 */
		uint32_t deadline = now + ctx->cfg.cache_ttl_ms;
		for (node = ctx->cache_head.next; node != &ctx->cache_head; node = node->next)
		{
			luat_netdrv_dns_cache_ent_t *ent = LUAT_NETDRV_DNS_ENTRY(node,
					luat_netdrv_dns_cache_ent_t, node);
			if (ent->expire_ms > deadline)
			{
				ent->expire_ms = deadline;
			}
		}
	}
	dns_cache_gc(ctx, now);
}

void luat_netdrv_dns_cfg_get(const luat_netdrv_dns_ctx_t *ctx, luat_netdrv_dns_cfg_t *out)
{
	if (ctx && out)
	{
		*out = ctx->cfg;
	}
}

void luat_netdrv_dns_stat_get(const luat_netdrv_dns_ctx_t *ctx, luat_netdrv_dns_stat_t *out)
{
	if (ctx && out)
	{
		*out = ctx->stat;
	}
}

void luat_netdrv_dns_stat_reset(luat_netdrv_dns_ctx_t *ctx)
{
	uint16_t used, inflight;
	if (ctx == NULL)
	{
		return;
	}
	used = ctx->stat.cache_used;
	inflight = ctx->stat.inflight;
	memset(&ctx->stat, 0, sizeof(ctx->stat));
	ctx->stat.cache_used = used;
	ctx->stat.inflight = inflight;
}

/* ===================================================================== */
/* 查询                                                                  */
/* ===================================================================== */

/*
 * 尝试用缓存直接完成一条腿.
 * @return 1 已处理(含负缓存命中); 0 需要走网络
 */
static int dns_try_cache(luat_netdrv_dns_ctx_t *ctx, const uint8_t *name, uint32_t name_len,
		uint16_t qtype, uint32_t now, luat_dns_ip_result *out, uint8_t *out_num)
{
	luat_netdrv_dns_cache_ent_t *ent;

	if (!ctx->cfg.cache_enable || ctx->cfg.cache_num == 0)
	{
		return 0;
	}
	ent = dns_cache_find(ctx, name, name_len, qtype);
	if (ent == NULL)
	{
		ctx->stat.cache_miss++;
		return 0;
	}
	if (DNS_TIME_REACHED(now, ent->expire_ms))
	{
		dns_cache_unlink(ent);
		dns_cache_count_update(ctx);
		ctx->stat.cache_miss++;
		return 0;
	}
	ent->hit++;
	if (ent->is_negative)
	{
		ctx->stat.negative_hit++;
		*out_num = 0;
		return 1;
	}
	ctx->stat.cache_hit++;
	*out_num = (ent->ip_num > LUAT_NETDRV_DNS_MAX_RR) ? LUAT_NETDRV_DNS_MAX_RR : ent->ip_num;
	memcpy(out, ent->ip, sizeof(luat_dns_ip_result) * (*out_num));
	return 1;
}

/* 把缓存结果并入 req 并结束这条腿 */
static int dns_leg_from_cache(luat_netdrv_dns_ctx_t *ctx, luat_netdrv_dns_req_t *req,
		const uint8_t *name, uint32_t name_len, uint16_t qtype, uint32_t now)
{
	luat_dns_ip_result cached[LUAT_NETDRV_DNS_MAX_RR];
	uint8_t cached_num = 0;

	if (!dns_try_cache(ctx, name, name_len, qtype, now, cached, &cached_num))
	{
		return 0;
	}
	ctx->stat.query++;
	if (cached_num)
	{
		dns_req_add_ip(req, cached, cached_num);
	}
	req->leg_done++;
	return 1;
}

/*
 * 给事务换一个 txid.
 *
 * 每次重发(超时重试 / 换 DNS 服务器 / rcode 非 0 后的重新查询)都必须换新的 txid:
 *   - RFC 5452 要求重传也用新的随机 ID, 否则离路径攻击者猜中一次就能污染后续重传;
 *   - 换 txid 后, 上一轮迟到的应答会因为 txid 对不上被直接丢弃,
 *     不会被误当成新一次查询的答案.
 */
static void dns_txn_renew_txid(luat_netdrv_dns_ctx_t *ctx, luat_netdrv_dns_txn_t *txn)
{
	uint16_t old = txn->txid;
	do
	{
		txn->txid = ++ctx->txid_seq;
		if (txn->txid == 0)
		{
			txn->txid = ++ctx->txid_seq;	/* 0 保留, 跳过 */
		}
	}
	while (txn->txid == old);	/* 极端情况下会绕回原值, 换一个 */
}

/*
 * 提交一条腿(A 或 AAAA).
 * 命中缓存直接完成; 否则建事务入队, 交给 pump 发出.
 *
 * 注意: 走"合并到在途事务"路径时本 req 会被 dns_req_absorb 释放, 合并后
 * 归属改为对方的 req, 因此这里必须通过 reqp 回写新的 req 指针.
 * 调用方继续使用旧的 req 就是典型的 use-after-free —— 尤其在双栈请求里,
 * AAAA 腿合并会让 req 失效, 紧接着 A 腿再拿它入队会直接踩内存.
 *
 * @return 0 成功; < 0 内存分配失败
 */
static int dns_add_leg(luat_netdrv_dns_ctx_t *ctx, luat_netdrv_dns_req_t **reqp,
		const uint8_t *name, uint32_t name_len, uint16_t qtype, uint32_t now)
{
	luat_netdrv_dns_req_t *req = *reqp;
	luat_netdrv_dns_txn_t *txn;

	if (dns_leg_from_cache(ctx, req, name, name_len, qtype, now))
	{
		return 0;
	}

	/* 有同 (name,qtype) 的在途事务就合并到它的 req 上 */
	txn = dns_txn_find(ctx, name, name_len, qtype);
	if (txn != NULL && txn->req != NULL && !txn->req->notified)
	{
		luat_netdrv_dns_req_t *dst = txn->req;
		dns_req_absorb(dst, req);	/* 释放 req */
		*reqp = dst;				/* 归属改到 dst */
		ctx->stat.query++;
		dns_req_check_done(ctx, dst);
		return 0;
	}

	req->leg_total++;
	txn = luat_heap_zalloc(sizeof(luat_netdrv_dns_txn_t));
	if (txn == NULL)
	{
		return -1;
	}
	dns_node_init(&txn->node);
	txn->req = req;
	txn->qtype = qtype;
	txn->name_len = (uint8_t)name_len;
	memcpy(txn->name, name, name_len);
	txn->adapter_index = req->adapter_index;
	txn->retry = 0;
	txn->query_sent = 0;
	txn->done = 0;
	txn->txid = ++ctx->txid_seq;
	if (txn->txid == 0)
	{
		txn->txid = ++ctx->txid_seq;	/* 0 保留, 跳过 */
	}
	txn->ready_ms = now;
	dns_server_pick(ctx, txn, ctx->server_cb, ctx->server_user);
	dns_node_add_tail(&txn->node, &ctx->txn_head);
	ctx->stat.query++;
	return 0;
}

int luat_netdrv_dns_query(luat_netdrv_dns_ctx_t *ctx, const char *domain, uint32_t len,
		uint8_t is_ipv6_mode, void *param, uint8_t adapter_index, uint32_t now_ms)
{
	luat_netdrv_dns_req_t *req;
	luat_netdrv_dns_waiter_t *self;
	const uint8_t *name = (const uint8_t *)domain;
	int dual = (is_ipv6_mode && dns_can_ipv6());
	int rc = 0;
	int absorbed = 0;

	if (ctx == NULL || domain == NULL || !ctx->inited)
	{
		return -1;
	}
	if (len == 0 || len >= LUAT_NETDRV_DNS_MAX_DOMAIN)
	{
		return -1;
	}
	if (dns_name_valid(name, len) != 0)
	{
		return -1;
	}

	req = luat_heap_zalloc(sizeof(luat_netdrv_dns_req_t));
	if (req == NULL)
	{
		return -1;
	}
	dns_node_init(&req->node);
	dns_node_init(&req->waiter_head);
	req->adapter_index = adapter_index;
	dns_node_add_tail(&req->node, &ctx->req_head);

	/* 请求方自己也进等待者队列, 回调路径与后续合并进来的请求完全一致 */
	self = dns_waiter_new(param, adapter_index);
	if (self == NULL)
	{
		dns_node_del(&req->node);
		luat_heap_free(req);
		return -1;
	}
	dns_node_add_tail(&self->node, &req->waiter_head);

	/* 双栈时 AAAA 与 A 两条腿并发下发, 不再是先 AAAA 再 A.
	 * 每条腿都可能把 req 合并到别人的 req 上, 所以每次都要看回 req 是否变了. */
	if (dual)
	{
		luat_netdrv_dns_req_t *before = req;
		if (dns_add_leg(ctx, &req, name, len, LUAT_NETDRV_DNS_TYPE_AAAA, now_ms) != 0)
		{
			rc = -1;
		}
		if (req != before)
		{
			absorbed = 1;	/* req 已经归别人, 下面不能再由本函数释放 */
		}
	}
	if (rc == 0)
	{
		luat_netdrv_dns_req_t *before = req;
		if (dns_add_leg(ctx, &req, name, len, LUAT_NETDRV_DNS_TYPE_A, now_ms) != 0)
		{
			rc = -1;
		}
		if (req != before)
		{
			absorbed = 1;
		}
	}
	if (rc != 0 && !absorbed && req->leg_total == 0 && req->leg_done == 0)
	{
		/* 一条腿都没立起来, 释放自己并报错 */
		dns_node_del(&req->node);
		dns_waiter_free(self);
		luat_heap_free(req);
		return -1;
	}

	/* 全部腿都在缓存里命中时 leg_total 仍为 0, 在这里立即回调 */
	dns_req_check_done(ctx, req);
	return 0;
}

/* ===================================================================== */
/* 应答处理                                                              */
/* ===================================================================== */

int luat_netdrv_dns_rx_feed(luat_netdrv_dns_ctx_t *ctx, const uint8_t *data, uint32_t len,
		uint32_t now_ms)
{
	dns_rd_t r;
	uint16_t txid, flags, qdcount, ancount, nscount, arcount, qtype, qclass, rcode;
	luat_netdrv_dns_txn_t *txn;
	luat_dns_ip_result parsed[LUAT_NETDRV_DNS_MAX_RR];
	uint8_t parsed_num = 0;
	uint32_t min_ttl = 0xFFFFFFFFUL;
	int ipv6_allowed = dns_can_ipv6();

	if (ctx == NULL || data == NULL || !ctx->inited)
	{
		return -1;
	}
	ctx->stat.rx++;

	if (len < DNS_HDR_LEN)
	{
		ctx->stat.malformed++;
		return -1;
	}
	r.data = data;
	r.len = len;
	r.pos = 0;
	if (dns_rd_be16(&r, &txid) != 0 || dns_rd_be16(&r, &flags) != 0 ||
		dns_rd_be16(&r, &qdcount) != 0 || dns_rd_be16(&r, &ancount) != 0 ||
		dns_rd_be16(&r, &nscount) != 0 || dns_rd_be16(&r, &arcount) != 0)
	{
		ctx->stat.malformed++;
		return -1;
	}
	/* 必须是应答 */
	if (!(flags & 0x8000))
	{
		ctx->stat.malformed++;
		return -1;
	}

	txn = dns_txn_find_by_txid(ctx, txid);
	if (txn == NULL)
	{
		/* 延迟应答 / 串包 / 伪造, 丢弃但不记 malformed */
		return -1;
	}

	rcode = flags & DNS_RCODE_MASK;

	/*
	 * 标准查询的应答必须回显 question, 否则无法校验归属.
	 * 第 1 条必须与本事务的域名/类型一致, 否则视为串包或伪造应答.
	 */
	if (qdcount == 0)
	{
		DNS_LOGW("response without question, drop");
		ctx->stat.malformed++;
		return -1;
	}
	if (dns_name_match(&r, txn->name, txn->name_len) != 0)
	{
		DNS_LOGW("question name not match, drop");
		ctx->stat.malformed++;
		return -1;
	}
	if (dns_rd_be16(&r, &qtype) != 0 || dns_rd_be16(&r, &qclass) != 0)
	{
		ctx->stat.malformed++;
		return -1;
	}
	if (qtype != txn->qtype || qclass != DNS_CLASS_IN)
	{
		DNS_LOGW("question type/class not match, drop");
		ctx->stat.malformed++;
		return -1;
	}
	/* 第 2..N 条 question 跳过 */
	for (uint16_t i = 1; i < qdcount; i++)
	{
		if (dns_skip_name(&r) != 0 || r.pos + 4 > r.len)
		{
			ctx->stat.malformed++;
			return -1;
		}
		r.pos += 4;
	}

	if (rcode == DNS_RCODE_NXDOMAIN)
	{
		/* 域名不存在是确定性结果, 立即失败, 不做无谓重试 */
		DNS_LOGI("%.*s NXDOMAIN", txn->name_len, txn->name);
		ctx->stat.nxdomain++;
		dns_cache_store(ctx, txn->name, txn->name_len, txn->qtype, NULL, 0, 0, 1, now_ms);
		dns_leg_finish(ctx, txn);
		return 0;
	}
	if (rcode != 0)
	{
		/* SERVFAIL/REFUSED 等: 立即换下一台 server, 不等重试超时 */
		DNS_LOGW("%.*s rcode %d, try next dns server", txn->name_len, txn->name, rcode);
		txn->retry = 0;
		if (dns_server_advance(txn, ctx->server_cb, ctx->server_user))
		{
			txn->query_sent = 0;
			dns_txn_renew_txid(ctx, txn);
			txn->ready_ms = now_ms + DNS_SERVER_SWITCH_GAP_MS;
		}
		else
		{
			dns_leg_finish(ctx, txn);
		}
		return 0;
	}

	/* answer 区 */
	if (ancount)
	{
		if (dns_parse_rrs(&r, ancount, txn->qtype, ipv6_allowed, parsed, LUAT_NETDRV_DNS_MAX_RR,
				&parsed_num, &min_ttl) != 0)
		{
			DNS_LOGW("answer section malformed, drop");
			ctx->stat.malformed++;
			return -1;
		}
	}
	/* authority / additional 只做结构校验. 这里失败不影响已经拿到的 answer. */
	if (nscount)
	{
		(void)dns_parse_rrs(&r, nscount, 0, 0, NULL, 0, &parsed_num, &min_ttl);
	}
	if (arcount)
	{
		(void)dns_parse_rrs(&r, arcount, 0, 0, NULL, 0, &parsed_num, &min_ttl);
	}

	if (parsed_num)
	{
		uint32_t ttl_ms = (min_ttl > 0x7FFFFFFFUL) ? 0x7FFFFFFFUL : (min_ttl * 1000UL);
		dns_cache_store(ctx, txn->name, txn->name_len, txn->qtype, parsed, parsed_num,
				ttl_ms, 0, now_ms);
		if (txn->req && !txn->req->notified)
		{
			dns_req_add_ip(txn->req, parsed, parsed_num);
		}
	}
	dns_leg_finish(ctx, txn);
	return 0;
}

/* ===================================================================== */
/* 调度                                                                  */
/* ===================================================================== */

/* 按时间补充令牌桶 */
static void dns_token_refill(luat_netdrv_dns_ctx_t *ctx, uint32_t now)
{
	uint32_t cap = ctx->cfg.max_inflight;
	uint32_t gap = ctx->cfg.min_gap_ms ? ctx->cfg.min_gap_ms : 1;
	uint32_t add;

	if (ctx->token_last_ms == 0)
	{
		ctx->token = cap;
		ctx->token_last_ms = now;
		return;
	}
	if ((uint32_t)(now - ctx->token_last_ms) == 0)
	{
		return;
	}
	/* 用 uint64 做中间量, 避免 elapsed * cap 溢出 */
	add = (uint32_t)(((uint64_t)(uint32_t)(now - ctx->token_last_ms) * cap) / gap);
	ctx->token_last_ms = now;
	ctx->token += add;
	if (ctx->token > cap)
	{
		ctx->token = cap;
	}
}

/* 处理超时与重试 */
static void dns_sweep_timeouts(luat_netdrv_dns_ctx_t *ctx, uint32_t now)
{
	luat_netdrv_dns_node_t *node, *next;
	for (node = ctx->txn_head.next; node != &ctx->txn_head; node = next)
	{
		luat_netdrv_dns_txn_t *txn = LUAT_NETDRV_DNS_ENTRY(node, luat_netdrv_dns_txn_t, node);
		next = node->next;
		if (txn->done || !txn->query_sent)
		{
			continue;
		}
		if (DNS_TIME_BEFORE(now, txn->deadline_ms))
		{
			continue;			/* 还没到超时 */
		}
		if (txn->retry < ctx->cfg.max_retry)
		{
			txn->retry++;
			txn->query_sent = 0;
			dns_txn_renew_txid(ctx, txn);
			txn->ready_ms = now + dns_backoff_ms(&ctx->cfg, txn->retry);
			DNS_LOGD("%.*s timeout, retry %d in %ums", txn->name_len, txn->name,
					txn->retry, (unsigned)(txn->ready_ms - now));
		}
		else
		{
			/* 当前服务器重试耗尽, 换下一台 */
			txn->retry = 0;
			if (dns_server_advance(txn, ctx->server_cb, ctx->server_user))
			{
				txn->query_sent = 0;
				dns_txn_renew_txid(ctx, txn);
				txn->ready_ms = now + DNS_SERVER_SWITCH_GAP_MS;
			}
			else
			{
				DNS_LOGE("%.*s all dns server failed", txn->name_len, txn->name);
				ctx->stat.timeout++;
				dns_leg_finish(ctx, txn);
			}
		}
	}
}

uint8_t luat_netdrv_dns_pump(luat_netdrv_dns_ctx_t *ctx, luat_netdrv_dns_txmsg_t *out,
		uint8_t max_out, uint32_t now_ms)
{
	uint16_t inflight = 0;
	uint8_t produced = 0;
	luat_netdrv_dns_node_t *node, *next;

	if (ctx == NULL || out == NULL || !ctx->inited)
	{
		return 0;
	}

	dns_cache_gc(ctx, now_ms);
	dns_sweep_timeouts(ctx, now_ms);
	dns_token_refill(ctx, now_ms);

	/*
	 * 在途数只统计"已经发出去、等应答"的事务, 不能把排队中的也算进来.
	 * 排队的事务本来就还没占用线路; 把它们计入会让上限在队列刚满时就卡死,
	 * 结果是一条都发不出去(队列长度恰好等于上限时 100% 触发).
	 */
	for (node = ctx->txn_head.next; node != &ctx->txn_head; node = node->next)
	{
		luat_netdrv_dns_txn_t *t = LUAT_NETDRV_DNS_ENTRY(node, luat_netdrv_dns_txn_t, node);
		if (!t->done && t->query_sent)
		{
			inflight++;
		}
	}

	for (node = ctx->txn_head.next; node != &ctx->txn_head && produced < max_out; node = next)
	{
		luat_netdrv_dns_txn_t *txn = LUAT_NETDRV_DNS_ENTRY(node, luat_netdrv_dns_txn_t, node);
		int len;
		next = node->next;
		if (txn->done || txn->query_sent)
		{
			continue;
		}
		if (DNS_TIME_BEFORE(now_ms, txn->ready_ms))
		{
			continue;			/* 还没到重试时刻 */
		}
		if (txn->server_idx >= MAX_DNS_SERVER)
		{
			/* 没有可用服务器 */
			ctx->stat.timeout++;
			dns_leg_finish(ctx, txn);
			continue;
		}
		if (inflight >= ctx->cfg.max_inflight)
		{
			ctx->stat.max_inflight_hit++;
			break;
		}
		if (ctx->token == 0)
		{
			break;				/* 令牌耗尽, 等下一个 pump */
		}

		len = dns_make_query(out[produced].data, LUAT_NETDRV_DNS_MSG_MAX, txn->txid,
				txn->name, txn->name_len, txn->qtype);
		if (len < 0)
		{
			/* 域名在建事务时已校验, 走到这里只可能是空间不足 */
			dns_leg_finish(ctx, txn);
			continue;
		}
		out[produced].len = (uint8_t)len;
		out[produced].adapter_index = txn->adapter_index;
		out[produced].server_idx = txn->server_idx;
		produced++;

		txn->query_sent = 1;
		txn->deadline_ms = now_ms + ctx->cfg.query_timeout_ms;
		ctx->token--;
		ctx->stat.tx++;
		ctx->last_tx_ms = now_ms;
		inflight++;
	}

	/* 兜底: 把已经满足完成条件的 req 收掉 */
	for (node = ctx->req_head.next; node != &ctx->req_head; node = next)
	{
		luat_netdrv_dns_req_t *req = LUAT_NETDRV_DNS_ENTRY(node, luat_netdrv_dns_req_t, node);
		next = node->next;
		if (!req->notified && req->leg_total > 0 && req->leg_done >= req->leg_total)
		{
			dns_req_finish(ctx, req);
		}
	}

	ctx->stat.inflight = inflight;
	return produced;
}

void luat_netdrv_dns_report_send_err(luat_netdrv_dns_ctx_t *ctx, uint8_t adapter_index,
		uint8_t server_idx, uint32_t now_ms)
{
	luat_netdrv_dns_node_t *node;
	if (ctx == NULL || !ctx->inited)
	{
		return;
	}
	ctx->stat.send_err++;
	for (node = ctx->txn_head.next; node != &ctx->txn_head; node = node->next)
	{
		luat_netdrv_dns_txn_t *txn = LUAT_NETDRV_DNS_ENTRY(node, luat_netdrv_dns_txn_t, node);
		if (!txn->done && txn->query_sent && txn->adapter_index == adapter_index &&
			txn->server_idx == server_idx)
		{
			/* 发送失败不算一次解析尝试, 只推后一点点 */
			txn->query_sent = 0;
			txn->ready_ms = now_ms + DNS_SEND_ERR_GAP_MS;
		}
	}
}

#endif /* LUAT_USE_NETDRV_DNS_CLIENT */
