/*
 * luat_netdrv_dns_utest.c
 *
 * netdrv 现代 DNS 客户端的 C 层单元测试.
 *
 * 之所以放在 C 而不是 Lua: 这个模块刻意不依赖 lwIP, 收发由适配层负责,
 * 所以测试可以完全掌控"时间"(now_ms 显式传参)与"网络"(自己拼应答报文),
 * 从而确定性地验证并发数、退避节奏、缓存策略、畸形报文拒绝这些行为.
 * 假传输层 = 一个假的 DNS 服务器查询回调 + 一个记录结果的结果回调.
 *
 * 入口: netdrv.dns_utest(case_name) / "all"
 */

#include "luat_base.h"

/*
 * 头文件必须先于下面的 #if 引入: LUAT_USE_NETDRV_DNS_CLIENT 由 BSP 的
 * luat_conf_bsp.h 显式定义, 公共头不做兜底推导; 先判后引会永远判假.
 */
#include "luat_netdrv_dns.h"

#if defined(LUAT_USE_UTEST) && defined(LUAT_USE_NETDRV_DNS_CLIENT)

#include <string.h>
#include <stdio.h>

#define LUAT_LOG_TAG "netdrv.dns.utest"
#include "luat_network_adapter.h"
#include "luat_log.h"
#include "luat_mem.h"

/*
 * 失败诊断. 全部只出现在失败分支, 不会污染正常输出.
 * 走日志系统而不是 printf: 真机上前者才有输出通道, 后者直接被丢掉.
 */
#define DNS_DBG(...) LLOGI("utest: " __VA_ARGS__)

#define T_SERVER_COUNT		2
#define T_SINK_MAX			16
#define T_MAX_TX			16
/* 测试时间基准: 非 0, 避开 token_last_ms==0 的哨兵语义 */
#define T_T0				1000

/* ---------------- 假传输层 ---------------- */

typedef struct
{
	uint8_t got;					/* 结果回调次数 */
	uint8_t ip_num;					/* 最后一次的地址数 */
	uint8_t is_v6[T_SINK_MAX];
	uint8_t v4[T_SINK_MAX][4];
	uint8_t v6[T_SINK_MAX][16];
	void *param[T_SINK_MAX];
	uint8_t adapter[T_SINK_MAX];
	/* 可配置的服务器列表 */
	uint8_t server_cnt;
	uint32_t server[T_SERVER_COUNT];
} t_ctx_t;

static t_ctx_t g_t;

static void t_sink_reset(void)
{
	memset(&g_t, 0, sizeof(g_t));
	g_t.server_cnt = T_SERVER_COUNT;
	g_t.server[0] = 0x08080808;		/* 8.8.8.8  */
	g_t.server[1] = 0x08080404;		/* 8.8.4.4  */
}

static void t_done(void *user_ctx, void *param, uint8_t adapter_index, uint8_t ip_num,
		luat_dns_ip_result *ip)
{
	t_ctx_t *t = (t_ctx_t *)user_ctx;
	uint8_t i;
	if (t->got < T_SINK_MAX)
	{
		t->param[t->got] = param;
		t->adapter[t->got] = adapter_index;
	}
	t->got++;
	t->ip_num = ip_num;
	for (i = 0; i < ip_num && i < T_SINK_MAX; i++)
	{
		if (network_ip_is_ipv6(&ip[i].ip))
		{
			t->is_v6[i] = 1;
			memcpy(t->v6[i], ip[i].ip.u_addr.ip6.addr, 16);
		}
		else
		{
			t->is_v6[i] = 0;
			memcpy(t->v4[i], &ip[i].ip.u_addr.ip4.addr, 4);
		}
	}
	/* 所有权已转移, 必须释放, 否则每次查询都会漏一块堆内存 */
	if (ip)
	{
		luat_heap_free(ip);
	}
}

static uint8_t t_server(uint8_t adapter_index, uint8_t server_idx, luat_ip_addr_t *ip, void *user_ctx)
{
	t_ctx_t *t = (t_ctx_t *)user_ctx;
	(void)adapter_index;
	if (server_idx >= t->server_cnt)
	{
		return 0;
	}
	network_set_ip_ipv4(ip, t->server[server_idx]);
	return 1;
}

static luat_netdrv_dns_ctx_t *t_new(void)
{
	luat_netdrv_dns_ctx_t *ctx = luat_heap_zalloc(sizeof(luat_netdrv_dns_ctx_t));
	t_sink_reset();
	if (ctx == NULL)
	{
		return NULL;
	}
	if (luat_netdrv_dns_init(ctx) != 0)
	{
		luat_heap_free(ctx);
		return NULL;
	}
	luat_netdrv_dns_set_done_cb(ctx, t_done, &g_t);
	luat_netdrv_dns_set_server_cb(ctx, t_server, &g_t);
	return ctx;
}

static void t_free(luat_netdrv_dns_ctx_t *ctx)
{
	luat_netdrv_dns_deinit(ctx);
	luat_heap_free(ctx);
}

/* ---------------- 假 DNS 服务器: 拼应答报文 ---------------- */

/*
 * @param compress 是否在 answer 里用 0xC00C 压缩指针回指 question 的域名
 * @return 报文长度; < 0 失败
 */
static int t_mk_resp(uint8_t *buf, uint32_t cap, uint16_t txid, const char *name,
		uint16_t qtype, uint8_t rcode, const uint8_t *rdatas, uint16_t rr_num, uint32_t ttl,
		int compress)
{
	uint32_t p = 0;
	uint16_t rdlen = (qtype == LUAT_NETDRV_DNS_TYPE_AAAA) ? 16 : 4;
	uint16_t k;

	if (cap < 12 + 8)
	{
		return -1;
	}
	/* header */
	buf[p++] = (uint8_t)(txid >> 8);
	buf[p++] = (uint8_t)(txid & 0xFF);
	/*
	 * flags 是 16 位: byte[2] = QR|Opcode|AA|TC|RD, byte[3] = RA|Z|AD|CD|RCODE.
	 * rcode 必须落在 byte[3] 的低 4 位, 塞进 byte[2] 会被当成 RD 之外的乱码,
	 * 结果 rcode 恒为 0, NXDOMAIN/SERVFAIL 分支永远进不去.
	 */
	buf[p++] = (uint8_t)(0x80 | 0x01);	/* QR=1, RD=1 */
	buf[p++] = (uint8_t)(0x80 | rcode);	/* RA=1, RCODE */
	buf[p++] = 0x00;
	buf[p++] = 0x01;					/* QDCOUNT=1 */
	buf[p++] = (uint8_t)(rr_num >> 8);
	buf[p++] = (uint8_t)(rr_num & 0xFF);	/* ANCOUNT */
	buf[p++] = 0;
	buf[p++] = 0;
	buf[p++] = 0;
	buf[p++] = 0;

	/* question */
	{
		const char *s = name;
		for (;;)
		{
			const char *dot = strchr(s, '.');
			uint32_t seg = dot ? (uint32_t)(dot - s) : (uint32_t)strlen(s);
			if (seg == 0 || seg > 63 || p + seg + 6 + 5 > cap)
			{
				return -1;
			}
			buf[p++] = (uint8_t)seg;
			memcpy(buf + p, s, seg);
			p += seg;
			if (!dot)
			{
				break;
			}
			s = dot + 1;
		}
		buf[p++] = 0x00;
		buf[p++] = (uint8_t)(qtype >> 8);
		buf[p++] = (uint8_t)(qtype & 0xFF);
		buf[p++] = 0x00;
		buf[p++] = 0x01;				/* QCLASS IN */
	}

	/* answers */
	for (k = 0; k < rr_num; k++)
	{
		if (compress)
		{
			if (p + 2 + 10 + rdlen > cap)
			{
				return -1;
			}
			buf[p++] = 0xC0;
			buf[p++] = 0x0C;			/* 指向 offset 12 的 question 域名 */
		}
		else
		{
			const char *s = name;
			for (;;)
			{
				const char *dot = strchr(s, '.');
				uint32_t seg = dot ? (uint32_t)(dot - s) : (uint32_t)strlen(s);
				if (p + seg + 1 + 10 + rdlen > cap)
				{
					return -1;
				}
				buf[p++] = (uint8_t)seg;
				memcpy(buf + p, s, seg);
				p += seg;
				if (!dot)
				{
					break;
				}
				s = dot + 1;
			}
			buf[p++] = 0x00;
		}
		buf[p++] = (uint8_t)(qtype >> 8);
		buf[p++] = (uint8_t)(qtype & 0xFF);
		buf[p++] = 0x00;
		buf[p++] = 0x01;				/* CLASS IN */
		buf[p++] = (uint8_t)(ttl >> 24);
		buf[p++] = (uint8_t)(ttl >> 16);
		buf[p++] = (uint8_t)(ttl >> 8);
		buf[p++] = (uint8_t)(ttl);
		buf[p++] = (uint8_t)(rdlen >> 8);
		buf[p++] = (uint8_t)(rdlen & 0xFF);
		memcpy(buf + p, rdatas + (uint32_t)k * rdlen, rdlen);
		p += rdlen;
	}
	return (int)p;
}

static uint16_t t_txid_of(const luat_netdrv_dns_txmsg_t *m)
{
	return (uint16_t)(((uint16_t)m->data[0] << 8) | m->data[1]);
}

/* 从查询报文里取出 qtype, 用于构造对应应答 */
static uint16_t t_qtype_of(const luat_netdrv_dns_txmsg_t *m)
{
	uint32_t n = m->len;
	uint32_t i = 0;
	/* 跳过 12 字节头 */
	i = 12;
	while (i < n && m->data[i] != 0)
	{
		i += 1 + m->data[i];
	}
	i++;	/* 跳过根标签 */
	if (i + 4 > n)
	{
		return 0;
	}
	return (uint16_t)(((uint16_t)m->data[i] << 8) | m->data[i + 1]);
}

/* 从查询报文里反解出点分域名, 用于回一个名字匹配的应答 */
static int t_qname_of(const luat_netdrv_dns_txmsg_t *m, char *out, uint32_t cap)
{
	uint32_t n = m->len;
	uint32_t i = 12;
	uint32_t p = 0;

	if (cap < 2)
	{
		return -1;
	}
	while (i < n && m->data[i] != 0)
	{
		uint8_t l = m->data[i];
		if (p + l + 2 > cap)
		{
			return -1;
		}
		if (p)
		{
			out[p++] = '.';
		}
		memcpy(out + p, m->data + i + 1, l);
		p += l;
		i += 1 + l;
	}
	out[p] = 0;
	return (int)p;
}

/*
 * 把 pump 产出的报文全部应答掉, 让在途数归零.
 * token_bucket 用例要反复观察"每 500ms 放行几条", 在途上限必须先让位,
 * 否则测到的永远是 max_inflight 而不是令牌桶.
 */
static int t_answer_all(luat_netdrv_dns_ctx_t *ctx, luat_netdrv_dns_txmsg_t *tx, int n,
		uint32_t now)
{
	static const uint8_t rdata[4] = { 1, 2, 3, 4 };
	uint8_t resp[512];
	char name[LUAT_NETDRV_DNS_MAX_DOMAIN + 1];
	int i, rl;

	for (i = 0; i < n; i++)
	{
		if (t_qname_of(&tx[i], name, sizeof(name)) < 0)
		{
			DNS_DBG("t_answer_all: bad qname at %d", i);
			return -1;
		}
		rl = t_mk_resp(resp, sizeof(resp), t_txid_of(&tx[i]), name, LUAT_NETDRV_DNS_TYPE_A,
				0, rdata, 1, 300, 1);
		if (rl < 0 || luat_netdrv_dns_rx_feed(ctx, resp, (uint32_t)rl,
				now + (uint32_t)i) != 0)
		{
			DNS_DBG("t_answer_all: rx failed at %d (%s)", i, name);
			return -1;
		}
	}
	return 0;
}

/* ===================================================================== */
/* 用例                                                                  */
/* ===================================================================== */

/* 查询报文编码: 头部 + QNAME + QTYPE + QCLASS */
static int t_query_encode(void)
{
	luat_netdrv_dns_ctx_t *ctx = t_new();
	luat_netdrv_dns_txmsg_t tx[T_MAX_TX];
	uint8_t n;
	int rc = -1;

	if (ctx == NULL)
	{
		return -1;
	}
	if (luat_netdrv_dns_query(ctx, "a.com", 5, 0, (void *)1, 4, T_T0) != 0)
	{
		DNS_DBG("query_encode: query rejected");
		goto done;
	}
	n = luat_netdrv_dns_pump(ctx, tx, T_MAX_TX, T_T0);
	if (n != 1)
	{
		DNS_DBG("query_encode: pump n=%d", n);
		goto done;
	}
	if (tx[0].len != 23)
	{
		DNS_DBG("query_encode: len=%d", tx[0].len);
		goto done;
	}
	if (tx[0].data[2] != 0x01 || tx[0].data[3] != 0x00)	/* QR=0 RD=1 */
	{
		DNS_DBG("query_encode: flags %02x %02x",
				tx[0].data[2], tx[0].data[3]);
		goto done;
	}
	if (tx[0].data[5] != 0x01)								/* QDCOUNT=1 */
	{
		DNS_DBG("query_encode: qdcount %02x", tx[0].data[5]);
		goto done;
	}
	/*
	 * QNAME 布局: [12]=1 [13]='a' [14]=3 [15..17]="com" [18]=0
	 * 之后 [19..20]=QTYPE, [21..22]=QCLASS
	 */
	if (tx[0].data[12] != 1 || tx[0].data[13] != 'a')
	{
		DNS_DBG("query_encode: qname head %02x %02x", tx[0].data[12], tx[0].data[13]);
		goto done;
	}
	if (tx[0].data[14] != 3 || memcmp(tx[0].data + 15, "com", 3) != 0)
	{
		DNS_DBG("query_encode: qname body %02x", tx[0].data[14]);
		goto done;
	}
	if (tx[0].data[18] != 0)
	{
		DNS_DBG("query_encode: qname root %02x", tx[0].data[18]);
		goto done;
	}
	if (!(tx[0].data[19] == 0 && tx[0].data[20] == LUAT_NETDRV_DNS_TYPE_A))
	{
		DNS_DBG("query_encode: qtype %02x %02x", tx[0].data[19], tx[0].data[20]);
		goto done;
	}
	if (!(tx[0].data[21] == 0 && tx[0].data[22] == 1))
	{
		DNS_DBG("query_encode: qclass %02x %02x", tx[0].data[21], tx[0].data[22]);
		goto done;
	}
	rc = 0;
done:
	t_free(ctx);
	return rc;
}

/* 非法域名必须被拒绝 */
static int t_query_bad_domain(void)
{
	luat_netdrv_dns_ctx_t *ctx = t_new();
	int rc = -1;
	if (ctx == NULL)
	{
		return -1;
	}
	if (luat_netdrv_dns_query(ctx, "", 0, 0, NULL, 0, T_T0) == 0)
	{
		goto done;
	}
	if (luat_netdrv_dns_query(ctx, "nodot", 5, 0, NULL, 0, T_T0) == 0)
	{
		goto done;
	}
	if (luat_netdrv_dns_query(ctx, "1abc.com", 8, 0, NULL, 0, T_T0) == 0)
	{
		goto done;
	}
	if (luat_netdrv_dns_query(ctx, "abc.com-", 8, 0, NULL, 0, T_T0) == 0)
	{
		goto done;
	}
	if (luat_netdrv_dns_query(ctx, "a..com", 6, 0, NULL, 0, T_T0) == 0)
	{
		goto done;
	}
	rc = 0;
done:
	t_free(ctx);
	return rc;
}

static int t_parse_a(void)
{
	luat_netdrv_dns_ctx_t *ctx = t_new();
	luat_netdrv_dns_txmsg_t tx[T_MAX_TX];
	uint8_t resp[512];
	uint8_t rdata[8] = { 1, 2, 3, 4, 5, 6, 7, 8 };
	int rl;
	int rc = -1;

	if (ctx == NULL)
	{
		return -1;
	}
	if (luat_netdrv_dns_query(ctx, "a.com", 5, 0, (void *)7, 4, T_T0) != 0)
	{
		goto done;
	}
	if (luat_netdrv_dns_pump(ctx, tx, T_MAX_TX, T_T0) != 1)
	{
		goto done;
	}
	rl = t_mk_resp(resp, sizeof(resp), t_txid_of(&tx[0]), "a.com", LUAT_NETDRV_DNS_TYPE_A,
			0, rdata, 2, 300, 1);
	if (rl < 0)
	{
		goto done;
	}
	if (luat_netdrv_dns_rx_feed(ctx, resp, (uint32_t)rl, T_T0 + 10) != 0)
	{
		DNS_DBG("parse_a: rx_feed rejected len=%d", rl);
		goto done;
	}
	if (g_t.got != 1 || g_t.ip_num != 2)
	{
		DNS_DBG("parse_a: got=%d ip_num=%d", g_t.got, g_t.ip_num);
		goto done;
	}
	if (memcmp(g_t.v4[0], rdata, 4) != 0 || memcmp(g_t.v4[1], rdata + 4, 4) != 0)
	{
		DNS_DBG("parse_a: addr mismatch %02x%02x%02x%02x / %02x%02x%02x%02x",
				g_t.v4[0][0], g_t.v4[0][1], g_t.v4[0][2], g_t.v4[0][3],
				g_t.v4[1][0], g_t.v4[1][1], g_t.v4[1][2], g_t.v4[1][3]);
		goto done;
	}
	if (g_t.param[0] != (void *)7 || g_t.adapter[0] != 4)
	{
		DNS_DBG("parse_a: param/addr mismatch");
		goto done;
	}
	rc = 0;
done:
	t_free(ctx);
	return rc;
}

static int t_parse_aaaa(void)
{
	luat_netdrv_dns_ctx_t *ctx = t_new();
	luat_netdrv_dns_txmsg_t tx[T_MAX_TX];
	uint8_t resp[512];
	uint8_t rdata[16];
	uint8_t v4[4] = { 9, 9, 9, 9 };
	int rl, i, n;
	int a_idx = -1, aaaa_idx = -1, v6_idx = -1;
	int rc = -1;

	if (ctx == NULL)
	{
		return -1;
	}
	for (i = 0; i < 16; i++)
	{
		rdata[i] = (uint8_t)(i + 1);
	}
	/* v6 模式才会发出 AAAA 腿, 单腿模式只会发 A 腿 */
	if (luat_netdrv_dns_query(ctx, "b.com", 5, 1, (void *)9, 4, T_T0) != 0)
	{
		goto done;
	}
	n = luat_netdrv_dns_pump(ctx, tx, T_MAX_TX, T_T0);
	for (i = 0; i < n; i++)
	{
		if (t_qtype_of(&tx[i]) == LUAT_NETDRV_DNS_TYPE_A)
		{
			a_idx = i;
		}
		else
		{
			aaaa_idx = i;
		}
	}
	if (a_idx < 0 || aaaa_idx < 0)
	{
		DNS_DBG("parse_aaaa: pump n=%d a=%d aaaa=%d", n, a_idx, aaaa_idx);
		goto done;
	}
	/* 未压缩的 AAAA 应答, 覆盖"answer 里逐标签展开域名"的解析路径 */
	rl = t_mk_resp(resp, sizeof(resp), t_txid_of(&tx[aaaa_idx]), "b.com",
			LUAT_NETDRV_DNS_TYPE_AAAA, 0, rdata, 1, 300, 0);
	if (rl < 0 || luat_netdrv_dns_rx_feed(ctx, resp, (uint32_t)rl, T_T0 + 10) != 0)
	{
		DNS_DBG("parse_aaaa: aaaa rejected len=%d", rl);
		goto done;
	}
	/* A 腿补齐后才回调 */
	rl = t_mk_resp(resp, sizeof(resp), t_txid_of(&tx[a_idx]), "b.com", LUAT_NETDRV_DNS_TYPE_A,
			0, v4, 1, 300, 1);
	if (rl < 0 || luat_netdrv_dns_rx_feed(ctx, resp, (uint32_t)rl, T_T0 + 20) != 0)
	{
		DNS_DBG("parse_aaaa: a rejected len=%d", rl);
		goto done;
	}
	if (g_t.got != 1 || g_t.ip_num != 2)
	{
		DNS_DBG("parse_aaaa: got=%d ip_num=%d", g_t.got, g_t.ip_num);
		goto done;
	}
	/* 合并顺序不保证, 自行找 v6 那条 */
	for (i = 0; i < g_t.ip_num; i++)
	{
		if (g_t.is_v6[i])
		{
			v6_idx = i;
		}
	}
	if (v6_idx < 0)
	{
		DNS_DBG("parse_aaaa: no v6 entry in %d ips", g_t.ip_num);
		goto done;
	}
	if (memcmp(g_t.v6[v6_idx], rdata, 16) != 0)
	{
		DNS_DBG("parse_aaaa: v6 mismatch %02x%02x%02x%02x", g_t.v6[v6_idx][0], g_t.v6[v6_idx][1],
				g_t.v6[v6_idx][2], g_t.v6[v6_idx][3]);
		goto done;
	}
	rc = 0;
done:
	t_free(ctx);
	return rc;
}

/* 8 个不同域名必须同时在途(这是本次改造的核心目标) */
static int t_concurrent_inflight(void)
{
	luat_netdrv_dns_ctx_t *ctx = t_new();
	luat_netdrv_dns_txmsg_t tx[T_MAX_TX];
	luat_netdrv_dns_stat_t st;
	char dom[8][8] = { "d0.com", "d1.com", "d2.com", "d3.com", "d4.com", "d5.com", "d6.com",
			"d7.com" };
	int i, n;
	int rc = -1;

	if (ctx == NULL)
	{
		return -1;
	}
	for (i = 0; i < 8; i++)
	{
		if (luat_netdrv_dns_query(ctx, dom[i], (uint32_t)strlen(dom[i]), 0,
				(void *)(uintptr_t)(i + 1), 4, T_T0) != 0)
		{
			goto done;
		}
	}
	n = luat_netdrv_dns_pump(ctx, tx, T_MAX_TX, T_T0);
	if (n != 8)
	{
		goto done;
	}
	luat_netdrv_dns_stat_get(ctx, &st);
	if (st.inflight != 8)
	{
		goto done;
	}
	/* 同一个 pump 内发出的 8 条必须是 8 个不同的 txid */
	for (i = 0; i < 8; i++)
	{
		int j;
		for (j = i + 1; j < 8; j++)
		{
			if (t_txid_of(&tx[i]) == t_txid_of(&tx[j]))
			{
				goto done;
			}
		}
	}
	rc = 0;
done:
	t_free(ctx);
	return rc;
}

/* 一次 IPv6 请求应同时产生 AAAA 与 A 两条腿 */
static int t_dual_stack_concurrent(void)
{
	luat_netdrv_dns_ctx_t *ctx = t_new();
	luat_netdrv_dns_txmsg_t tx[T_MAX_TX];
	luat_netdrv_dns_stat_t st;
	uint8_t seen_a = 0, seen_aaaa = 0;
	int i, n;
	int rc = -1;

	if (ctx == NULL)
	{
		return -1;
	}
	if (luat_netdrv_dns_query(ctx, "c.com", 5, 1, (void *)3, 4, T_T0) != 0)
	{
		goto done;
	}
	n = luat_netdrv_dns_pump(ctx, tx, T_MAX_TX, T_T0);
	if (n != 2)
	{
		goto done;
	}
	for (i = 0; i < n; i++)
	{
		uint16_t qt = t_qtype_of(&tx[i]);
		if (qt == LUAT_NETDRV_DNS_TYPE_A)
		{
			seen_a = 1;
		}
		else if (qt == LUAT_NETDRV_DNS_TYPE_AAAA)
		{
			seen_aaaa = 1;
		}
	}
	if (!seen_a || !seen_aaaa)
	{
		goto done;
	}
	luat_netdrv_dns_stat_get(ctx, &st);
	if (st.inflight != 2)
	{
		goto done;
	}
	rc = 0;
done:
	t_free(ctx);
	return rc;
}

/* 两腿先后完成, 结果必须合并后一次性回调 */
static int t_dual_stack_merge(void)
{
	luat_netdrv_dns_ctx_t *ctx = t_new();
	luat_netdrv_dns_txmsg_t tx[T_MAX_TX];
	uint8_t resp[512];
	uint8_t v4[4] = { 10, 0, 0, 1 };
	uint8_t v6[16] = { 0x20, 0x01, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1 };
	int i, n, rl;
	int a_idx = -1, aaaa_idx = -1;
	int rc = -1;

	if (ctx == NULL)
	{
		return -1;
	}
	if (luat_netdrv_dns_query(ctx, "c.com", 5, 1, (void *)3, 4, T_T0) != 0)
	{
		goto done;
	}
	n = luat_netdrv_dns_pump(ctx, tx, T_MAX_TX, T_T0);
	for (i = 0; i < n; i++)
	{
		if (t_qtype_of(&tx[i]) == LUAT_NETDRV_DNS_TYPE_A)
		{
			a_idx = i;
		}
		else
		{
			aaaa_idx = i;
		}
	}
	if (a_idx < 0 || aaaa_idx < 0)
	{
		goto done;
	}
	/* 先回 AAAA, 此时不应回调(另一条腿还没结束) */
	rl = t_mk_resp(resp, sizeof(resp), t_txid_of(&tx[aaaa_idx]), "c.com",
			LUAT_NETDRV_DNS_TYPE_AAAA, 0, v6, 1, 300, 1);
	if (rl < 0 || luat_netdrv_dns_rx_feed(ctx, resp, (uint32_t)rl, T_T0 + 10) != 0)
	{
		goto done;
	}
	if (g_t.got != 0)
	{
		goto done;		/* 还没齐, 不该回调 */
	}
	/* 再回 A, 两条腿齐了才回调 */
	rl = t_mk_resp(resp, sizeof(resp), t_txid_of(&tx[a_idx]), "c.com",
			LUAT_NETDRV_DNS_TYPE_A, 0, v4, 1, 300, 1);
	if (rl < 0 || luat_netdrv_dns_rx_feed(ctx, resp, (uint32_t)rl, T_T0 + 20) != 0)
	{
		goto done;
	}
	if (g_t.got != 1 || g_t.ip_num != 2)
	{
		goto done;
	}
	rc = 0;
done:
	t_free(ctx);
	return rc;
}

/* 缓存命中不得产生任何报文 */
static int t_cache_hit_no_tx(void)
{
	luat_netdrv_dns_ctx_t *ctx = t_new();
	luat_netdrv_dns_txmsg_t tx[T_MAX_TX];
	luat_netdrv_dns_stat_t st;
	uint8_t resp[512];
	uint8_t rdata[4] = { 1, 2, 3, 4 };
	int rl, i;
	int rc = -1;

	if (ctx == NULL)
	{
		return -1;
	}
	if (luat_netdrv_dns_query(ctx, "a.com", 5, 0, (void *)1, 4, T_T0) != 0)
	{
		goto done;
	}
	if (luat_netdrv_dns_pump(ctx, tx, T_MAX_TX, T_T0) != 1)
	{
		goto done;
	}
	rl = t_mk_resp(resp, sizeof(resp), t_txid_of(&tx[0]), "a.com", LUAT_NETDRV_DNS_TYPE_A,
			0, rdata, 1, 300, 1);
	if (rl < 0 || luat_netdrv_dns_rx_feed(ctx, resp, (uint32_t)rl, T_T0 + 10) != 0)
	{
		goto done;
	}
	luat_netdrv_dns_stat_get(ctx, &st);
	if (st.tx != 1)
	{
		goto done;
	}
	/* 连续 5 次都必须缓存命中, 且不再发包 */
	for (i = 0; i < 5; i++)
	{
		g_t.got = 0;
		if (luat_netdrv_dns_query(ctx, "a.com", 5, 0, (void *)1, 4, T_T0 + 100 + (uint32_t)i) != 0)
		{
			goto done;
		}
		if (luat_netdrv_dns_pump(ctx, tx, T_MAX_TX, T_T0 + 100 + (uint32_t)i) != 0)
		{
			goto done;
		}
		if (g_t.got != 1)
		{
			goto done;
		}
	}
	luat_netdrv_dns_stat_get(ctx, &st);
	if (st.tx != 1 || st.cache_hit != 5)
	{
		goto done;
	}
	rc = 0;
done:
	t_free(ctx);
	return rc;
}

/* min(记录TTL, 上限); TTL=0 不缓存 */
static int t_cache_ttl_policy(void)
{
	luat_netdrv_dns_ctx_t *ctx = t_new();
	luat_netdrv_dns_txmsg_t tx[T_MAX_TX];
	luat_netdrv_dns_stat_t st;
	uint8_t resp[512];
	uint8_t rdata[4] = { 1, 2, 3, 4 };
	uint8_t dom[3][8] = { "t.com", "u.com", "v.com" };
	uint32_t ttls[3] = { 300, 30, 0 };	/* >上限, <上限, 0 */
	int k, rl;
	int rc = -1;

	if (ctx == NULL)
	{
		return -1;
	}
	for (k = 0; k < 3; k++)
	{
		if (luat_netdrv_dns_query(ctx, dom[k], 5, 0, (void *)1, 4, T_T0) != 0)
		{
			goto done;
		}
		if (luat_netdrv_dns_pump(ctx, tx, T_MAX_TX, T_T0 + (uint32_t)k * 100) != 1)
		{
			goto done;
		}
		rl = t_mk_resp(resp, sizeof(resp), t_txid_of(&tx[0]), dom[k], LUAT_NETDRV_DNS_TYPE_A,
				0, rdata, 1, ttls[k], 1);
		if (rl < 0 || luat_netdrv_dns_rx_feed(ctx, resp, (uint32_t)rl,
				T_T0 + (uint32_t)k * 100 + 10) != 0)
		{
			goto done;
		}
	}
	luat_netdrv_dns_stat_get(ctx, &st);
	if (st.cache_used != 2)		/* TTL=0 的那条不缓存 */
	{
		goto done;
	}
	/* TTL=300 被 60s 上限截断: 59.9s 时仍命中 */
	g_t.got = 0;
	if (luat_netdrv_dns_query(ctx, dom[0], 5, 0, (void *)1, 4, T_T0 + 59900) != 0)
	{
		goto done;
	}
	if (g_t.got != 1)
	{
		goto done;
	}
	/* 60.1s 时过期, 必须重新发包 */
	g_t.got = 0;
	if (luat_netdrv_dns_query(ctx, dom[0], 5, 0, (void *)1, 4, T_T0 + 60100) != 0)
	{
		goto done;
	}
	if (g_t.got != 0)
	{
		goto done;
	}
	/*
	 * TTL=30 的那条不受上限影响: 29.9s 命中.
	 * 该条目是在 T_T0+110 入库的, 到期时刻是 T_T0+110+30000, 不是 T_T0+30000,
	 * 所以过期检查必须越过这个时刻, 用 30.2s.
	 */
	g_t.got = 0;
	if (luat_netdrv_dns_query(ctx, dom[1], 5, 0, (void *)1, 4, T_T0 + 29900) != 0 || g_t.got != 1)
	{
		goto done;
	}
	g_t.got = 0;
	if (luat_netdrv_dns_query(ctx, dom[1], 5, 0, (void *)1, 4, T_T0 + 30200) != 0 || g_t.got != 0)
	{
		goto done;
	}
	rc = 0;
done:
	t_free(ctx);
	return rc;
}

/* 运行时改 cache_ttl 必须立刻生效 */
static int t_cache_runtime_cfg(void)
{
	luat_netdrv_dns_ctx_t *ctx = t_new();
	luat_netdrv_dns_cfg_t cfg;
	luat_netdrv_dns_txmsg_t tx[T_MAX_TX];
	uint8_t resp[512];
	uint8_t rdata[4] = { 1, 2, 3, 4 };
	int rl;
	int rc = -1;

	if (ctx == NULL)
	{
		return -1;
	}
	if (luat_netdrv_dns_query(ctx, "a.com", 5, 0, (void *)1, 4, T_T0) != 0)
	{
		DNS_DBG("rtcfg: query1 rejected");
		goto done;
	}
	if (luat_netdrv_dns_pump(ctx, tx, T_MAX_TX, T_T0) != 1)
	{
		DNS_DBG("rtcfg: pump1 != 1");
		goto done;
	}
	rl = t_mk_resp(resp, sizeof(resp), t_txid_of(&tx[0]), "a.com", LUAT_NETDRV_DNS_TYPE_A,
			0, rdata, 1, 600, 1);
	if (rl < 0 || luat_netdrv_dns_rx_feed(ctx, resp, (uint32_t)rl, T_T0 + 10) != 0)
	{
		DNS_DBG("rtcfg: rx1 failed rl=%d", rl);
		goto done;
	}
	/* 把上限压到 2s */
	luat_netdrv_dns_cfg_get(ctx, &cfg);
	cfg.cache_ttl_ms = 2000;
	luat_netdrv_dns_cfg_apply(ctx, &cfg, T_T0 + 100);
	g_t.got = 0;
	if (luat_netdrv_dns_query(ctx, "a.com", 5, 0, (void *)1, 4, T_T0 + 2100) != 0)
	{
		DNS_DBG("rtcfg: query2 rejected");
		goto done;
	}
	if (g_t.got != 0)		/* 新的 2s 上限已生效, 条目已过期 */
	{
		DNS_DBG("rtcfg: got=%u want 0", (unsigned)g_t.got);
		goto done;
	}
	rc = 0;
done:
	t_free(ctx);
	return rc;
}

/*
 * 运行时下调 cache_ttl 不得连带压缩负缓存.
 *
 * 两条缓存的生命周期口径不同: 正缓存走 min(记录TTL, cache_ttl_ms),
 * 负缓存走 neg_ttl_ms. 如果 cfg_apply 用 cache_ttl_ms 一刀切地去钳所有条目,
 * 把 cache_ttl 从 60s 调到 2s 会把 neg_ttl=10s 的 NXDOMAIN 负缓存也压成 2s ——
 * 负缓存就名存实亡了(每个不存在的域名都会重新去打 DNS).
 *
 * 构造: 正缓存条目在 [2s, 10s) 窗口内过期, 负缓存条目必须活过这个窗口.
 */
static int t_cache_neg_ttl_not_clamped(void)
{
	luat_netdrv_dns_ctx_t *ctx = t_new();
	luat_netdrv_dns_cfg_t cfg;
	luat_netdrv_dns_txmsg_t tx[T_MAX_TX];
	luat_netdrv_dns_stat_t st;
	uint8_t resp[512];
	uint8_t rdata[4] = { 1, 2, 3, 4 };
	int rl;
	int rc = -1;

	if (ctx == NULL)
	{
		return -1;
	}
	/* 正缓存: a.com 记录 TTL 给足, 靠 cache_ttl 上限来约束 */
	if (luat_netdrv_dns_query(ctx, "n1.com", 6, 0, (void *)1, 4, T_T0) != 0)
	{
		DNS_DBG("negttl: query1 rejected");
		goto done;
	}
	if (luat_netdrv_dns_pump(ctx, tx, T_MAX_TX, T_T0) != 1)
	{
		goto done;
	}
	rl = t_mk_resp(resp, sizeof(resp), t_txid_of(&tx[0]), "n1.com", LUAT_NETDRV_DNS_TYPE_A,
			0, rdata, 1, 600, 1);
	if (rl < 0 || luat_netdrv_dns_rx_feed(ctx, resp, (uint32_t)rl, T_T0 + 10) != 0)
	{
		goto done;
	}
	/* 负缓存: n2.com 回 NXDOMAIN */
	if (luat_netdrv_dns_query(ctx, "n2.com", 6, 0, (void *)1, 4, T_T0) != 0)
	{
		DNS_DBG("negttl: query2 rejected");
		goto done;
	}
	if (luat_netdrv_dns_pump(ctx, tx, T_MAX_TX, T_T0 + 20) != 1)
	{
		goto done;
	}
	rl = t_mk_resp(resp, sizeof(resp), t_txid_of(&tx[0]), "n2.com", LUAT_NETDRV_DNS_TYPE_A,
			3 /* NXDOMAIN */, NULL, 0, 0, 1);
	if (rl < 0 || luat_netdrv_dns_rx_feed(ctx, resp, (uint32_t)rl, T_T0 + 30) != 0)
	{
		goto done;
	}
	luat_netdrv_dns_stat_get(ctx, &st);
	if (st.cache_used != 2)
	{
		DNS_DBG("negttl: cache_used=%u want 2", (unsigned)st.cache_used);
		goto done;
	}

	/* 把正缓存上限压到 2s, 负缓存 neg_ttl 保持默认 10s */
	luat_netdrv_dns_cfg_get(ctx, &cfg);
	cfg.cache_ttl_ms = 2000;
	luat_netdrv_dns_cfg_apply(ctx, &cfg, T_T0 + 100);

	/* 5s 之后: 正缓存早已过期(必须重新发包), 负缓存必须还在(不能发包) */
	g_t.got = 0;
	if (luat_netdrv_dns_query(ctx, "n1.com", 6, 0, (void *)1, 4, T_T0 + 5100) != 0)
	{
		goto done;
	}
	if (g_t.got != 0)
	{
		DNS_DBG("negttl: 正缓存未按 2s 上限过期");
		goto done;
	}
	g_t.got = 0;
	if (luat_netdrv_dns_query(ctx, "n2.com", 6, 0, (void *)1, 4, T_T0 + 5100) != 0)
	{
		goto done;
	}
	if (g_t.got != 1)
	{
		DNS_DBG("negttl: 负缓存被 cache_ttl 连带压缩了(got=%u want 1)", (unsigned)g_t.got);
		goto done;
	}
	luat_netdrv_dns_stat_get(ctx, &st);
	if (st.negative_hit != 1)
	{
		DNS_DBG("negttl: negative_hit=%llu want 1", (unsigned long long)st.negative_hit);
		goto done;
	}
	rc = 0;
done:
	t_free(ctx);
	return rc;
}

/*
 * 缓存默认按网卡隔离(share=0), 打开 share 才跨网卡共享.
 *
 * 动机: 一条缓存是"某台DNS服务器经某条出口链路"解析出来的. 出口不同 ->
 * 权威DNS可能给出不同答案(地域就近调度/运营商内网域名/多WAN分流),
 * 共享会让"A出口解析出的地址"被B出口的连接复用; 反向也有害: B出口的
 * NXDOMAIN 会污染 A 出口的查询。
 *
 * 本用例覆盖三件事:
 *   1. share=0: 同一域名在网卡1解析后, 网卡2 查询必须【不命中】(要重新发包);
 *   2. share=1: 网卡2 必须命中网卡1 写入的条目(不新增发包);
 *   3. share 开关切换时整表失效(两种键空间不能混用), 且切换后行为正确。
 */
static int t_cache_adapter_isolated(void)
{
	luat_netdrv_dns_ctx_t *ctx = t_new();
	luat_netdrv_dns_cfg_t cfg;
	luat_netdrv_dns_txmsg_t tx[T_MAX_TX];
	luat_netdrv_dns_stat_t st;
	uint8_t resp[512];
	uint8_t rdata[4] = { 1, 2, 3, 4 };
	int rl;
	int rc = -1;

	if (ctx == NULL)
	{
		return -1;
	}
	luat_netdrv_dns_cfg_get(ctx, &cfg);
	if (cfg.share != 0)
	{
		DNS_DBG("share: 默认应为 0(按网卡隔离), 实际 %u", (unsigned)cfg.share);
		goto done;
	}

	/* ---- 1. share=0: 网卡 1 解析并入库 ---- */
	if (luat_netdrv_dns_query(ctx, "s.com", 5, 0, (void *)1, 1, T_T0) != 0)
	{
		goto done;
	}
	if (luat_netdrv_dns_pump(ctx, tx, T_MAX_TX, T_T0) != 1)
	{
		DNS_DBG("share: pump1 != 1");
		goto done;
	}
	rl = t_mk_resp(resp, sizeof(resp), t_txid_of(&tx[0]), "s.com", LUAT_NETDRV_DNS_TYPE_A,
			0, rdata, 1, 300, 1);
	if (rl < 0 || luat_netdrv_dns_rx_feed(ctx, resp, (uint32_t)rl, T_T0 + 10) != 0)
	{
		goto done;
	}
	luat_netdrv_dns_stat_get(ctx, &st);
	if (st.cache_used != 1)
	{
		DNS_DBG("share: cache_used=%u want 1", (unsigned)st.cache_used);
		goto done;
	}
	/* 网卡 1 自己应当命中 */
	g_t.got = 0;
	if (luat_netdrv_dns_query(ctx, "s.com", 5, 0, (void *)1, 1, T_T0 + 100) != 0 || g_t.got != 1)
	{
		DNS_DBG("share: 同网卡未命中");
		goto done;
	}
	/* 网卡 2 必须【不命中】: 这是隔离的核心语义 */
	g_t.got = 0;
	if (luat_netdrv_dns_query(ctx, "s.com", 5, 0, (void *)1, 2, T_T0 + 200) != 0)
	{
		goto done;
	}
	if (g_t.got != 0)
	{
		DNS_DBG("share: share=0 时网卡2 命中了他网卡缓存(应为隔离)");
		goto done;
	}

	/* 让网卡 2 的这条事务收尾, 免得干扰后面 */
	if (luat_netdrv_dns_pump(ctx, tx, T_MAX_TX, T_T0 + 300) != 1)
	{
		DNS_DBG("share: pump2 != 1");
		goto done;
	}
	if (t_answer_all(ctx, tx, 1, T_T0 + 310) != 0)
	{
		goto done;
	}

	/* ---- 2. 切到 share=1: 必须整表失效, 然后网卡 1 重新解析 ---- */
	luat_netdrv_dns_cfg_get(ctx, &cfg);
	cfg.share = 1;
	luat_netdrv_dns_cfg_apply(ctx, &cfg, T_T0 + 400);
	luat_netdrv_dns_stat_get(ctx, &st);
	if (st.cache_used != 0)
	{
		DNS_DBG("share: 切换 share 后未整表失效, cache_used=%u", (unsigned)st.cache_used);
		goto done;
	}
	if (luat_netdrv_dns_query(ctx, "s.com", 5, 0, (void *)1, 1, T_T0 + 500) != 0)
	{
		goto done;
	}
	if (luat_netdrv_dns_pump(ctx, tx, T_MAX_TX, T_T0 + 500) != 1)
	{
		DNS_DBG("share: pump3 != 1");
		goto done;
	}
	rl = t_mk_resp(resp, sizeof(resp), t_txid_of(&tx[0]), "s.com", LUAT_NETDRV_DNS_TYPE_A,
			0, rdata, 1, 300, 1);
	if (rl < 0 || luat_netdrv_dns_rx_feed(ctx, resp, (uint32_t)rl, T_T0 + 510) != 0)
	{
		goto done;
	}
	/* 共享模式下, 另一张网卡必须命中同一份缓存 */
	g_t.got = 0;
	if (luat_netdrv_dns_query(ctx, "s.com", 5, 0, (void *)1, 2, T_T0 + 600) != 0 || g_t.got != 1)
	{
		DNS_DBG("share: share=1 时网卡2 未共享到缓存 (got=%u)", (unsigned)g_t.got);
		goto done;
	}
	luat_netdrv_dns_stat_get(ctx, &st);
	if (st.cache_used != 1)
	{
		DNS_DBG("share: share=1 时条目数应为 1, 实际 %u", (unsigned)st.cache_used);
		goto done;
	}

	/* ---- 3. share=1 时按网卡 flush 等价于整表失效 ---- */
	luat_netdrv_dns_cache_flush_adapter(ctx, 2);
	luat_netdrv_dns_stat_get(ctx, &st);
	if (st.cache_used != 0)
	{
		DNS_DBG("share: share=1 时按网卡 flush 应清空整表, cache_used=%u",
				(unsigned)st.cache_used);
		goto done;
	}
	rc = 0;
done:
	t_free(ctx);
	return rc;
}

/* cache_num=2 时第 3 个域名淘汰 LRU */
static int t_cache_evict(void)
{
	luat_netdrv_dns_ctx_t *ctx = t_new();
	luat_netdrv_dns_cfg_t cfg;
	luat_netdrv_dns_txmsg_t tx[T_MAX_TX];
	luat_netdrv_dns_stat_t st;
	uint8_t resp[512];
	uint8_t rdata[4] = { 1, 2, 3, 4 };
	char dom[3][8] = { "e0.com", "e1.com", "e2.com" };
	int k, rl;
	int rc = -1;

	if (ctx == NULL)
	{
		return -1;
	}
	luat_netdrv_dns_cfg_get(ctx, &cfg);
	cfg.cache_num = 2;
	luat_netdrv_dns_cfg_apply(ctx, &cfg, T_T0);
	for (k = 0; k < 3; k++)
	{
		if (luat_netdrv_dns_query(ctx, dom[k], 6, 0, (void *)1, 4,
				T_T0 + (uint32_t)k * 100) != 0)
		{
			goto done;
		}
		if (luat_netdrv_dns_pump(ctx, tx, T_MAX_TX, T_T0 + (uint32_t)k * 100) != 1)
		{
			goto done;
		}
		rl = t_mk_resp(resp, sizeof(resp), t_txid_of(&tx[0]), dom[k], LUAT_NETDRV_DNS_TYPE_A,
				0, rdata, 1, 300, 1);
		if (rl < 0 || luat_netdrv_dns_rx_feed(ctx, resp, (uint32_t)rl,
				T_T0 + (uint32_t)k * 100 + 10) != 0)
		{
			goto done;
		}
	}
	luat_netdrv_dns_stat_get(ctx, &st);
	if (st.cache_used != 2 || st.evict != 1)
	{
		goto done;
	}
	/* e0 是最早的 LRU, 应已被淘汰 */
	g_t.got = 0;
	if (luat_netdrv_dns_query(ctx, dom[0], 6, 0, (void *)1, 4, T_T0 + 500) != 0 || g_t.got != 0)
	{
		goto done;
	}
	/* e2 还在 */
	g_t.got = 0;
	if (luat_netdrv_dns_query(ctx, dom[2], 6, 0, (void *)1, 4, T_T0 + 500) != 0 || g_t.got != 1)
	{
		goto done;
	}
	rc = 0;
done:
	t_free(ctx);
	return rc;
}

/* NXDOMAIN 进负缓存, SERVFAIL 不进 */
static int t_negative_and_servfail(void)
{
	luat_netdrv_dns_ctx_t *ctx = t_new();
	luat_netdrv_dns_txmsg_t tx[T_MAX_TX];
	luat_netdrv_dns_stat_t st;
	uint8_t resp[512];
	int rl, i;
	int rc = -1;

	if (ctx == NULL)
	{
		return -1;
	}
	/* NXDOMAIN */
	if (luat_netdrv_dns_query(ctx, "nx.com", 6, 0, (void *)1, 4, T_T0) != 0)
	{
		goto done;
	}
	if (luat_netdrv_dns_pump(ctx, tx, T_MAX_TX, T_T0) != 1)
	{
		goto done;
	}
	rl = t_mk_resp(resp, sizeof(resp), t_txid_of(&tx[0]), "nx.com", LUAT_NETDRV_DNS_TYPE_A,
			3, NULL, 0, 0, 1);
	if (rl < 0 || luat_netdrv_dns_rx_feed(ctx, resp, (uint32_t)rl, T_T0 + 10) != 0)
	{
		goto done;
	}
	if (g_t.got != 1 || g_t.ip_num != 0)
	{
		DNS_DBG("neg: nxdomain got=%d ip_num=%d", g_t.got, g_t.ip_num);
		goto done;
	}
	/* 再查一次必须命中负缓存, 不发包 */
	luat_netdrv_dns_stat_get(ctx, &st);
	for (i = 0; i < 3; i++)
	{
		g_t.got = 0;
		if (luat_netdrv_dns_query(ctx, "nx.com", 6, 0, (void *)1, 4,
				T_T0 + 100 + (uint32_t)i) != 0)
		{
			goto done;
		}
		{
			int np = luat_netdrv_dns_pump(ctx, tx, T_MAX_TX, T_T0 + 100 + (uint32_t)i);
			if (np != 0)
			{
				char nm[80] = "?";
				luat_netdrv_dns_stat_get(ctx, &st);
				if (np > 0)
				{
					t_qname_of(&tx[0], nm, sizeof(nm));
				}
				DNS_DBG("neg: i=%d pump emitted %d (qname=%s qtype=%u) nxdomain=%llu cache_used=%u",
						i, np, nm, (unsigned)t_qtype_of(&tx[0]),
						(unsigned long long)st.nxdomain, (unsigned)st.cache_used);
				goto done;
			}
		}
		if (g_t.got != 1)
		{
			DNS_DBG("neg: negative hit no callback at i=%d got=%d", i, g_t.got);
			goto done;
		}
	}
	luat_netdrv_dns_stat_get(ctx, &st);
	if (st.negative_hit != 3 || st.tx != 1)
	{
		DNS_DBG("neg: negative_hit=%llu tx=%llu", (unsigned long long)st.negative_hit,
				(unsigned long long)st.tx);
		goto done;
	}
	/* SERVFAIL(2): 换服务器重试, 不缓存 */
	g_t.got = 0;		/* 上面那轮负缓存命中已经把 got 置 1 了, 必须先清零 */
	if (luat_netdrv_dns_query(ctx, "sf.com", 6, 0, (void *)1, 4, T_T0 + 200) != 0)
	{
		goto done;
	}
	if (luat_netdrv_dns_pump(ctx, tx, T_MAX_TX, T_T0 + 200) != 1)
	{
		goto done;
	}
	rl = t_mk_resp(resp, sizeof(resp), t_txid_of(&tx[0]), "sf.com", LUAT_NETDRV_DNS_TYPE_A,
			2, NULL, 0, 0, 1);
	if (rl < 0 || luat_netdrv_dns_rx_feed(ctx, resp, (uint32_t)rl, T_T0 + 210) != 0)
	{
		goto done;
	}
	/* SERVFAIL 后仍在途(换了服务器), 且没有结果回调 */
	if (g_t.got != 0)
	{
		DNS_DBG("neg: servfail fired a callback got=%d", g_t.got);
		goto done;
	}
	/* 关键断言放在这里: SERVFAIL 不允许留下任何缓存条目, 此时只应有 nx 那条负缓存 */
	luat_netdrv_dns_stat_get(ctx, &st);
	if (st.cache_used != 1)
	{
		DNS_DBG("neg: cache_used=%u after servfail, want 1 (only nx)", (unsigned)st.cache_used);
		goto done;
	}
	/* 把服务器全关掉, 逼它最终失败 */
	g_t.server_cnt = 0;
	{
		uint32_t t = T_T0 + 210;
		int guard;
		for (guard = 0; guard < 50; guard++)
		{
			luat_netdrv_dns_pump(ctx, tx, T_MAX_TX, t);
			t += 5000;
		}
	}
	if (g_t.got != 1 || g_t.ip_num != 0)
	{
		DNS_DBG("neg: no-server-exhausted got=%d ip_num=%d", g_t.got, g_t.ip_num);
		goto done;
	}
	/*
	 * 上面这 50 轮跨度 250s, nx 的负缓存(默认 10s)早就被 gc 回收了,
	 * 所以这里必须是 0: 说明 SERVFAIL 那条从头到尾没进过缓存.
	 */
	luat_netdrv_dns_stat_get(ctx, &st);
	if (st.cache_used != 0 || st.timeout == 0)
	{
		DNS_DBG("neg: cache_used=%u timeout=%llu", (unsigned)st.cache_used,
				(unsigned long long)st.timeout);
		goto done;
	}
	rc = 0;
done:
	t_free(ctx);
	return rc;
}

/* 超时重试 + 指数退避 + 服务器轮转 */
static int t_retry_and_rotation(void)
{
	luat_netdrv_dns_ctx_t *ctx = t_new();
	luat_netdrv_dns_cfg_t cfg;
	luat_netdrv_dns_txmsg_t tx[T_MAX_TX];
	uint16_t txid0, txid1;
	uint8_t srv0, srv1;
	int rc = -1;
	int n;

	if (ctx == NULL)
	{
		return -1;
	}
	luat_netdrv_dns_cfg_get(ctx, &cfg);
	cfg.query_timeout_ms = 100;
	cfg.max_retry = 1;
	luat_netdrv_dns_cfg_apply(ctx, &cfg, T_T0);

	if (luat_netdrv_dns_query(ctx, "r.com", 5, 0, (void *)1, 4, T_T0) != 0)
	{
		goto done;
	}
	n = luat_netdrv_dns_pump(ctx, tx, T_MAX_TX, T_T0);
	if (n != 1)
	{
		DNS_DBG("retry: first pump n=%d want 1", n);
		goto done;
	}
	txid0 = t_txid_of(&tx[0]);
	srv0 = tx[0].server_idx;

	/* 没到超时不重发 */
	n = luat_netdrv_dns_pump(ctx, tx, T_MAX_TX, T_T0 + 50);
	if (n != 0)
	{
		DNS_DBG("retry: +50ms n=%d want 0", n);
		goto done;
	}
	/* 第一次超时后应立刻排入重试(退避 200~250ms 左右), 此时还不到点 */
	n = luat_netdrv_dns_pump(ctx, tx, T_MAX_TX, T_T0 + 120);
	if (n != 0)
	{
		DNS_DBG("retry: +120ms n=%d want 0", n);
		goto done;
	}
	/* 退避到期后重发, txid 必须换新的, 且仍打同一台 */
	n = luat_netdrv_dns_pump(ctx, tx, T_MAX_TX, T_T0 + 400);
	if (n != 1)
	{
		DNS_DBG("retry: +400ms n=%d want 1", n);
		goto done;
	}
	txid1 = t_txid_of(&tx[0]);
	srv1 = tx[0].server_idx;
	if (txid0 == txid1)
	{
		DNS_DBG("retry: txid not changed %04x", txid1);
		goto done;
	}
	if (srv0 != srv1)
	{
		DNS_DBG("retry: server rotated too early %d->%d", srv0, srv1);
		goto done;
	}
	/*
	 * 第二次超时后重试次数耗尽, 换到下一台服务器.
	 * sweep 在这一刻就把 server_idx 推进了, 但 ready_ms = now + 20ms,
	 * 所以同一个 pump 看不到报文.
	 */
	n = luat_netdrv_dns_pump(ctx, tx, T_MAX_TX, T_T0 + 500);
	if (n != 0)
	{
		DNS_DBG("retry: +500ms n=%d want 0 (switch gap not elapsed)", n);
		goto done;
	}
	n = luat_netdrv_dns_pump(ctx, tx, T_MAX_TX, T_T0 + 600);
	if (n != 1)
	{
		DNS_DBG("retry: +600ms n=%d want 1", n);
		goto done;
	}
	if (tx[0].server_idx == srv1)
	{
		DNS_DBG("retry: server not rotated, still %d", srv1);
		goto done;
	}
	rc = 0;
done:
	t_free(ctx);
	return rc;
}

/* 在途上限: 超过上限的事务排队, 不丢 */
static int t_max_inflight_cap(void)
{
	luat_netdrv_dns_ctx_t *ctx = t_new();
	luat_netdrv_dns_cfg_t cfg;
	luat_netdrv_dns_txmsg_t tx[T_MAX_TX];
	luat_netdrv_dns_stat_t st;
	char dom[6][8] = { "f0.com", "f1.com", "f2.com", "f3.com", "f4.com", "f5.com" };
	int i, n = 0;
	int rc = -1;

	if (ctx == NULL)
	{
		return -1;
	}
	luat_netdrv_dns_cfg_get(ctx, &cfg);
	cfg.max_inflight = 2;
	cfg.min_gap_ms = 0;
	luat_netdrv_dns_cfg_apply(ctx, &cfg, T_T0);

	for (i = 0; i < 6; i++)
	{
		if (luat_netdrv_dns_query(ctx, dom[i], 6, 0, (void *)1, 4, T_T0) != 0)
		{
			goto done;
		}
	}
	n = luat_netdrv_dns_pump(ctx, tx, T_MAX_TX, T_T0);
	if (n != 2)
	{
		goto done;
	}
	luat_netdrv_dns_stat_get(ctx, &st);
	if (st.inflight != 2 || st.max_inflight_hit == 0)
	{
		goto done;
	}
	rc = 0;
done:
	t_free(ctx);
	return rc;
}

/* 令牌桶限速: 桶满时允许一次完整突发, 之后按 min_gap 匀速放行 */
static int t_token_bucket(void)
{
	luat_netdrv_dns_ctx_t *ctx = t_new();
	luat_netdrv_dns_cfg_t cfg;
	luat_netdrv_dns_txmsg_t tx[T_MAX_TX];
	luat_netdrv_dns_stat_t st;
	char dom[20][10];
	int i, n;
	int rc = -1;

	if (ctx == NULL)
	{
		return -1;
	}
	for (i = 0; i < 20; i++)
	{
		snprintf(dom[i], sizeof(dom[i]), "g%d.com", i);
	}
	/* 桶容量 = max_inflight = 8, 补满一整桶需要 min_gap = 1000ms */
	luat_netdrv_dns_cfg_get(ctx, &cfg);
	cfg.max_inflight = 8;
	cfg.min_gap_ms = 1000;
	cfg.query_timeout_ms = 60000;	/* 别让事务在观测窗口内超时重发 */
	cfg.max_retry = 0;
	luat_netdrv_dns_cfg_apply(ctx, &cfg, T_T0);

	for (i = 0; i < 20; i++)
	{
		if (luat_netdrv_dns_query(ctx, dom[i], 6, 0, (void *)1, 4, T_T0) != 0)
		{
			goto done;
		}
	}
	/*
	 * 初始桶是满的: 一次放行 8 条, 剩下的 12 条排队.
	 * 时间步长刻意取 500ms, 让 500*8/1000 = 4 正好整除, 断言不含取整误差.
	 */
	n = luat_netdrv_dns_pump(ctx, tx, T_MAX_TX, T_T0);
	if (n != 8)
	{
		DNS_DBG("token_bucket: burst n=%d want 8", n);
		goto done;
	}
	if (t_answer_all(ctx, tx, n, T_T0 + 10) != 0)
	{
		goto done;
	}
	/* 桶已空, 同一时刻再 pump 放行 0 条 */
	if (luat_netdrv_dns_pump(ctx, tx, T_MAX_TX, T_T0) != 0)
	{
		goto done;
	}
	/* 之后每 500ms 恰好放行 4 条 */
	for (i = 1; i <= 3; i++)
	{
		uint32_t t = T_T0 + (uint32_t)i * 500;
		n = luat_netdrv_dns_pump(ctx, tx, T_MAX_TX, t);
		if (n != 4)
		{
			DNS_DBG("token_bucket: +%ums n=%d want 4", (unsigned)(i * 500), n);
			goto done;
		}
		if (t_answer_all(ctx, tx, n, t + 10) != 0)
		{
			goto done;
		}
	}
	/* 8 + 4*3 = 20 条已全部放行, 之后没有新事务 */
	if (luat_netdrv_dns_pump(ctx, tx, T_MAX_TX, T_T0 + 2000) != 0)
	{
		goto done;
	}
	luat_netdrv_dns_stat_get(ctx, &st);
	if (st.tx != 20)
	{
		DNS_DBG("token_bucket: tx=%llu want 20", (unsigned long long)st.tx);
		goto done;
	}
	rc = 0;
done:
	t_free(ctx);
	return rc;
}

/*
 * 队列推进不能停摆 —— 适配层定时器门控的回归用例.
 *
 * 背景(真机缺陷): 适配层原来用 ctx->stat.inflight > 0 决定调度定时器起停, 而
 * stat.inflight 只统计"已发出"的事务, 排队中的(query_sent==0)不算. 于是出现:
 *   最后一个在途事务完成时 inflight 归零, 若此刻令牌桶恰好为空(pump 的
 *   "token==0 就 break" 分支), 队列里的事务既不会被 pump 发出(定时器已停,
 *   没人再调 pump), 也不会被 sweep 超时回收(从未发出, 连 deadline_ms 都没有),
 *   应用侧的 DNS 查询就永久挂起, 直到碰巧有下一个 DNS 事件把它顺带唤醒.
 *
 * 本用例不讲时序故事, 而是直接验证门控输出那个不变式:
 *   "队列里还有没发出去的事务(query_sent==0) 时, should_schedule 必须为真"
 * 同时验证反向: 全空(无事务)时必须为假, 否则定时器永远停不下来、白天空转.
 */
static int t_queue_drain_gate(void)
{
	luat_netdrv_dns_ctx_t *ctx = t_new();
	luat_netdrv_dns_cfg_t cfg;
	luat_netdrv_dns_txmsg_t tx[T_MAX_TX];
	luat_netdrv_dns_stat_t st;
	char dom[20][10];
	int i, n;
	int rc = -1;

	if (ctx == NULL)
	{
		return -1;
	}
	for (i = 0; i < 20; i++)
	{
		snprintf(dom[i], sizeof(dom[i]), "q%d.com", i);
	}
	/*
	 * 桶容量 = max_inflight = 8, 补满一整桶要 min_gap = 1000ms.
	 * 这样 20 条查询必然"8 条在途 + 12 条排队", 排队深度可控.
	 * cache_enable=0 让每条腿都真的建事务(不吃缓存), 与 t_token_bucket 一致.
	 */
	luat_netdrv_dns_cfg_get(ctx, &cfg);
	cfg.cache_enable = 0;
	cfg.max_inflight = 8;
	cfg.min_gap_ms = 1000;
	cfg.query_timeout_ms = 60000;	/* 别让事务在观测窗口内超时重发 */
	cfg.max_retry = 0;
	luat_netdrv_dns_cfg_apply(ctx, &cfg, T_T0);

	/* ---------------- 基线: 全空时必须停表 ---------------- */
	if (luat_netdrv_dns_should_schedule(ctx) != 0)
	{
		DNS_DBG("gate: 空 ctx 却要求起表(定时器会永不停)");
		goto done;
	}

	for (i = 0; i < 20; i++)
	{
		if (luat_netdrv_dns_query(ctx, dom[i], 6, 0, (void *)1, 4, T_T0) != 0)
		{
			goto done;
		}
	}
	/*
	 * 一桶放 8 条, 剩下 12 条排队.
	 * 必须一次把桶用光(单次 pump 只能产 max_out 条), 这里 T_MAX_TX=16 > 8,
	 * 所以 8 条一次性出完, token 归零.
	 */
	n = luat_netdrv_dns_pump(ctx, tx, T_MAX_TX, T_T0);
	if (n != 8)
	{
		DNS_DBG("gate: burst n=%d want 8", n);
		goto done;
	}
	if (luat_netdrv_dns_queued(ctx) != 12)
	{
		DNS_DBG("gate: queued=%u want 12", (unsigned)luat_netdrv_dns_queued(ctx));
		goto done;
	}
	if (luat_netdrv_dns_should_schedule(ctx) != 1)
	{
		DNS_DBG("gate: 还有 12 条排队却要求停表 —— 队列会饿死");
		goto done;
	}

	/*
	 * 核心不变式: 每轮把在途全部答完, 只要还有排队事务,
	 * should_schedule 就必须一直为真. 定时器一旦被停, 队列就再也没人推.
	 */
	for (i = 0; i < 2; i++)
	{
		uint32_t t = T_T0 + (uint32_t)(i + 1) * 1000;	/* 每轮补满一桶 */
		if (t_answer_all(ctx, tx, n, t + 10) != 0)
		{
			goto done;
		}
		/*
		 * 这一刻的状态就是真机上会停摆的状态: 在途已清空, 但队列里还有
		 * 12-4*(i+1) 条没发出去。
		 *
		 * 下面这一步是本用例的关键 —— 直接断言"旧口径会得出停表"这件事:
		 *   live inflight == 0 && queued > 0  =>  must schedule
		 * 旧实现的门控正是 `stat.inflight > 0`, 在这个状态下必然返回"停表",
		 * 而停表后队列就再也没人推(定时器是 RX 驱动路径之外唯一的 pump 调用者)。
		 *
		 * 注意必须用 luat_netdrv_dns_inflight()(现算)而不是 stat.inflight(快照):
		 * 后者只在 pump 末尾更新, 不调 pump 时是旧值 —— 本用例最初就是被它骗到,
		 * 误以为"答完后仍有 8 个在途"。
		 */
		if (luat_netdrv_dns_inflight(ctx) != 0)
		{
			DNS_DBG("gate: 轮 %d 在途未清空 inflight=%u", i,
					(unsigned)luat_netdrv_dns_inflight(ctx));
			goto done;
		}
		if (luat_netdrv_dns_queued(ctx) == 0)
		{
			DNS_DBG("gate: 轮 %d 队列已空, 与预期不符", i);
			goto done;
		}
		if (luat_netdrv_dns_should_schedule(ctx) != 1)
		{
			DNS_DBG("gate: 轮 %d inflight=0 且队列非空(%u), 门控却要求停表 —— 停摆",
					i, (unsigned)luat_netdrv_dns_queued(ctx));
			goto done;
		}
		/* 补满一桶后必须能继续推进 */
		n = luat_netdrv_dns_pump(ctx, tx, T_MAX_TX, t);
		if (n <= 0)
		{
			DNS_DBG("gate: 轮 %d 队列还在却没放出任何报文", i);
			goto done;
		}
		if (luat_netdrv_dns_queued(ctx) > 0 && luat_netdrv_dns_should_schedule(ctx) != 1)
		{
			DNS_DBG("gate: 轮 %d 放出 %d 条后仍有排队却要停表", i, n);
			goto done;
		}
	}
	/* 4 + 4 + 4 = 12 条已全部放完 */
	if (luat_netdrv_dns_queued(ctx) != 0)
	{
		DNS_DBG("gate: 队列未排空, 仍剩 %u 条", (unsigned)luat_netdrv_dns_queued(ctx));
		goto done;
	}
	if (t_answer_all(ctx, tx, n, T_T0 + 4000) != 0)
	{
		goto done;
	}

	/* ---------------- 全空后必须允许停表 ---------------- */
	if (luat_netdrv_dns_has_pending(ctx) != 0)
	{
		DNS_DBG("gate: 事务未全部回收");
		goto done;
	}
	if (luat_netdrv_dns_should_schedule(ctx) != 0)
	{
		DNS_DBG("gate: 已空闲却要求继续起表(定时器永不停, 空转耗电)");
		goto done;
	}
	rc = 0;
done:
	t_free(ctx);
	return rc;
}

/* 畸形/串包/伪造应答必须被丢弃, 且不完成事务 */
static int t_malformed_rejected(void)
{
	luat_netdrv_dns_ctx_t *ctx = t_new();
	luat_netdrv_dns_txmsg_t tx[T_MAX_TX];
	uint8_t resp[600];
	uint8_t rdata[4] = { 1, 2, 3, 4 };
	uint16_t txid;
	int rl, i;
	int rc = -1;

	if (ctx == NULL)
	{
		return -1;
	}
	if (luat_netdrv_dns_query(ctx, "m.com", 5, 0, (void *)1, 4, T_T0) != 0)
	{
		goto done;
	}
	if (luat_netdrv_dns_pump(ctx, tx, T_MAX_TX, T_T0) != 1)
	{
		goto done;
	}
	txid = t_txid_of(&tx[0]);
	rl = t_mk_resp(resp, sizeof(resp), txid, "m.com", LUAT_NETDRV_DNS_TYPE_A, 0, rdata, 1, 300, 1);
	if (rl < 0)
	{
		goto done;
	}

	/* 1) 空报文 */
	if (luat_netdrv_dns_rx_feed(ctx, resp, 0, T_T0 + 10) == 0)
	{
		goto done;
	}
	/* 2) 截断到只有半个头 */
	if (luat_netdrv_dns_rx_feed(ctx, resp, 6, T_T0 + 10) == 0)
	{
		goto done;
	}
	/* 3) QR=0, 这是查询不是应答 */
	resp[2] = 0x01;
	if (luat_netdrv_dns_rx_feed(ctx, resp, (uint32_t)rl, T_T0 + 10) == 0)
	{
		goto done;
	}
	resp[2] = 0x81;
	/* 4) txid 对不上 */
	resp[0] ^= 0xFF;
	if (luat_netdrv_dns_rx_feed(ctx, resp, (uint32_t)rl, T_T0 + 10) == 0)
	{
		goto done;
	}
	resp[0] ^= 0xFF;
	/* 5) question 域名对不上 */
	rl = t_mk_resp(resp, sizeof(resp), txid, "other.com", LUAT_NETDRV_DNS_TYPE_A, 0, rdata, 1, 300, 0);
	if (rl < 0 || luat_netdrv_dns_rx_feed(ctx, resp, (uint32_t)rl, T_T0 + 10) == 0)
	{
		goto done;
	}
	/* 6) qtype 对不上 */
	rl = t_mk_resp(resp, sizeof(resp), txid, "m.com", LUAT_NETDRV_DNS_TYPE_AAAA, 0, rdata, 0, 300, 1);
	if (rl < 0 || luat_netdrv_dns_rx_feed(ctx, resp, (uint32_t)rl, T_T0 + 10) == 0)
	{
		goto done;
	}
	/* 7) 声明 ANCOUNT 但没有数据(截断) */
	rl = t_mk_resp(resp, sizeof(resp), txid, "m.com", LUAT_NETDRV_DNS_TYPE_A, 0, rdata, 1, 300, 1);
	if (rl < 0)
	{
		goto done;
	}
	/* 从 i=1 开始: i=0 是完整报文, 本来就应该被接受 */
	for (i = 1; i < 9; i++)
	{
		if (luat_netdrv_dns_rx_feed(ctx, resp, (uint32_t)rl - (uint32_t)i, T_T0 + 10) == 0)
		{
			DNS_DBG("malformed: truncated len=%d accepted", rl - i);
			goto done;
		}
	}
	/* 8) question 里塞一个前向压缩指针(恶意构造) */
	rl = t_mk_resp(resp, sizeof(resp), txid, "m.com", LUAT_NETDRV_DNS_TYPE_A, 0, rdata, 0, 300, 1);
	if (rl < 0)
	{
		goto done;
	}
	resp[12] = 0xC0;
	resp[13] = 0x20;			/* 指向 offset 32, 在自己之后 -> 前向指针 */
	if (luat_netdrv_dns_rx_feed(ctx, resp, (uint32_t)rl, T_T0 + 10) == 0)
	{
		goto done;
	}
	/* 以上全部不得完成事务 */
	if (g_t.got != 0)
	{
		goto done;
	}
	/* 最后一条合法应答必须仍然能完成 */
	rl = t_mk_resp(resp, sizeof(resp), txid, "m.com", LUAT_NETDRV_DNS_TYPE_A, 0, rdata, 1, 300, 1);
	if (rl < 0 || luat_netdrv_dns_rx_feed(ctx, resp, (uint32_t)rl, T_T0 + 20) != 0)
	{
		goto done;
	}
	if (g_t.got != 1 || g_t.ip_num != 1)
	{
		goto done;
	}
	rc = 0;
done:
	t_free(ctx);
	return rc;
}

/* QDCOUNT=0 的应答无法校验归属, 必须丢弃 */
static int t_no_question(void)
{
	luat_netdrv_dns_ctx_t *ctx = t_new();
	luat_netdrv_dns_txmsg_t tx[T_MAX_TX];
	uint8_t resp[64];
	uint16_t txid;
	int rc = -1;

	if (ctx == NULL)
	{
		return -1;
	}
	if (luat_netdrv_dns_query(ctx, "q.com", 5, 0, (void *)1, 4, T_T0) != 0)
	{
		goto done;
	}
	if (luat_netdrv_dns_pump(ctx, tx, T_MAX_TX, T_T0) != 1)
	{
		goto done;
	}
	txid = t_txid_of(&tx[0]);
	memset(resp, 0, sizeof(resp));
	resp[0] = (uint8_t)(txid >> 8);
	resp[1] = (uint8_t)(txid & 0xFF);
	resp[2] = 0x81;
	resp[3] = 0x80;
	/* QDCOUNT=0 */
	if (luat_netdrv_dns_rx_feed(ctx, resp, 12, T_T0 + 10) == 0)
	{
		goto done;
	}
	if (g_t.got != 0)
	{
		goto done;
	}
	rc = 0;
done:
	t_free(ctx);
	return rc;
}

/* flush 后必须重新查询 */
static int t_flush(void)
{
	luat_netdrv_dns_ctx_t *ctx = t_new();
	luat_netdrv_dns_txmsg_t tx[T_MAX_TX];
	luat_netdrv_dns_stat_t st;
	uint8_t resp[512];
	uint8_t rdata[4] = { 1, 2, 3, 4 };
	int rl;
	int rc = -1;

	if (ctx == NULL)
	{
		return -1;
	}
	if (luat_netdrv_dns_query(ctx, "a.com", 5, 0, (void *)1, 4, T_T0) != 0)
	{
		goto done;
	}
	if (luat_netdrv_dns_pump(ctx, tx, T_MAX_TX, T_T0) != 1)
	{
		goto done;
	}
	rl = t_mk_resp(resp, sizeof(resp), t_txid_of(&tx[0]), "a.com", LUAT_NETDRV_DNS_TYPE_A,
			0, rdata, 1, 300, 1);
	if (rl < 0 || luat_netdrv_dns_rx_feed(ctx, resp, (uint32_t)rl, T_T0 + 10) != 0)
	{
		goto done;
	}
	luat_netdrv_dns_cache_flush(ctx);
	luat_netdrv_dns_stat_get(ctx, &st);
	if (st.cache_used != 0)
	{
		goto done;
	}
	g_t.got = 0;
	if (luat_netdrv_dns_query(ctx, "a.com", 5, 0, (void *)1, 4, T_T0 + 20) != 0 || g_t.got != 0)
	{
		goto done;
	}
	if (luat_netdrv_dns_pump(ctx, tx, T_MAX_TX, T_T0 + 20) != 1)
	{
		goto done;
	}
	rc = 0;
done:
	t_free(ctx);
	return rc;
}

/* 大小写不敏感匹配 + 等待者合并 */
static int t_case_insensitive_and_merge(void)
{
	luat_netdrv_dns_ctx_t *ctx = t_new();
	luat_netdrv_dns_txmsg_t tx[T_MAX_TX];
	uint8_t resp[512];
	uint8_t rdata[4] = { 9, 8, 7, 6 };
	uint16_t txid;
	int rl;
	int rc = -1;

	if (ctx == NULL)
	{
		return -1;
	}
	if (luat_netdrv_dns_query(ctx, "mix.com", 7, 0, (void *)11, 4, T_T0) != 0)
	{
		goto done;
	}
	/* 同一域名再来一个请求, 应合并到同一条腿 */
	if (luat_netdrv_dns_query(ctx, "mix.com", 7, 0, (void *)22, 5, T_T0) != 0)
	{
		goto done;
	}
	if (luat_netdrv_dns_pump(ctx, tx, T_MAX_TX, T_T0) != 1)
	{
		goto done;
	}
	txid = t_txid_of(&tx[0]);
	/* 应答里域名用大写, 必须仍然匹配 */
	rl = t_mk_resp(resp, sizeof(resp), txid, "MIX.COM", LUAT_NETDRV_DNS_TYPE_A, 0, rdata, 1, 300, 0);
	if (rl < 0 || luat_netdrv_dns_rx_feed(ctx, resp, (uint32_t)rl, T_T0 + 10) != 0)
	{
		goto done;
	}
	if (g_t.got != 2)
	{
		goto done;		/* 两个请求方都要收到 */
	}
	if (g_t.param[0] != (void *)11 || g_t.adapter[0] != 4)
	{
		goto done;
	}
	if (g_t.param[1] != (void *)22 || g_t.adapter[1] != 5)
	{
		goto done;
	}
	if (g_t.ip_num != 1)
	{
		goto done;
	}
	rc = 0;
done:
	t_free(ctx);
	return rc;
}

/* 发送失败不消耗重试次数, 只推后重发 */
static int t_send_err(void)
{
	luat_netdrv_dns_ctx_t *ctx = t_new();
	luat_netdrv_dns_cfg_t cfg;
	luat_netdrv_dns_txmsg_t tx[T_MAX_TX];
	int rc = -1;

	if (ctx == NULL)
	{
		return -1;
	}
	luat_netdrv_dns_cfg_get(ctx, &cfg);
	cfg.query_timeout_ms = 1000;
	luat_netdrv_dns_cfg_apply(ctx, &cfg, T_T0);
	if (luat_netdrv_dns_query(ctx, "s.com", 5, 0, (void *)1, 4, T_T0) != 0)
	{
		goto done;
	}
	if (luat_netdrv_dns_pump(ctx, tx, T_MAX_TX, T_T0) != 1)
	{
		goto done;
	}
	luat_netdrv_dns_report_send_err(ctx, 4, tx[0].server_idx, T_T0 + 5);
	if (luat_netdrv_dns_pump(ctx, tx, T_MAX_TX, T_T0 + 10) != 0)
	{
		goto done;
	}
	if (luat_netdrv_dns_pump(ctx, tx, T_MAX_TX, T_T0 + 100) != 1)
	{
		goto done;
	}
	rc = 0;
done:
	t_free(ctx);
	return rc;
}

/* deinit 必须把所有挂起的请求都以失败回调掉, 不能泄漏 */
static int t_deinit_flushes(void)
{
	luat_netdrv_dns_ctx_t *ctx = t_new();
	int rc = -1;
	if (ctx == NULL)
	{
		return -1;
	}
	if (luat_netdrv_dns_query(ctx, "z.com", 5, 1, (void *)1, 4, T_T0) != 0)
	{
		goto done;
	}
	if (luat_netdrv_dns_query(ctx, "y.com", 5, 0, (void *)2, 4, T_T0) != 0)
	{
		goto done;
	}
	/* 故意不 pump, 直接 deinit */
	luat_netdrv_dns_deinit(ctx);
	/*
	 * z.com 是双栈请求(AAAA+A 两条腿), 但它仍然只是【一个请求方】, 只回调一次;
	 * y.com 单栈也回调一次. 两条腿合起来 3 个事务, 但只有 2 个请求方.
	 */
	if (g_t.got != 2)
	{
		goto done;
	}
	if (g_t.param[0] != (void *)1 || g_t.param[1] != (void *)2)
	{
		goto done;
	}
	rc = 0;
done:
	t_free(ctx);
	return rc;
}

/* 大量查询 + flush 后堆内存不得持续增长 */
static int t_no_leak(void)
{
	luat_netdrv_dns_ctx_t *ctx = t_new();
	luat_netdrv_dns_txmsg_t tx[T_MAX_TX];
	uint8_t resp[512];
	uint8_t rdata[4] = { 1, 2, 3, 4 };
	size_t total = 0, used_before = 0, used_after = 0, peak_before = 0, peak_after = 0;
	int i, rl, rc = -1;

	if (ctx == NULL)
	{
		return -1;
	}
	/*
	 * 每一轮都是"建事务 -> pump -> 收应答 -> flush"的完整往返.
	 * 不能让域名固定: 否则第一轮解析完就进了缓存, 后面 1999 轮全是缓存命中,
	 * 根本走不到分配/释放路径, 泄漏测不出来.
	 */
	for (i = 0; i < 50; i++)
	{
		uint32_t t = T_T0 + (uint32_t)i * 10;
		luat_netdrv_dns_cache_flush(ctx);
		g_t.got = 0;
		if (luat_netdrv_dns_query(ctx, "warm.com", 8, 0, (void *)1, 4, t) != 0)
		{
			goto done;
		}
		if (luat_netdrv_dns_pump(ctx, tx, T_MAX_TX, t) != 1)
		{
			DNS_DBG("leak: warm pump i=%d", i);
			goto done;
		}
		rl = t_mk_resp(resp, sizeof(resp), t_txid_of(&tx[0]), "warm.com",
				LUAT_NETDRV_DNS_TYPE_A, 0, rdata, 1, 300, 1);
		if (rl < 0 || luat_netdrv_dns_rx_feed(ctx, resp, (uint32_t)rl, t + 5) != 0)
		{
			DNS_DBG("leak: warm rx i=%d", i);
			goto done;
		}
	}
	luat_netdrv_dns_cache_flush(ctx);
	/*
	 * max_used 出参不能传 NULL: PC 的 luat_meminfo_sys 会无条件写它,
	 * 传 NULL 会在 luat_malloc_mini.c 里空指针写入崩溃.
	 */
	luat_meminfo_sys(&total, &used_before, &peak_before);

	for (i = 0; i < 2000; i++)
	{
		uint32_t t = T_T0 + 100000 + (uint32_t)i * 20;
		luat_netdrv_dns_cache_flush(ctx);
		g_t.got = 0;
		if (luat_netdrv_dns_query(ctx, "leak.com", 8, 0, (void *)1, 4, t) != 0)
		{
			DNS_DBG("leak: query rejected at i=%d", i);
			goto done;
		}
		if (luat_netdrv_dns_pump(ctx, tx, T_MAX_TX, t) != 1)
		{
			DNS_DBG("leak: pump i=%d", i);
			goto done;
		}
		rl = t_mk_resp(resp, sizeof(resp), t_txid_of(&tx[0]), "leak.com",
				LUAT_NETDRV_DNS_TYPE_A, 0, rdata, 1, 300, 1);
		if (rl < 0 || luat_netdrv_dns_rx_feed(ctx, resp, (uint32_t)rl, t + 5) != 0)
		{
			DNS_DBG("leak: rx i=%d", i);
			goto done;
		}
		if (g_t.got != 1)
		{
			DNS_DBG("leak: no callback at i=%d got=%d", i, g_t.got);
			goto done;
		}
	}
	luat_netdrv_dns_cache_flush(ctx);
	luat_netdrv_dns_deinit(ctx);
	luat_meminfo_sys(&total, &used_after, &peak_after);

	/* 允许 4KB 的抖动, 超过说明确有泄漏 */
	if (used_after > used_before + 4096)
	{
		DNS_DBG("leak: before %u after %u",
				(unsigned)used_before, (unsigned)used_after);
		goto done;
	}
	(void)total;
	(void)peak_before;
	(void)peak_after;
	rc = 0;
done:
	t_free(ctx);
	return rc;
}

/* ===================================================================== */
/* 入口                                                                  */
/* ===================================================================== */

typedef struct
{
	const char *name;
	int (*fn)(void);
}t_case_t;

static const t_case_t t_cases[] = {
	{ "query_encode", t_query_encode },
	{ "query_bad_domain", t_query_bad_domain },
	{ "parse_a", t_parse_a },
	{ "parse_aaaa", t_parse_aaaa },
	{ "concurrent_inflight", t_concurrent_inflight },
	{ "dual_stack_concurrent", t_dual_stack_concurrent },
	{ "dual_stack_merge", t_dual_stack_merge },
	{ "cache_hit_no_tx", t_cache_hit_no_tx },
	{ "cache_ttl_policy", t_cache_ttl_policy },
	{ "cache_runtime_cfg", t_cache_runtime_cfg },
	{ "cache_adapter_isolated", t_cache_adapter_isolated },
	{ "cache_neg_ttl_not_clamped", t_cache_neg_ttl_not_clamped },
	{ "cache_evict", t_cache_evict },
	{ "negative_and_servfail", t_negative_and_servfail },
	{ "retry_and_rotation", t_retry_and_rotation },
	{ "max_inflight_cap", t_max_inflight_cap },
	{ "token_bucket", t_token_bucket },
	{ "queue_drain_gate", t_queue_drain_gate },
	{ "malformed_rejected", t_malformed_rejected },
	{ "no_question", t_no_question },
	{ "flush", t_flush },
	{ "case_insensitive_and_merge", t_case_insensitive_and_merge },
	{ "send_err", t_send_err },
	{ "deinit_flushes", t_deinit_flushes },
	{ "no_leak", t_no_leak },
};

int luat_netdrv_dns_utest(lua_State *L, const char *case_name)
{
	size_t i, n = sizeof(t_cases) / sizeof(t_cases[0]);
	int matched = 0;
	int rc = 0;

	(void)L;
	if (case_name == NULL || strcmp(case_name, "all") == 0)
	{
		for (i = 0; i < n; i++)
		{
			if (t_cases[i].fn() != 0)
			{
				DNS_DBG("case fail: %s",
						t_cases[i].name);
				rc = -1;
			}
			else
			{
				luat_log_log(LUAT_LOG_INFO, "netdrv.dns.utest", "case pass: %s",
						t_cases[i].name);
			}
		}
		return rc;
	}
	for (i = 0; i < n; i++)
	{
		if (strcmp(case_name, t_cases[i].name) == 0)
		{
			matched = 1;
			if (t_cases[i].fn() != 0)
			{
				DNS_DBG("case fail: %s",
						t_cases[i].name);
				rc = -1;
			}
			else
			{
				luat_log_log(LUAT_LOG_INFO, "netdrv.dns.utest", "case pass: %s",
						t_cases[i].name);
			}
			break;
		}
	}
	if (!matched)
	{
		DNS_DBG("unknown case: %s", case_name);
		rc = -1;
	}
	return rc;
}

#endif /* defined(LUAT_USE_UTEST) && defined(LUAT_USE_NETDRV_DNS_CLIENT) */
