#ifndef LUAT_HTTPSRV_TRANSPORT_H
#define LUAT_HTTPSRV_TRANSPORT_H

#include "luat_base.h"
#include <stddef.h>

struct luat_httpsrv_ctx;
struct client_socket_ctx;

/*
 * httpsrv 传输后端契约.
 *
 * PC 模拟器上有两套互不连通的 TCP/IP 协议栈:
 *   A. lwIP 2.2 (components/network/lwip22)  —— 真机用它, PC 上没有 netif, 是一座孤岛
 *   B. 宿主 OS 协议栈 (winsock/BSD)          —— PC 上有真实局域网 IP, 浏览器走这条
 * 而 HTTP 语义(请求解析/静态文件路由/响应拼装/Lua 派发)与栈无关, 统一放在 luat_httpsrv_http.c,
 * 两个后端只负责字节搬运.
 *
 * 约定:
 *  - srv_start 失败必须返回非 0, 由它决定 httpsrv.start() 返回 false. 绝不允许"监听成功
 *    但没人能把包送进来"的假成功.
 *  - cli_send 成功返回 0, 失败返回 -1(连接已断).
 *  - 所有函数都在后端自己的线程上下文里跑, 共享层只通过 luat_msgbus 切到 Lua 线程.
 */
typedef struct luat_httpsrv_transport
{
    const char* name;

    /* ---- 服务端 ---- */

    /* 绑定端口并开始监听. 0=成功, 非0=失败 */
    int (*srv_start)(struct luat_httpsrv_ctx* ctx);
    /* 请求停止监听(需能被 accept/poll 循环及时唤醒) */
    void (*srv_stop)(struct luat_httpsrv_ctx* ctx);
    /* 日志用本地地址; 返回 NULL 表示未知 */
    const char* (*srv_local_ip)(struct luat_httpsrv_ctx* ctx, char* buff, size_t len);

    /* ---- 客户端 ---- */

    /* 发送全部数据, 并在本层维护 send_size 累计量(连接收尾据此判断是否已发完).
       成功返回 0, 失败返回 -1 */
    int (*cli_send)(struct client_socket_ctx* client, const char* buff, size_t len);
    /* 关闭连接 */
    void (*cli_close)(void* hconn);
    /* Lua 回调返回后调用: 把响应写到"拥有该连接的线程"上执行 */
    int (*cli_dispatch_resp)(struct client_socket_ctx* client);
    /* 命中静态文件, 由后端自行(含流式)发送; 返回 1 表示已处理 */
    int (*cli_serve_static)(struct client_socket_ctx* client, const char* path, size_t len);
    /* 清理该连接在传输层的资源(不释放 client 本身) */
    void (*cli_cleanup)(struct client_socket_ctx* client);
} luat_httpsrv_transport_t;

/* 真机 lwIP 后端(components/network/httpsrv/src/luat_httpsrv_lwip.c) */
extern const luat_httpsrv_transport_t luat_httpsrv_transport_lwip;
/* PC 宿主 socket 后端(components/network/httpsrv/src/luat_httpsrv_posix.c) */
extern const luat_httpsrv_transport_t luat_httpsrv_transport_posix;

#endif // LUAT_HTTPSRV_TRANSPORT_H
