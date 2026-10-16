/*
 * luat_netdrv_dns.h
 *
 * netdrv 现代 DNS 客户端 —— 对比 components/ethernet/common/dns_client.c 的四点改进:
 *   1. 多个查询可同时在途(并发), 不再是"单队列一次只发一条 + 1 秒定时器"
 *   2. A / AAAA 作为两条独立腿并发发出, 不再是 AAAA 串行在前、A 串行在后
 *   3. 带 LRU 结果缓存(默认 TTL 上限 60 秒), NXDOMAIN 走短 TTL 负缓存
 *   4. 并发上限 + 最小发送间隔 + 指数退避 + 服务器轮转, 全部可配
 *
 * 分层约定(重要):
 *   本模块【不调用任何 lwIP API】, 也不绑定任何传输层.
 *   它只负责 DNS 协议编解码 + 事务状态机 + 缓存 + 调度;
 *   实际的收发由 net_lwip2.c 用 udp_sendto_if / raw pcb 回调完成.
 *   因此它可以在 PC 模拟器里用假传输层直接驱动做高覆盖率单元测试,
 *   真机只负责验证真实网络路径.
 *
 * 线程不变式(必须严格遵守):
 *   ctx 内的全部状态只能在 lwIP tcpip 线程内被读写.
 *   net_lwip2.c 通过 platform_send_event -> tcpip_callback 进入本模块;
 *   原始 UDP 收包回调也必须先经事件转发(EV_LWIP_DNS_RX)再进来.
 *   其它线程(Lua 任务)只能通过 net_lwip2 的配置事件间接触达.
 */

#ifndef __LUAT_NETDRV_DNS_H__
#define __LUAT_NETDRV_DNS_H__

/*
 * 关于 c_common.h / 平台 bsp_common.h 的撞名问题 —— 这里的事实必须写清楚,
 * 否则后来者会照着一段不成立的注释去改 include, 必然踩坑:
 *
 *   c_common.h 与 CCM42xx SDK 的 bsp_common.h 重复定义了同一批类型
 *   (Time_UserDataStruct / Date_UserDataStruct / Time_Union / Date_Union,
 *    连 llist_head 都同名), 同时可见必然 conflicting types.
 *
 * 【本头并没有做到"不引 c_common.h"】
 *   下面这两行是必需的:
 *     - dns_def.h            提供 luat_dns_ip_result / MAX_DNS_SERVER / DNS_SERVER_PORT
 *     - luat_network_adapter.h 提供 luat_ip_addr_t / network_ip_is_vaild / MAX_DNS_IP
 *   而 dns_def.h 与 luat_network_adapter.h 在【非 SDK 构建】下都会把 c_common.h 拉进来
 *   (实测: PC 上 luat_netdrv_dns.c.obj.d 里确实有 components/common/c_common.h).
 *
 * 【真正避免冲突的是 luat_network_adapter.h 里既有的守卫, 不是本文件的私有链表】
 *   luat_network_adapter.h:5-11
 *     #if defined(__SOC_BSP__) || ... 
 *     #include "bsp_common.h"          // 先定义 __BSP_COMMON_H__
 *     #endif
 *     #ifndef __BSP_COMMON_H__
 *     #include "c_common.h"          // SDK 构建下被守卫挡住, 不会与 bsp_common.h 并存
 *     #endif
 *
 * 【那本文件的私有链表是干什么的】
 *   它是为了不依赖 c_common.h 的 llist_* 实现 —— 后者用 GCC 语句表达式 ({...}),
 *   MSVC 编不过; 而且类型名会与 SDK 头撞名. 也就是说私有链表解决的是
 *   "MSVC 可编译 + 类型名独立", 不是"避免引入 c_common.h". 两件事不要混为一谈.
 *
 * 【本头会被两类编译单元包含】
 *   1. luat_lib_netdrv.c —— 经 luat_netdrv.h -> lwip pbuf -> lwipopts 见过 bsp_common.h
 *   2. SDK 侧单元       —— 经 csdk/interface/net_lwip.h -> net_lwip2.h 见过 bsp_common.h
 *   所以对本头做任何 include 增删, 都要同时评估这两条链.
 *
 * 【想真正做到解耦该怎么做】
 *   把 luat_dns_ip_result / MAX_DNS_SERVER / DNS_SERVER_PORT 从 dns_def.h 抽到 netdrv
 *   自己的头里, 让本模块不再引 dns_def.h. 那才是"与平台头解耦"的正解, 目前没做.
 */
#include "dns_def.h"
#include "luat_network_adapter.h"
#include <stddef.h>

/* 私有双向链表节点: 布局与 luat_netdrv_dns_node_t 一致, 但类型名独立, 不会与平台头撞名 */
typedef struct luat_netdrv_dns_node
{
	struct luat_netdrv_dns_node *next, *prev;
}luat_netdrv_dns_node_t;

/*
 * 可移植的 container-of.
 *
 * 不能用 c_common.h 的 llist_entry: 它展开成 GCC 的语句表达式 ({ ... }),
 * MSVC 无法编译 —— 这也是旧 dns_client.c 全程只用 llist_traversal 而从不
 * 直接取结构体的原因. 本文件改用 offsetof, MSVC 与 arm-gnu 都支持.
 */
#define LUAT_NETDRV_DNS_ENTRY(ptr, type, member) \
	((type *)((uint8_t *)(ptr) - offsetof(type, member)))

/*
 * ==== 功能开关 ====
 *
 * 开关约定(与本仓库其它 LUAT_USE_* 能力宏一致, 只看"有没有定义", 不看取值):
 *   - 未定义 : 使用旧实现 components/ethernet/common/dns_client.c
 *   - 已定义 : 使用本实现
 *
 * 默认口径: 【本头不提供任何默认值兜底】需要该实现的 BSP 必须在自己的
 * luat_conf_bsp.h 里显式声明:
 *   #define LUAT_USE_NETDRV_DNS_CLIENT 1
 * 与 luat_netdrv.h:25-26 对 LUAT_USE_NETDRV_IPV6 的口径一致。
 *
 * 【为什么不做成"定义了 LUAT_USE_DNS 就自动开启"】
 * 曾经是那样(自动推导, 另提供 LUAT_NETDRV_DNS_CLIENT_LEGACY 回退), 目的是让
 * Air1601 这类"luat_conf_bsp.h 在 SDK 仓库内"的 BSP 零跨仓库改动即可生效。
 * 但它的代价是一处隐性耦合, 已被废弃:
 *   - LUAT_USE_DNS 是各 SDK 早就存在的"有没有 DNS 能力"开关, 与"用哪套实现"
 *     是两件事。自动推导让这一个宏悄悄承担了第二个语义, 而 SDK 侧编辑配置的
 *     人从宏名和注释里看不出这一点;
 *   - 于是想单独回退实现时 SDK 侧无从下手(回退宏只写在本仓库注释里); 而注掉
 *     LUAT_USE_DNS 想省 flash 时, 会连 DNS 能力一起掉到旧实现, 而不是只切换实现;
 *   - 新 BSP 首次写 LUAT_USE_DNS 时, 会在没有任何评审提示的情况下默认拿到新实现
 *     —— 而两者行为有真实差异(并发 / 令牌桶节奏 / TTL上限 / 负缓存 / 缓存是否按
 *     网卡隔离)。
 * 现在改用显式开关: LUAT_USE_DNS 恢复"只管能力"的单一语义, 职责边界清楚。
 */

#ifdef LUAT_USE_NETDRV_DNS_CLIENT

/* 域名最大长度(不含结束符), 与 luat_netdrv_event.h 的 domain_name[256] 保持一致 */
#define LUAT_NETDRV_DNS_MAX_DOMAIN		256
/* DNS over UDP 单报文上限(RFC 1035) */
#define LUAT_NETDRV_DNS_MSG_MAX			512
/* 单个应答最多解析的记录数, 与 MAX_DNS_IP 保持一致 */
#define LUAT_NETDRV_DNS_MAX_RR			MAX_DNS_IP

/* 记录类型 */
#define LUAT_NETDRV_DNS_TYPE_A			1		/* A    */
#define LUAT_NETDRV_DNS_TYPE_AAAA		28	/* AAAA */

/* 默认配置 */
#define LUAT_NETDRV_DNS_DEF_CACHE_NUM		32
#define LUAT_NETDRV_DNS_DEF_CACHE_TTL_MS	60000
#define LUAT_NETDRV_DNS_DEF_NEG_TTL_MS		10000
#define LUAT_NETDRV_DNS_DEF_MAX_INFLIGHT	8
#define LUAT_NETDRV_DNS_DEF_MAX_RETRY		2
#define LUAT_NETDRV_DNS_DEF_TIMEOUT_MS		2000
#define LUAT_NETDRV_DNS_DEF_MIN_GAP_MS		20

/* netdrv.ctrl 的 DNS 配置项取值范围(越界拒绝该项并记日志, 不静默截断) */
#define LUAT_NETDRV_DNS_LIM_CACHE_NUM_MAX	256
#define LUAT_NETDRV_DNS_LIM_CACHE_TTL_MAX	86400000UL
#define LUAT_NETDRV_DNS_LIM_NEG_TTL_MAX		3600000UL
#define LUAT_NETDRV_DNS_LIM_INFLIGHT_MAX	32
#define LUAT_NETDRV_DNS_LIM_TIMEOUT_MIN		100
#define LUAT_NETDRV_DNS_LIM_TIMEOUT_MAX		30000
#define LUAT_NETDRV_DNS_LIM_RETRY_MAX		5
#define LUAT_NETDRV_DNS_LIM_MIN_GAP_MAX		1000

/* ---- 可配置项 ---- */
typedef struct
{
	uint32_t cache_num;		/* 缓存条目上限, 0 = 不缓存.         默认 32      */
	uint32_t cache_ttl_ms;	/* 记录 TTL 上限, 0 = 不缓存.        默认 60000ms */
	uint32_t neg_ttl_ms;	/* NXDOMAIN 负缓存时长.              默认 10000ms */
	uint8_t cache_enable;	/* 缓存总开关, 0 关闭.              默认 1       */
	/*
	 * 缓存是否跨网卡共享, 默认 0(不共享).
	 *
	 * 默认不共享的原因: 一条缓存条目是"由某台 DNS 服务器经某条出口链路"解析出来的.
	 * 出口不同 -> 权威 DNS 可能给出不同答案:
	 *   - 地域就近调度(CDN): 蜂窝出口与以太网出口可能落在不同 POP;
	 *   - 运营商内网域名: 只在某条链路的 DNS 上可解析;
	 *   - 多 WAN 分流: 各出口的 DNS 视图本就不同.
	 * 共享会把这些答案混在一起, 让"A 出口解析出的地址"被 B 出口的连接复用;
	 * 反过来也有害: B 出口解析失败(或 NXDOMAIN)会污染 A 出口的查询结果。
	 *
	 * 置 1 则显式共享: 缓存键退化为 (name, qtype), 适合"各网卡 DNS 视为等价"
	 * 的简单设备, 可以省一份缓存。
	 *
	 * 运行时切换本开关会整表失效(两种键空间不能混用), 见 luat_netdrv_dns_cfg_apply。
	 */
	uint8_t share;			/* 缓存跨网卡共享, 0 = 按网卡隔离.   默认 0       */
	uint8_t max_inflight;	/* 最大在途事务数, 至少 1.          默认 8       */
	uint8_t max_retry;		/* 单台服务器最多重试次数.           默认 2       */
	uint16_t query_timeout_ms;	/* 单次尝试超时.            默认 2000ms   */
	uint16_t min_gap_ms;	/* 相邻两次发出的最小间隔.          默认 20ms    */
}luat_netdrv_dns_cfg_t;

/* ---- 统计 ---- */
typedef struct
{
	uint64_t query;			/* 提交的查询请求数(含双栈的第二条腿) */
	uint64_t cache_hit;		/* 正缓存命中次数 */
	uint64_t cache_miss;	/* 缓存未命中次数 */
	uint64_t negative_hit;	/* 负缓存(NXDOMAIN)命中次数 */
	uint64_t tx;			/* 实际发出的 DNS 报文数 */
	uint64_t rx;			/* 收到的 DNS 报文数 */
	uint64_t nxdomain;		/* 收到 NXDOMAIN 的次数 */
	uint64_t timeout;		/* 事务最终超时失败的次数 */
	uint64_t evict;			/* LRU 淘汰的缓存条目数 */
	uint64_t malformed;	/* 因格式非法被丢弃的应答数 */
	uint64_t max_inflight_hit;	/* 因在途上限而排队的次数 */
	uint64_t send_err;		/* 发送失败(由适配层回报)的次数 */
	uint16_t inflight;		/* 当前在途事务数 */
	uint16_t cache_used;	/* 当前缓存条目数 */
	/*
	 * 能力位(不是计数器): 当前构建能否表达 AAAA 结果, 即 lwIP 是否编入了
	 * IPv6(LWIP_IPV6). 为 0 时双栈查询只发 A 那条腿 —— 发 AAAA 也存不下来,
	 * 结果里不可能出现 IPv6 地址, 这不是解析失败.
	 * 由 luat_netdrv_dns_stat_get() 每次现算填入, 不存在 ctx->stat 里
	 * (统计会被 memset 重置, 能力位不该跟着被清掉).
	 */
	uint8_t ipv6;
}luat_netdrv_dns_stat_t;

/* ---- 缓存条目 ---- */
typedef struct luat_netdrv_dns_cache_ent
{
	luat_netdrv_dns_node_t node;
	/*
	 * 归属网卡. cfg.share=0 时它是缓存键的一部分(按网卡隔离);
	 * cfg.share=1 时入表统一写 0(归一化), 因为此时键里不含网卡。
	 * 详见 luat_netdrv_dns_cfg_t.share 的说明。
	 */
	uint8_t adapter_index;
	uint8_t name_len;
	uint8_t name[LUAT_NETDRV_DNS_MAX_DOMAIN];
	uint16_t qtype;
	uint8_t ip_num;
	luat_dns_ip_result ip[LUAT_NETDRV_DNS_MAX_RR];
	uint32_t expire_ms;		/* luat_mcu_tick64_ms() 基准的绝对到期时刻 */
	uint8_t is_negative;	/* 1 = NXDOMAIN 负缓存 */
	uint64_t hit;
}luat_netdrv_dns_cache_ent_t;

/* ---- 单个请求方 ---- */
typedef struct luat_netdrv_dns_waiter
{
	luat_netdrv_dns_node_t node;
	void *param;			/* = network_ctrl_t* */
	uint8_t adapter_index;
}luat_netdrv_dns_waiter_t;

/* ---- 请求聚合体: 一次 dns()/dns_ipv6() 调用对应一个, 内部含 1~2 条腿 ---- */
typedef struct luat_netdrv_dns_req
{
	luat_netdrv_dns_node_t node;
	luat_netdrv_dns_node_t waiter_head;	/* 合并等待同一 (name,qtype) 的请求方 */
	luat_dns_ip_result ip[LUAT_NETDRV_DNS_MAX_RR];
	uint8_t ip_num;
	uint8_t leg_total;		/* 总腿数: 1 = 仅 A, 2 = AAAA + A */
	uint8_t leg_done;		/* 已进入终态的腿数 */
	uint8_t notified;		/* 结果已回调, 防重复通知 */
	void *param;
	uint8_t adapter_index;
}luat_netdrv_dns_req_t;

/* ---- 在途事务: 一个 (域名, qtype) 针对一组服务器的解析过程 ---- */
typedef struct luat_netdrv_dns_txn
{
	luat_netdrv_dns_node_t node;
	luat_netdrv_dns_req_t *req;
	uint16_t txid;
	uint16_t qtype;
	uint8_t name_len;
	uint8_t name[LUAT_NETDRV_DNS_MAX_DOMAIN];
	uint8_t adapter_index;
	uint8_t server_idx;		/* 当前使用的 DNS 服务器下标 */
	uint8_t retry;			/* 当前服务器已重试次数 */
	uint8_t query_sent;		/* 本服务器是否已发出过 */
	uint8_t done;			/* 该腿是否已进入终态 */
	uint32_t ready_ms;		/* 最早可发出时刻(重试/换服退避后生效) */
	uint32_t deadline_ms;	/* 已发出时的应答超时时刻 */
}luat_netdrv_dns_txn_t;

/* ---- 待发报文 ---- */
typedef struct
{
	uint8_t len;
	uint8_t adapter_index;
	uint8_t server_idx;		/* 适配层据此决定发给哪台服务器 */
	uint8_t data[LUAT_NETDRV_DNS_MSG_MAX];
}luat_netdrv_dns_txmsg_t;

/*
 * 取指定适配器第 server_idx 台 DNS 服务器.
 * 返回 1 且写出地址 = 该服务器有效; 返回 0 = 无效(未配置或已置为无效).
 */
typedef uint8_t (*luat_netdrv_dns_server_cb)(uint8_t adapter_index, uint8_t server_idx,
		luat_ip_addr_t *ip, void *user_ctx);

/*
 * 结果回调. 每个等待者单独回调一次.
 * ip_num > 0 时 ip 为 luat_heap_zalloc 出来的堆数组, 所有权【转移给回调方】
 * (与 EV_NW_DNS_RESULT 的既有约定一致, 接收方会接管并在稍后释放);
 * ip_num == 0 时 ip == NULL, 表示解析失败(含负缓存命中).
 */
typedef void (*luat_netdrv_dns_done_cb)(void *user_ctx, void *param, uint8_t adapter_index,
		uint8_t ip_num, luat_dns_ip_result *ip);

/* ---- 全局上下文(单例, 跨网卡共享缓存) ---- */
typedef struct
{
	luat_netdrv_dns_cfg_t cfg;
	luat_netdrv_dns_node_t cache_head;		/* 队首 = 最近最少使用 */
	luat_netdrv_dns_node_t txn_head;		/* 在途事务 */
	luat_netdrv_dns_node_t req_head;		/* 未完成请求(含等待者) */
	uint16_t txid_seq;
	uint32_t last_tx_ms;		/* 节奏控制 */
	/*
	 * 令牌桶限速: 容量 = max_inflight, 每 min_gap_ms 补满 max_inflight 个令牌,
	 * 每发一条报文消耗 1 个.
	 * 目的是"允许突发、限制持续速率": 一次 8 个域名的批量解析会立刻全部发出
	 * (这正是并发要的效果), 但持续查询速率被钳在 max_inflight/min_gap_ms.
	 * 若只在 pump 入口判断 min_gap, 粗粒度定时器会把限速退化成"每 tick 一条",
	 * 并发直接失效, 因此改成按时间补充的令牌桶.
	 */
	uint32_t token;
	uint32_t token_last_ms;
	uint8_t rr_server;		/* 服务器轮转游标 */
	uint8_t inited;
	/*
	 * 结果回调绑定在 ctx 上而不是逐次传参:
	 * 一条腿可能从 rx_feed / pump / sweep 三条路径之一进入终态,
	 * 而 pump 与 sweep 不持有调用方的回调上下文, 逐层透传既啰嗦又容易漏传.
	 */
	luat_netdrv_dns_done_cb done_cb;
	void *done_user;
	/*
	 * DNS 服务器表由适配层(net_lwip2)按适配器持有, 客户端不直接依赖 lwIP,
	 * 因此通过回调按需查询. 与 done_cb 同样绑定在 ctx 上:
	 * sweep / pump 在没有调用方上下文的情况下也要能换服务器.
	 */
	luat_netdrv_dns_server_cb server_cb;
	void *server_user;
	luat_netdrv_dns_stat_t stat;
}luat_netdrv_dns_ctx_t;

/* ---- 生命周期 ---- */

/** 初始化 ctx, 装载默认配置, 随机化 txid 起点(防跨会话可预测, RFC 5452) */
int luat_netdrv_dns_init(luat_netdrv_dns_ctx_t *ctx);

/** 绑定结果回调. 一个 ctx 对应一个适配层, 通常在 init 之后立即调用一次 */
void luat_netdrv_dns_set_done_cb(luat_netdrv_dns_ctx_t *ctx, luat_netdrv_dns_done_cb cb, void *user);

/** 绑定 DNS 服务器查询回调. 与结果回调一样绑定在 ctx 上, 供 pump/rx_feed 自行取服务器 */
void luat_netdrv_dns_set_server_cb(luat_netdrv_dns_ctx_t *ctx, luat_netdrv_dns_server_cb cb, void *user);

/** 释放全部缓存条目与在途事务, 并对未完成的请求回调失败 */
void luat_netdrv_dns_deinit(luat_netdrv_dns_ctx_t *ctx);

/* ---- 查询 ---- */

/**
 * 提交一个查询请求.
 * @param is_ipv6_mode 0 = 只查 A; 非 0 = 同时并发查 AAAA 与 A(两条腿), 结果合并
 * @param param 请求方上下文(透传给 done 回调)
 * @return 0 成功(已入队或缓存命中); < 0 参数非法或内存不足
 */
int luat_netdrv_dns_query(luat_netdrv_dns_ctx_t *ctx, const char *domain, uint32_t len,
		uint8_t is_ipv6_mode, void *param, uint8_t adapter_index, uint32_t now_ms);

/**
 * 喂入一条 DNS 应答.
 * 非法/串包/伪造的应答只记统计并丢弃, 不会完成任何事务(等超时).
 * @return 0 表示该报文被接受并处理; < 0 表示被丢弃
 */
int luat_netdrv_dns_rx_feed(luat_netdrv_dns_ctx_t *ctx, const uint8_t *data, uint32_t len,
		uint32_t now_ms);

/**
 * 调度: 处理超时/重试/服务器轮转, 并产出一批待发报文.
 * 幂等, 可在任意时机反复调用.
 * @return 实际产出的报文数(<= max_out)
 */
uint8_t luat_netdrv_dns_pump(luat_netdrv_dns_ctx_t *ctx, luat_netdrv_dns_txmsg_t *out,
		uint8_t max_out, uint32_t now_ms);

/**
 * 回报一次发送失败. 不消耗重试次数, 只把该事务推后一小段退避后重发.
 */
void luat_netdrv_dns_report_send_err(luat_netdrv_dns_ctx_t *ctx, uint8_t adapter_index,
		uint8_t server_idx, uint32_t now_ms);

/* ---- 配置与统计 ---- */

/**
 * 应用配置. cache_num / cache_ttl_ms / neg_ttl_ms 变化时会立即重新裁剪缓存.
 * 各字段的取值范围见文件头部的 LUAT_NETDRV_DNS_LIM_* 宏.
 */
void luat_netdrv_dns_cfg_apply(luat_netdrv_dns_ctx_t *ctx, const luat_netdrv_dns_cfg_t *cfg,
		uint32_t now_ms);

void luat_netdrv_dns_cfg_get(const luat_netdrv_dns_ctx_t *ctx, luat_netdrv_dns_cfg_t *out);

void luat_netdrv_dns_stat_get(const luat_netdrv_dns_ctx_t *ctx, luat_netdrv_dns_stat_t *out);

/** 清空整个缓存. 切网卡 / 换 DNS 服务器 / DHCP 续约变更 DNS 列表时必须调用 */
void luat_netdrv_dns_cache_flush(luat_netdrv_dns_ctx_t *ctx);

/**
 * 只清掉某张网卡的缓存条目.
 *
 * share=0(默认)时应优先用这个: 链路断开 / 该网卡换了 DNS 服务器时,
 * 影响面只是这张网卡自己的解析视图, 没必要把别的网卡的有效缓存一起废掉。
 * share=1 时所有条目都归在 owner=0, 本函数等价于 luat_netdrv_dns_cache_flush。
 */
void luat_netdrv_dns_cache_flush_adapter(luat_netdrv_dns_ctx_t *ctx, uint8_t adapter_index);

/**
 * 是否还有未完成的工作(在途 + 排队 + 退避等待中的事务).
 *
 * 适配层的定时器起停必须问这个, 不能只看 stat.inflight:
 * stat.inflight 只统计"已发出、等应答"的事务, 排队中的不算.
 * 只要出现"最后一个在途事务刚完成、同时令牌桶恰好被掏空"的时刻,
 * 只看 inflight 会让定时器停掉, 而队列里还有没发出去的事务 —— 它们既不会
 * 被 pump 发出(没人再调 pump), 也不会被 sweep 超时回收(从未发出, 没有 deadline),
 * 表现为应用侧 DNS 查询永久挂起, 直到碰巧有下一个 DNS 事件把它顺带唤醒.
 */
uint8_t luat_netdrv_dns_has_pending(const luat_netdrv_dns_ctx_t *ctx);

/**
 * 当前是否应当让调度定时器保持运行. 等价于"还有未完成的事务"(= has_pending).
 *
 * 【为什么适配层不能只判 stat.inflight】
 * stat.inflight 只统计"已发出、等应答"的事务, 排队中的(query_sent==0)不算.
 * 反例(默认配置 max_inflight=8 / min_gap=20ms):
 *   t=0    8 条并发瞬间发出, 令牌桶被掏空(token=0), 队列假设还有 N 条;
 *   t=1..7 每来一个应答, pump 补 1 个令牌、放行 1 条, 令牌收支恰好为 0
 *          (RX 驱动的 pump 频率远高于 20ms 定时器, 见 dns_token_refill 的
 *           elapsed*cap/gap 取整);
 *   t=8    第 8 个应答到达: inflight 归零, 若此刻 token==0, pump 在
 *          "token == 0" 处直接 break, 队列里仍有 N 条没发;
 *          只看 inflight 的门控会在这里 platform_stop_timer。
 *   之后没有任何机制再调 pump: sweep_timeouts 跳过 !query_sent 的事务
 *   (它们从未发出, 连 deadline_ms 都没有), 于是这些查询永久挂起,
 *   直到碰巧有下一个 DNS 事件把它顺带唤醒。
 *
 * 用 has_pending 就安全: 只要还有事务(不论在途/排队/退避), 定时器就在跑,
 * 每个 period(<=100ms)补一次令牌; 补满整桶最多 min_gap_ms(<=1000ms),
 * 对应最多 ceil(min_gap/period) 个 tick。期间没有东西能在 has_pending 为真时
 * 停掉定时器, 所以队列一定会被推进。空闲(无事务)时照常停表, 省电语义不变。
 *
 * 注意不要在这里附加"token > 0"之类的条件: 桶闲置 min_gap_ms 后必然被补满
 * 到 cap(>=1), token 恒 > 0, 条件会退化成恒真、定时器永不停, 白白空转。
 */
uint8_t luat_netdrv_dns_should_schedule(const luat_netdrv_dns_ctx_t *ctx);

/**
 * pump 最近一次执行时的"待发队列深度"(query_sent==0 且未完成的事务数).
 * 从事务链表现算, 只用于诊断/测试断言。
 * "队列深度长期 > 0 而 inflight == 0" 就是停摆的指纹。
 */
uint16_t luat_netdrv_dns_queued(const luat_netdrv_dns_ctx_t *ctx);

/**
 * 当前在途事务数(已发出、等应答), 从事务链表现算。
 *
 * 与 stat.inflight 的区别很重要: stat.inflight 是 pump 末尾写的快照, 只有调过
 * pump 才更新, 不调 pump 时读到的是旧值(真机测试曾据此误判"仍有 8 个在途")。
 * 需要"此刻真实在途数"时用本函数。门控本身不要依赖任何 inflight 数字 —— 用
 * should_schedule。
 */
uint16_t luat_netdrv_dns_inflight(const luat_netdrv_dns_ctx_t *ctx);

/** 把统计计数清零(不改变配置, 也不清缓存) */
void luat_netdrv_dns_stat_reset(luat_netdrv_dns_ctx_t *ctx);

#endif /* LUAT_USE_NETDRV_DNS_CLIENT */

#endif /* __LUAT_NETDRV_DNS_H__ */
