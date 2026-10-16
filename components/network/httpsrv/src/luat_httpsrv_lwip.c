/*
 * httpsrv 的 lwIP 传输后端(真机).
 *
 * 只负责字节搬运: tcp_new/bind/listen/accept + pcb 收发 + tcp_sent 流控.
 * HTTP 语义全部在 luat_httpsrv_http.c, 两端共用, 保证真机与 PC 行为一致.
 */

#include "luat_base.h"
#include "luat_msgbus.h"
#include "luat_mem.h"
#include "luat_rtos.h"
#include "luat_httpsrv.h"
#include "luat_fs.h"

#include "lwip/opt.h"
#include "lwip/tcp.h"
#include "lwip/ip_addr.h"
#include "lwip/tcpip.h"
#include "lwip/netif.h"

#define LUAT_LOG_TAG "httpsrv"
#include "luat_log.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "http_parser.h"

extern int g_httpsrv_debug;
#define HTTPSRV_DBG(...) if (g_httpsrv_debug) LLOGD(__VA_ARGS__)

static int lwip_cli_serve_static(client_socket_ctx_t* client, const char* path, size_t len);

//================================
// vtable: 传输相关操作

static int lwip_cli_send(client_socket_ctx_t* client, const char* buff, size_t len) {
    if (len == 0)
        return 0;
    struct tcp_pcb* pcb = (struct tcp_pcb*)client->hconn;
    int ret = 0;
#if ENABLE_PSIF
    #if defined(CHIP_EC618)
    ret = tcp_write(pcb, (const void*)buff, len, TCP_WRITE_FLAG_COPY, 0, 0, 0);
    #else
    sockdataflag_t dataflag={0};
	dataflag.bExceptData=0;
    dataflag.dataRai=0;
    ret = tcp_write(pcb, (const void*)buff, len, TCP_WRITE_FLAG_COPY, dataflag, 0);
    #endif
#else
    ret = tcp_write(pcb, (const void*)buff, len, TCP_WRITE_FLAG_COPY);
#endif
    if (ret == 0) {
        // send_size 必须在这里累计: client_sent_cb 靠 write_done && send_size == sent_size
        // 判断"这条连接是否已发完并可以回收", 漏掉会让连接永远不关闭、client ctx 永远不释放.
        client->send_size += len;
        HTTPSRV_DBG("send more %d/%d", client->sent_size, client->send_size);
        return 0;
    }
    LLOGE("client_write err %d", ret);
    return -1;
}

static void client_close_cb(void* arg) {
    struct tcp_pcb* pcb = (struct tcp_pcb*)arg;
    tcp_close(pcb);
}

static void lwip_cli_cleanup(client_socket_ctx_t* client) {
    struct tcp_pcb* pcb = (struct tcp_pcb*)client->hconn;
    if (pcb) {
        tcp_err(pcb, NULL);
        tcp_sent(pcb, NULL);
        tcp_recv(pcb, NULL);
        tcp_arg(pcb, NULL);
        if (tcpip_callback(client_close_cb, pcb) != ERR_OK) {
            tcp_close(pcb);
        }
        client->hconn = NULL;
    }
}

// Lua 回调在 Lua 线程跑完, 这里把写操作切回 tcpip 线程
static void client_dispatch_cb(void* arg) {
    client_socket_ctx_t* client = (client_socket_ctx_t*)arg;
    if (client->discard) {
        // 回调已被 GC, 不用发响应, 直接回收
        luat_httpsrv_client_cleanup(client);
        return;
    }
    luat_httpsrv_send_response(client);
    tcp_output((struct tcp_pcb*)client->hconn);
}

static int lwip_cli_dispatch_resp(client_socket_ctx_t* client) {
    if (tcpip_callback(client_dispatch_cb, client) != ERR_OK) {
        return -1;
    }
    return 0;
}

//================================
// client methods

static err_t client_recv_cb(void *arg, struct tcp_pcb *tpcb,
                             struct pbuf *p, err_t err) {
    if (err) {
        HTTPSRV_DBG("tpcb %p err %d", tpcb, err);
        return ERR_OK;
    }
    if (arg == NULL) {
        tcp_abort(tpcb);
        return ERR_ABRT;
    }
    HTTPSRV_DBG("client_recv_cb tpcb %p p %p err %d arg %p", tpcb, p, err, arg);
    client_socket_ctx_t* ctx = (client_socket_ctx_t*)arg;
    if (p == NULL) {
        HTTPSRV_DBG("recv p is NULL");
        tcp_arg(tpcb, NULL);
        tcp_abort(tpcb);
        ctx->hconn = NULL;
        luat_httpsrv_client_cleanup(ctx);
        return ERR_ABRT;
    }
    HTTPSRV_DBG("tpcb %p p %p len %d err %d", tpcb, p, p->tot_len, err);
    if (ctx->buff == NULL) {
        ctx->buff = luat_heap_malloc(p->tot_len);
        if (ctx->buff == NULL) {
            LLOGW("out of memory when malloc client buff %d", p->tot_len);
            pbuf_free(p); // 需要吗?
            tcp_arg(tpcb, NULL);
            tcp_abort(tpcb);
            ctx->hconn = NULL;
            luat_httpsrv_client_cleanup(ctx);
            return ERR_ABRT;
        }
        ctx->buff_offset = 0;
        ctx->buff_size = p->tot_len;
    }
    if (ctx->buff_size < p->tot_len) {
        char* ptr = luat_heap_realloc(ctx->buff, p->tot_len + 1);
        if (ptr == NULL) {
            LLOGW("out of memory when realloc client buff %d", p->tot_len);
            luat_heap_free(ctx->buff);
            ctx->buff = NULL;
            tcp_arg(tpcb, NULL);
            tcp_abort(tpcb);
            ctx->hconn = NULL;
            luat_httpsrv_client_cleanup(ctx);
            return ERR_ABRT;
        }
        ctx->buff_offset = 0;
        ctx->buff = ptr;
        ctx->buff_size = p->tot_len;
    }
    pbuf_copy_partial(p, ctx->buff, p->tot_len, 0);
    ctx->buff_offset = p->tot_len;
    HTTPSRV_DBG("request %.*s", p->len, p->payload);
    tcp_recved(tpcb, p->tot_len);

    // http_parser 已在连接建立时初始化，这里只需执行解析
    luat_httpsrv_parser_exec(ctx, (const char*)ctx->buff, ctx->buff_offset);
    if (ctx->parser.http_errno != HPE_OK) {
        LLOGW("parser errno %d != HPE_OK", ctx->parser.http_errno);
        tcp_arg(tpcb, NULL);
        tcp_abort(tpcb);
        ctx->hconn = NULL;
        luat_httpsrv_client_cleanup(ctx);
        return ERR_ABRT;
    }
    pbuf_free(p);
    p = NULL;

    if (ctx->recv_done) {
        // 停止接收更多的数据
        tcp_recv(tpcb, NULL);
        luat_heap_free(ctx->buff);
        ctx->buff = NULL;
        HTTPSRV_DBG("http request is ready");
        if (ctx->parser.http_errno != HPE_OK || ctx->uri == NULL) {
            LLOGI("bad request, close socket %d", ctx->parser.http_errno);
            tcp_arg(tpcb, NULL);
            tcp_abort(tpcb);
            ctx->hconn = NULL;
            luat_httpsrv_client_cleanup(ctx);
            return ERR_OK;
        }
        ctx->recv_done = 0;
        // 命中静态文件时后端自行发送(含流式), 返回 1 表示已处理
        if (luat_httpsrv_dispatch_request(ctx)) {
            // tcp_close(tpcb);
            return ERR_OK;
        }
    }
    else {
        HTTPSRV_DBG("wait more data");
    }

    return ERR_OK;
}

static err_t client_sent_cb(void *arg, struct tcp_pcb *tpcb, u16_t len) {
    (void)tpcb;
    client_socket_ctx_t* ctx = (client_socket_ctx_t*)arg;
    if (ctx == NULL) {
        return ERR_OK;
    }
    ctx->sent_size += len;
    int ret = 0;
    if (ctx->fd) {
        if (ctx->sbuff_offset) {
            ret = lwip_cli_send(ctx, (const char*)ctx->sbuff, ctx->sbuff_offset);
            if (ret == 0) {
                ctx->sbuff_offset = 0;
            }
        }
        else {
            while (tcp_sndbuf(tpcb) > 1400)
            {
                ret = luat_fs_fread(ctx->sbuff, 1400, 1, ctx->fd);
                if (ret < 1) {
                    luat_fs_fclose(ctx->fd);
                    ctx->fd = NULL;
                    ctx->write_done = 1;
                    break;
                }
                else {
                    ctx->sbuff_offset = ret;
                    ret = lwip_cli_send(ctx, (const char*)ctx->sbuff, ctx->sbuff_offset);
                    ctx->sbuff_offset = 0;
                }
            }
        }
    }
    HTTPSRV_DBG("done? %d sent %d/%d", ctx->write_done, ctx->sent_size, ctx->send_size);
    if (ctx->write_done && ctx->send_size == ctx->sent_size) {
        luat_httpsrv_client_cleanup(ctx);
    }
    return ERR_OK;
}

static void client_err_cb(void *arg, err_t err) {
    HTTPSRV_DBG("client_err_cb %d", err);
    if (arg == NULL) {
        return;
    }
    client_socket_ctx_t* client = (client_socket_ctx_t*)arg;
    if(ERR_RST == err && client->hconn)
    {
        struct tcp_pcb* pcb = (struct tcp_pcb*)client->hconn;
        tcp_err(pcb, NULL);
        tcp_sent(pcb, NULL);
        tcp_recv(pcb, NULL);
    }
    client->hconn = NULL;
    luat_httpsrv_client_cleanup(client);
}

static err_t srv_accept_cb(void *arg, struct tcp_pcb *newpcb, err_t err) {
    if (err) {
        HTTPSRV_DBG("accpet err %d", err);
        tcp_abort(newpcb);
        return ERR_OK;
    }
    HTTPSRV_DBG("srv_accept_cb newpcb %p err %d", newpcb, err);
    luat_httpsrv_ctx_t* srvctx = (luat_httpsrv_ctx_t*) arg;
    client_socket_ctx_t* ctx = luat_heap_malloc(sizeof(client_socket_ctx_t));
    if (ctx == NULL) {
        HTTPSRV_DBG("out of memory when malloc client ctx");
        tcp_abort(newpcb);
        return ERR_ABRT;
    }
    memset(ctx, 0, sizeof(client_socket_ctx_t));
    ctx->vt = srvctx->vt;
    ctx->hconn = newpcb;
    ctx->lua_ref_id = srvctx->lua_ref_id;
    // 在连接建立时初始化 http_parser，而非每次收到数据时
    luat_httpsrv_parser_init(ctx);
    tcp_arg(newpcb, ctx);
    tcp_recv(newpcb, client_recv_cb);
    tcp_sent(newpcb, client_sent_cb);
    tcp_err(newpcb, client_err_cb);
    tcp_accepted(newpcb);
    return ERR_OK;
}

// 静态文件: 先发头, 再把文件句柄挂上, 后续由 client_sent_cb 流式发送
static int lwip_cli_serve_static(client_socket_ctx_t* client, const char* path, size_t len) {
    luat_httpsrv_send_static_head(client, path, len);
    FILE* fd = luat_fs_fopen(path, "rb");
    if (fd == NULL) {
        struct tcp_pcb* pcb = (struct tcp_pcb*)client->hconn;
        tcp_recv(pcb, NULL);
        tcp_sent(pcb, NULL);
        if (tcp_close(pcb)) {
            tcp_abort(pcb);
        }
        LLOGE("open %s FAIL!!", path);
        return 1;
    }
    client->fd = fd;
    client->sbuff_offset = 0;
    return 1;
}

static void srv_stop_cb(void* arg) {
    luat_httpsrv_ctx_t* ctx = (luat_httpsrv_ctx_t*)arg;
    if (ctx == NULL) {
        return;
    }
    if (ctx->hlisten) {
        // 监听状态的pcb没有recv/sent回调, 对LISTEN态设置会触发lwip断言, 直接close
        struct tcp_pcb* pcb = (struct tcp_pcb*)ctx->hlisten;
        if (tcp_close(pcb)) {
            tcp_abort(pcb);
        }
        ctx->hlisten = NULL;
    }
    luat_httpsrv_free(ctx);
}

static void luat_httpsrv_start_cb(luat_httpsrv_ctx_t* ctx) {
    struct tcp_pcb* tcp = tcp_new();
    int ret = 0;
    if (tcp == NULL) {
        HTTPSRV_DBG("out of memory when malloc httpsrv tcp_pcb");
        ctx->start_ret = -1;
        goto start_done;
    }
    tcp->flags |= SOF_REUSEADDR;
    // priv为NULL时绑定0.0.0.0(IP_ADDR_ANY), 接受全部网卡上的连接
    struct netif* netif = (struct netif*)ctx->priv;
    ret = tcp_bind(tcp, netif ? &netif->ip_addr : IP_ADDR_ANY, ctx->port);
    if (ret) {
        LLOGE("httpsrv bind port %d ret %d", ctx->port, ret);
        tcp_close(tcp);
        ctx->start_ret = ret;
        goto start_done;
    }
    ctx->hlisten = tcp_listen_with_backlog(tcp, 4);
    if (ctx->hlisten == NULL) {
        LLOGE("httpsrv listen port %d failed", ctx->port);
        tcp_close(tcp);
        ctx->start_ret = -1;
        goto start_done;
    }
    tcp_arg((struct tcp_pcb*)ctx->hlisten, ctx);
    tcp_accept((struct tcp_pcb*)ctx->hlisten, srv_accept_cb);
    ctx->start_ret = 0;
start_done:
    if (ctx->start_sem) {
        luat_rtos_semaphore_release(ctx->start_sem);
    }
    return;
}

static int lwip_srv_start(luat_httpsrv_ctx_t* ctx) {
    int ret = tcpip_callback(luat_httpsrv_start_cb, ctx);
    if (ret) {
        LLOGE("启动失败 %d", ret);
    }
    return ret;
}

static void lwip_srv_stop(luat_httpsrv_ctx_t* ctx) {
    tcpip_callback(srv_stop_cb, ctx);
}

static const char* lwip_srv_local_ip(luat_httpsrv_ctx_t* ctx, char* buff, size_t len) {
    struct netif* netif = (struct netif*)ctx->priv;
    if (netif) {
        return ipaddr_ntoa_r(&netif->ip_addr, buff, (int)len);
    }
    if (len >= 8) {
        memcpy(buff, "0.0.0.0", 8);
        return buff;
    }
    return NULL;
}

//================================
// 后端入口(放在文件末尾: vtable 要引用上面全部函数)

const luat_httpsrv_transport_t luat_httpsrv_transport_lwip = {
    .name = "lwip",
    .srv_start = lwip_srv_start,
    .srv_stop = lwip_srv_stop,
    .srv_local_ip = lwip_srv_local_ip,
    .cli_send = lwip_cli_send,
    .cli_close = NULL,
    .cli_dispatch_resp = lwip_cli_dispatch_resp,
    .cli_serve_static = lwip_cli_serve_static,
    .cli_cleanup = lwip_cli_cleanup,
};
