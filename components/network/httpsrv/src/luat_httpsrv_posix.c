/*
 * httpsrv 的 PC 传输后端(宿主 OS socket).
 *
 * 为什么需要它: PC 模拟器上有两套互不连通的 TCP/IP 协议栈.
 *   A. lwIP 2.2 —— 模拟器内那一套. PC 上没有任何 netif_add, 是座孤岛;
 *   B. 宿主 OS 协议栈(winsock/BSD) —— 有真实局域网 IP, 浏览器访问的就是这一套.
 * 真机的 httpsrv 绑在 A 上, 而 PC 上开发者用手机浏览器打的是 B,
 * 两套栈之间没有任何字节通路, 于是 httpsrv 在 PC 上"监听成功但永远收不到连接".
 *
 * 所以 PC 走本文件: 直接用宿主 socket 监听, 浏览器能真的访问到.
 * HTTP 语义(解析/静态文件/响应拼装/Lua 派发)在 luat_httpsrv_http.c, 与 lwIP 后端共用,
 * 保证 PC 上跑出来的行为和真机一致.
 *
 * 并发模型: 一个监听线程 poll() accept, 每条连接派生一个 detached 线程.
 * 阻塞 socket 自带背压, 不需要 lwIP 那套 tcp_sent 流控状态机.
 *
 * 整个文件被 LUAT_HTTPSRV_POSIX_BACKEND 包起来: 固件的编译脚本在 luat-soc-* 仓库里,
 * 通常用 components/network/httpsrv/src/*.c 通配收集源文件. 没有这个开关的话固件也会
 * 尝试编译本文件, 而 luat_posix_compat.h 只存在于 bsp/pc 下, 会直接编译失败.
 * 该宏由 bsp/pc/xmake.lua 在"确实把这个文件加进编译列表"的同一条件下定义, 两者必须一致.
 * ISO C 要求空翻译单元至少有一个声明, 所以留一个 typedef 占位.
 */

#if defined(LUAT_HTTPSRV_POSIX_BACKEND)

#include "luat_base.h"
#include "luat_mem.h"
#include "luat_httpsrv.h"
#include "luat_fs.h"
#include "luat_posix_compat.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#if defined(_WIN32) || defined(_WIN64)
typedef SOCKET       srv_fd_t;
typedef WSAPOLLFD    srv_pollfd_t;
#define SRV_INVALID_FD      INVALID_SOCKET
#define srv_close(fd)       closesocket(fd)
#define srv_errno()         WSAGetLastError()
#define srv_poll(fds, n, to) WSAPoll((fds), (n), (to))
#else
#include <sys/socket.h>
#include <netinet/in.h>
#include <arpa/inet.h>
#include <poll.h>
typedef int         srv_fd_t;
typedef struct pollfd srv_pollfd_t;
#define SRV_INVALID_FD      (-1)
#define srv_close(fd)       close(fd)
#define srv_errno()         errno
#define srv_poll(fds, n, to) poll((fds), (n), (to))
#endif

#define LUAT_LOG_TAG "httpsrv"
#include "luat_log.h"

extern int g_httpsrv_debug;
#define HTTPSRV_DBG(...) if (g_httpsrv_debug) LLOGD(__VA_ARGS__)

#define HTTPSRV_MAX_CONN     16      // 在飞连接上限, 超限回 503 不排队
#define HTTPSRV_BACKLOG      16
#define HTTPSRV_POLL_MS      100     // 监听线程轮询节拍, stop 最多延迟这么久
#define HTTPSRV_RECV_BUF     4096
#define HTTPSRV_SEND_CHUNK   1400
#define HTTPSRV_RECV_TIMEOUT_MS 10000 // 单连接收完整请求的上限, 防"连上不说话"占死槽位
#define HTTPSRV_RESP_WAIT_MS 10000   // 等 Lua 回调返回的最长时间
#define HTTPSRV_STOP_WAIT_MS 1000    // stop 等待监听 fd 真正关闭的上限

/* 服务端私有数据. refcnt: 监听线程持 1, 每条在飞连接再各持 1 */
typedef struct posix_srv {
    luat_httpsrv_ctx_t* ctx;
    srv_fd_t listen_fd;
    pthread_mutex_t lock;
    pthread_cond_t  closed_cond;   // 监听 fd 已关闭时通知 stop 侧
    int stop;
    int conn_cnt;
    int refcnt;
} posix_srv_t;

/* 连接级私有数据: Lua 线程与客户端线程之间的应答握手 */
typedef struct posix_conn {
    posix_srv_t* srv;        // 所属服务端, 线程退出时归还引用
    pthread_mutex_t lock;
    pthread_cond_t  cond;
    int resp_ready;   // Lua 线程已处理完回调, 可以写响应了
} posix_conn_t;

static int posix_wsa_init(void) {
#if defined(_WIN32) || defined(_WIN64)
    static int inited = 0;
    if (!inited) {
        WSADATA wd;
        if (WSAStartup(MAKEWORD(2,2), &wd) != 0) {
            return -1;
        }
        inited = 1;
    }
#endif
    return 0;
}

static int start_detached_thread(void* (*fn)(void*), void* arg) {
    pthread_t tid;
    pthread_attr_t attr;
    int ret;
    pthread_attr_init(&attr);
    pthread_attr_setdetachstate(&attr, PTHREAD_CREATE_DETACHED);
    ret = pthread_create(&tid, &attr, fn, arg);
    pthread_attr_destroy(&attr);
    if (ret != 0) {
        LLOGE("pthread_create failed, ret=%d", ret);
    }
    return ret;
}

// 最后一个持有者负责释放: posix_srv_t 与它绑定的 ctx 同生共死
static void posix_srv_release(posix_srv_t* srv) {
    pthread_mutex_lock(&srv->lock);
    srv->refcnt--;
    int dead = (srv->refcnt <= 0);
    pthread_mutex_unlock(&srv->lock);
    if (!dead) {
        return;
    }
    pthread_cond_destroy(&srv->closed_cond);
    pthread_mutex_destroy(&srv->lock);
    luat_httpsrv_free(srv->ctx);
    luat_heap_free(srv);
    HTTPSRV_DBG("posix srv released");
}

//================================
// vtable

static int posix_cli_send(client_socket_ctx_t* client, const char* buff, size_t len) {
    if (len == 0)
        return 0;
    srv_fd_t fd = (srv_fd_t)(intptr_t)client->hconn;
    size_t sent = 0;
    while (sent < len) {
        int n = (int)send(fd, buff + sent, (int)(len - sent), 0);
        if (n <= 0) {
            HTTPSRV_DBG("send fail, sent %d/%d", sent, len);
            return -1;
        }
        sent += (size_t)n;
    }
    // 与 lwIP 后端保持同一套收发计数口径
    client->send_size += len;
    return 0;
}

static void posix_cli_close(void* hconn) {
    if (hconn == NULL)
        return;
    srv_close((srv_fd_t)(intptr_t)hconn);
}

// 响应由"拥有该连接的客户端线程"写出, 这里只做握手唤醒
static int posix_cli_dispatch_resp(client_socket_ctx_t* client) {
    posix_conn_t* pc = (posix_conn_t*)client->priv;
    if (pc == NULL) {
        return -1;
    }
    pthread_mutex_lock(&pc->lock);
    pc->resp_ready = 1;
    pthread_cond_signal(&pc->cond);
    pthread_mutex_unlock(&pc->lock);
    return 0;
}

static int posix_cli_serve_static(client_socket_ctx_t* client, const char* path, size_t len) {
    luat_httpsrv_send_static_head(client, path, len);
    FILE* fd = luat_fs_fopen(path, "rb");
    if (fd == NULL) {
        LLOGE("open %s FAIL!!", path);
        return 1;
    }
    // 阻塞 socket: 循环读文件直接写出, 发完即止
    char buff[HTTPSRV_SEND_CHUNK];
    size_t total = 0;
    while (total < len) {
        // 注意 fread 的语义是"读了多少字节", 与 lwIP 后端里按"元素数"取返回值的写法不同
        size_t r = (size_t)luat_fs_fread(buff, 1, sizeof(buff), fd);
        if (r == 0) {
            break;
        }
        if (posix_cli_send(client, buff, r) != 0) {
            break;
        }
        total += r;
    }
    luat_fs_fclose(fd);
    client->write_done = 1;
    HTTPSRV_DBG("static %s sent %d/%d", path, total, len);
    return 1;
}

static void posix_cli_cleanup(client_socket_ctx_t* client) {
    if (client->hconn) {
        posix_cli_close(client->hconn);
        client->hconn = NULL;
    }
    if (client->priv) {
        posix_conn_t* pc = (posix_conn_t*)client->priv;
        client->priv = NULL;
        pthread_mutex_destroy(&pc->lock);
        pthread_cond_destroy(&pc->cond);
        luat_heap_free(pc);
    }
}

static const char* posix_srv_local_ip(luat_httpsrv_ctx_t* ctx, char* buff, size_t len) {
    (void)ctx;
    // 绑的是 0.0.0.0(全部网卡), 具体访问地址由局域网 IP 决定
    if (len >= 8) {
        memcpy(buff, "0.0.0.0", 8);
        return buff;
    }
    return NULL;
}

//================================
// 客户端线程

static void* posix_client_thread(void* arg) {
    client_socket_ctx_t* client = (client_socket_ctx_t*)arg;
    posix_conn_t* pc = (posix_conn_t*)client->priv;
    posix_srv_t* srv = pc ? pc->srv : NULL;

    char* rbuff = luat_heap_malloc(HTTPSRV_RECV_BUF);
    if (rbuff == NULL) {
        LLOGE("out of memory when alloc recv buffer");
        goto done;
    }

    while (!client->recv_done) {
        // 服务已在停止时, 不要继续占着连接槽位空等
        if (srv && srv->stop) {
            HTTPSRV_DBG("server stopping, abort recv");
            break;
        }
        int n = (int)recv((srv_fd_t)(intptr_t)client->hconn, rbuff, HTTPSRV_RECV_BUF, 0);
        if (n <= 0) {
            HTTPSRV_DBG("recv done/err %d", n);
            break;
        }
        luat_httpsrv_parser_exec(client, rbuff, (size_t)n);
        if (client->parser.http_errno != HPE_OK) {
            LLOGW("parser errno %d != HPE_OK", client->parser.http_errno);
            break;
        }
    }
    luat_heap_free(rbuff);
    rbuff = NULL;

    if (!client->recv_done || client->uri == NULL) {
        LLOGI("bad request, close socket");
        goto done;
    }

    // 静态文件命中时后端自行发完; 未命中则派发到 Lua 线程
    if (luat_httpsrv_dispatch_request(client)) {
        goto done;
    }

    // 等 Lua 线程跑完回调
    pthread_mutex_lock(&pc->lock);
    while (!pc->resp_ready) {
        struct timespec abs;
        luat_calc_abs_timeout(&abs, HTTPSRV_RESP_WAIT_MS);
        if (pthread_cond_timedwait(&pc->cond, &pc->lock, &abs) != 0) {
            break;
        }
    }
    int ready = pc->resp_ready;
    pthread_mutex_unlock(&pc->lock);

    if (!ready) {
        // Lua 线程没能应答(回调耗时超过 HTTPSRV_RESP_WAIT_MS).
        // 这里绝不能走 posix_cli_cleanup: 它会 free 掉 pc, 而 Lua 线程随后还会通过
        // client->priv 访问 pc 去 signal, 那就是 use-after-free.
        // 正确做法是只关连接, 把 client 与 pc 一起泄漏掉 —— 与 luat_lib_httpsrv.c 里
        // start 超时的处理保持同一口径(宁可泄漏也不能误伤).
        LLOGE("wait lua response timeout, leak client %p", client);
        posix_cli_close(client->hconn);
        client->hconn = NULL;
        goto release;
    }

    if (!client->discard) {
        luat_httpsrv_send_response(client);
    }

done:
    luat_httpsrv_client_cleanup(client);

release:
    if (srv) {
        pthread_mutex_lock(&srv->lock);
        srv->conn_cnt--;
        pthread_mutex_unlock(&srv->lock);
        posix_srv_release(srv);
    }
    return NULL;
}

//================================
// 监听线程

static void* posix_accept_thread(void* arg) {
    posix_srv_t* srv = (posix_srv_t*)arg;
    luat_httpsrv_ctx_t* ctx = srv->ctx;

    while (1) {
        pthread_mutex_lock(&srv->lock);
        int stop = srv->stop;
        srv_fd_t fd = srv->listen_fd;
        pthread_mutex_unlock(&srv->lock);
        if (stop || fd == SRV_INVALID_FD) {
            break;
        }

        srv_pollfd_t pfd;
        pfd.fd = fd;
        pfd.events = POLLIN;
        pfd.revents = 0;
        int ret = srv_poll(&pfd, 1, HTTPSRV_POLL_MS);
        if (ret <= 0) {
            continue;   // 超时则回到循环顶部重新检查 stop
        }
        if (pfd.revents & (POLLERR | POLLNVAL | POLLHUP)) {
            // 不能在这里 break: 跳出循环会释放 ctx, 而 Lua 侧的 srvs[] 槽位仍指向它.
            // 只记录并继续, 正常关闭走顶部 stop 检查即可.
            HTTPSRV_DBG("poll revents %d, continue", pfd.revents);
            continue;
        }

        struct sockaddr_in cli_addr;
        socklen_t alen = sizeof(cli_addr);
        srv_fd_t cfd = accept(fd, (struct sockaddr*)&cli_addr, &alen);
        if (cfd == SRV_INVALID_FD) {
            continue;
        }

        // 接收超时: 否则一个"连上但什么都不发"的客户端会永久占住一个连接槽位,
        // 攒够 16 个之后整个服务对后续请求只剩 503, 且没有任何恢复路径.
        {
#if defined(_WIN32) || defined(_WIN64)
            DWORD tv = HTTPSRV_RECV_TIMEOUT_MS;
            setsockopt(cfd, SOL_SOCKET, SO_RCVTIMEO, (const char*)&tv, sizeof(tv));
#else
            struct timeval tv;
            tv.tv_sec = HTTPSRV_RECV_TIMEOUT_MS / 1000;
            tv.tv_usec = (HTTPSRV_RECV_TIMEOUT_MS % 1000) * 1000;
            setsockopt(cfd, SOL_SOCKET, SO_RCVTIMEO, &tv, sizeof(tv));
#endif
        }

        // 并发闸门: 超限直接回 503, 不排队(排队只会让浏览器长时间挂起)
        pthread_mutex_lock(&srv->lock);
        int over = (srv->conn_cnt >= HTTPSRV_MAX_CONN);
        if (!over) {
            srv->conn_cnt++;
            srv->refcnt++;     // 该连接线程持有一份引用
        }
        pthread_mutex_unlock(&srv->lock);
        if (over) {
            const char* busy = "HTTP/1.0 503 Service Unavailable\r\nContent-Length: 0\r\n"
                               "Connection: close\r\n\r\n";
            send(cfd, busy, (int)strlen(busy), 0);
            srv_close(cfd);
            LLOGW("too many connections (max %d), reject", HTTPSRV_MAX_CONN);
            continue;
        }

        client_socket_ctx_t* client = luat_heap_malloc(sizeof(client_socket_ctx_t));
        posix_conn_t* pc = luat_heap_malloc(sizeof(posix_conn_t));
        if (client == NULL || pc == NULL) {
            LLOGE("out of memory when malloc client ctx");
            if (client) luat_heap_free(client);
            if (pc) luat_heap_free(pc);
            srv_close(cfd);
            pthread_mutex_lock(&srv->lock);
            srv->conn_cnt--;
            srv->refcnt--;
            pthread_mutex_unlock(&srv->lock);
            continue;
        }
        memset(client, 0, sizeof(client_socket_ctx_t));
        memset(pc, 0, sizeof(posix_conn_t));
        pthread_mutex_init(&pc->lock, NULL);
        pthread_cond_init(&pc->cond, NULL);
        pc->resp_ready = 0;
        pc->srv = srv;

        client->vt = ctx->vt;
        client->hconn = (void*)(intptr_t)cfd;
        client->priv = pc;
        client->lua_ref_id = ctx->lua_ref_id;
        luat_httpsrv_parser_init(client);

        if (start_detached_thread(posix_client_thread, client) != 0) {
            LLOGE("start client thread failed");
            posix_cli_cleanup(client);
            luat_heap_free(client);
            pthread_mutex_lock(&srv->lock);
            srv->conn_cnt--;
            srv->refcnt--;
            pthread_mutex_unlock(&srv->lock);
        }
    }

    // 关闭监听 fd, 并通知 stop 侧"端口已经释放"
    // 关键: 关闭动作只在本线程做. stop 侧若跨线程 closesocket, 等于在 WSAPoll 正阻塞的
    // 那个句柄上关闭 socket —— Windows 明确未定义, POSIX 上则是经典的 fd 复用竞争.
    pthread_mutex_lock(&srv->lock);
    srv_fd_t fd = srv->listen_fd;
    srv->listen_fd = SRV_INVALID_FD;
    pthread_cond_broadcast(&srv->closed_cond);
    pthread_mutex_unlock(&srv->lock);
    if (fd != SRV_INVALID_FD) {
        srv_close(fd);
    }

    posix_srv_release(srv);
    return NULL;
}

//================================
// 服务端

static int posix_srv_start(luat_httpsrv_ctx_t* ctx) {
    int ret = 0;
    posix_srv_t* srv = NULL;
    srv_fd_t fd = SRV_INVALID_FD;

    if (posix_wsa_init() != 0) {
        LLOGE("wsa init failed");
        goto fail;
    }

    fd = socket(AF_INET, SOCK_STREAM, 0);
    if (fd == SRV_INVALID_FD) {
        LLOGE("socket() failed, err=%d", srv_errno());
        goto fail;
    }
    {
        // 注意: SO_REUSEADDR 在两个平台语义相反.
        //   POSIX: 允许在 TIME_WAIT 后快速重绑, 但仍禁止两个活跃监听共存 —— 需要设置.
        //   Windows: 允许另一个 socket"抢"同一 addr:port, 正是我们要禁止的行为.
        //            而 Windows 默认(不设置)已经是独占绑定, 且默认容忍 TIME_WAIT 重绑.
        // 所以这里只在 POSIX 上设置, Windows 上一个选项都不要碰.
        int opt = 1;
#if !defined(_WIN32) && !defined(_WIN64)
        setsockopt(fd, SOL_SOCKET, SO_REUSEADDR, &opt, sizeof(opt));
#else
        (void)opt;
#endif
    }
    struct sockaddr_in ba;
    memset(&ba, 0, sizeof(ba));
    ba.sin_family = AF_INET;
    ba.sin_port = htons(ctx->port);
    ba.sin_addr.s_addr = htonl(INADDR_ANY);   // 绑定全部网卡, 局域网手机可访问
    if (bind(fd, (struct sockaddr*)&ba, sizeof(ba)) != 0) {
        LLOGE("httpsrv bind 0.0.0.0:%d failed, err=%d", ctx->port, srv_errno());
        goto fail;
    }
    if (listen(fd, HTTPSRV_BACKLOG) != 0) {
        LLOGE("httpsrv listen 0.0.0.0:%d failed, err=%d", ctx->port, srv_errno());
        goto fail;
    }

    srv = luat_heap_malloc(sizeof(posix_srv_t));
    if (srv == NULL) {
        LLOGE("out of memory when malloc posix srv");
        goto fail;
    }
    memset(srv, 0, sizeof(posix_srv_t));
    srv->ctx = ctx;
    srv->listen_fd = fd;
    srv->stop = 0;
    srv->conn_cnt = 0;
    srv->refcnt = 1;             // 监听线程自己这一份
    pthread_mutex_init(&srv->lock, NULL);
    pthread_cond_init(&srv->closed_cond, NULL);

    ctx->hlisten = (void*)(intptr_t)fd;
    ctx->priv = srv;

    if (start_detached_thread(posix_accept_thread, srv) != 0) {
        LLOGE("start accept thread failed");
        pthread_mutex_destroy(&srv->lock);
        luat_heap_free(srv);
        srv = NULL;
        goto fail;
    }

    ctx->start_ret = 0;
    goto start_done;

fail:
    if (fd != SRV_INVALID_FD) {
        srv_close(fd);
    }
    ctx->priv = NULL;
    ctx->hlisten = NULL;
    ctx->start_ret = -1;

start_done:
    // 必须在一切就绪/失败都确定之后再放信号: l_httpsrv_start 醒来后会读 ctx->start_ret
    if (ctx->start_sem) {
        luat_rtos_semaphore_release(ctx->start_sem);
    }
    return ret;
}

// 注意: 本函数不释放 ctx —— ctx 由监听线程退出时释放(见 posix_accept_thread 末尾).
// 绝不能在这里 posix_srv_release(): 监听线程还持有自己那一份引用, 在它真正退出前
// 释放 ctx 会让它随后对已释放内存再操作一次(实测会崩在 posix_srv_release 里).
// 同理这里也不去 closesocket 监听 fd —— 那个句柄正被 WSAPoll 阻塞着, 跨线程关闭不安全.
static void posix_srv_stop(luat_httpsrv_ctx_t* ctx) {
    posix_srv_t* srv = (posix_srv_t*)ctx->priv;
    if (srv == NULL) {
        // start 从未成功建立(没有监听线程会来释放), 这里补释放
        luat_httpsrv_free(ctx);
        return;
    }
    pthread_mutex_lock(&srv->lock);
    srv->stop = 1;
    // 等监听线程醒来把端口真正关掉, 这样调用方 stop 返回后端口就是可用的
    // (与"stop 后立刻在同端口重启"的用法一致). 监听线程最多 HTTPSRV_POLL_MS 才醒一次.
    while (srv->listen_fd != SRV_INVALID_FD) {
        struct timespec abs;
        luat_calc_abs_timeout(&abs, HTTPSRV_STOP_WAIT_MS);
        if (pthread_cond_timedwait(&srv->closed_cond, &srv->lock, &abs) != 0) {
            break;
        }
    }
    pthread_mutex_unlock(&srv->lock);
}

//================================
// 后端入口

const luat_httpsrv_transport_t luat_httpsrv_transport_posix = {
    .name = "posix",
    .srv_start = posix_srv_start,
    .srv_stop = posix_srv_stop,
    .srv_local_ip = posix_srv_local_ip,
    .cli_send = posix_cli_send,
    .cli_close = posix_cli_close,
    .cli_dispatch_resp = posix_cli_dispatch_resp,
    .cli_serve_static = posix_cli_serve_static,
    .cli_cleanup = posix_cli_cleanup,
};

#else
/* 未启用宿主后端(例如固件通配到了本文件): 留一个声明, 避免空翻译单元 */
typedef int luat_httpsrv_posix_backend_not_enabled;
#endif /* LUAT_HTTPSRV_POSIX_BACKEND */
