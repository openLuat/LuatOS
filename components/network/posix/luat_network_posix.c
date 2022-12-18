#include "luat_base.h"
#include "luat_network_adapter.h"
#include "luat_malloc.h"
#include "luat_msgbus.h"
#include "luat_crypto.h"

#include <stdio.h>
#include <string.h>
#include <errno.h>
#include <netdb.h>
#include <signal.h>
#include <fcntl.h>
#include <sys/select.h>

#define LUAT_LOG_TAG "network"
#include "luat_log.h"

#include "luat_network_posix.h"

CBFuncEx_t posix_network_cb;
void * posix_network_param;
uint8_t posix_network_ready;

static luat_rtos_mutex_t* master_lock;

static void posix_send_event(int id, int p1, int p2, int p3) {
    luat_network_cb_param_t params = {0};
    params.tag = 0;
    params.param = posix_network_param;
    // 触发一下回调
    // if (ready) {
    OS_EVENT event = {
        .ID = id,
        .Param1 = p1,
        .Param2 = p2,
        .Param3 = p3
    };
    LLOGD("posix event %d %d %d %d", id, p1, p2, p3);
    posix_network_cb(&event, &params);
}

void posix_network_client_thread_entry(posix_socket_t *ps) {

    luat_network_cb_param_t params = {0};
    params.tag = 0;
    params.param = posix_network_param;
    // 触发一下回调
    // if (ready) {
    OS_EVENT event = {0};

    struct sockaddr_in sockaddr = {0};
    sockaddr.sin_family = AF_INET;
    sockaddr.sin_port = htons(ps->remote_port);
    sockaddr.sin_addr.s_addr = ps->remote_ip.ipv4;
    luat_rtos_task_sleep(50);

    LLOGD("ready to connect %d", ps->socket_id);
    int ret = connect(ps->socket_id, (struct sockaddr*)&sockaddr, sizeof(sockaddr));

    LLOGD("connect ret %d", ret);
    if (ret) {
        // 失败了
        LLOGD("connect FAIL ret %d", ret);
        posix_send_event(EV_NW_SOCKET_ERROR, ps->socket_id, 0, 0);
        luat_heap_free(ps);
        return;
    }
    // 发送系统消息, 通知连接成功
    posix_send_event(EV_NW_SOCKET_CONNECT_OK, ps->socket_id, 0, 0);
    LLOGD("wait data now");

    fd_set readfds;
    fd_set writefds;
    fd_set errorfds;
    int maxsock;
    struct timeval tv;
    maxsock = ps->socket_id;
    // timeout setting
    tv.tv_sec = 0;
    tv.tv_usec = 3000; //暂时3ms吧
    while (1) {
        // initialize file descriptor set
        FD_ZERO(&readfds);
        // FD_ZERO(&writefds);
        FD_ZERO(&errorfds);
        FD_SET(ps->socket_id, &readfds);
        // FD_SET(ps->socket_id, &writefds);
        FD_SET(ps->socket_id, &errorfds);

        if (master_lock)
            if (luat_rtos_mutex_lock(master_lock, 100))
                continue;
        ret = select(maxsock + 1, &readfds, NULL, &errorfds, &tv);
        if (master_lock)
            luat_rtos_mutex_unlock(master_lock);

        if (ret < 0) {
            LLOGE("select ret %d", ret);
            break;
        } else if (ret == 0) {
            //printf("select timeout\n");
            continue;
        }

        if (FD_ISSET(maxsock, &readfds)) {
            // 发消息,可读了
        }
        // if (FD_ISSET(maxsock, &writefds)) {
        //     // 发消息,发送完成了??
        // }
        if (FD_ISSET(maxsock, &errorfds)) {
            // 发消息,出错了
            break;
        }
    }

    luat_heap_free(ps);
    LLOGI("socket thread exit");
}

void posix_network_set_ready(uint8_t ready) {
    LLOGD("CALL posix_network_set_ready");
    posix_network_ready = ready;
    luat_network_cb_param_t params = {0};
    params.tag = 0;
    params.param = posix_network_param;
    // 触发一下回调
    // if (ready) {
        OS_EVENT event = {
            .ID = EV_NW_STATE,
            .Param1 = 0,
            .Param2 = ready,
            .Param3 = 0
        };
        posix_network_cb(&event, &params);
    // }
}

//检查网络是否准备好，返回非0准备好，user_data是注册时的user_data，传入给底层api
uint8_t (posix_check_ready)(void *user_data) {
    LLOGD("CALL posix_check_ready %d", posix_network_ready);
    return posix_network_ready;
};

//创建一个socket，并设置成非阻塞模式，user_data传入对应适配器, tag作为socket的合法依据，给check_socket_vaild比对用
//成功返回socketid，失败 < 0
int (posix_create_socket)(uint8_t is_tcp, uint64_t *tag, void *param, uint8_t is_ipv6, void *user_data) {
    // TODO 支持IPV6
    int s = socket(AF_INET, is_tcp ? SOCK_STREAM : SOCK_DGRAM, is_tcp ? IPPROTO_TCP : IPPROTO_UDP);
    LLOGD("CALL posix_create_socket %d %d", s, is_tcp);
    return s;
}

//作为client绑定一个port，并连接remote_ip和remote_port对应的server
//成功返回0，失败 < 0
int (posix_socket_connect)(int socket_id, uint64_t tag, uint16_t local_port, luat_ip_addr_t *remote_ip, uint16_t remote_port, void *user_data) {
    LLOGD("CALL posix_socket_connect %d", socket_id);
    posix_socket_t *ps = luat_heap_malloc(sizeof(posix_socket_t));
    if (ps == NULL) {
        LLOGE("out of memory when malloc posix_socket_t");
        return -1;
    }
    ps->socket_id = socket_id;
    ps->tag = tag;
    ps->local_port = local_port;
    memcpy(&ps->remote_ip, remote_ip, sizeof(luat_ip_addr_t));
    ps->remote_port = remote_port;
    ps->user_data = user_data;

    int ret = network_posix_client_thread_start(ps);
    LLOGD("socket thread start %d", ret);

    if (ret) {
        luat_heap_free(ps);
    }
    return ret;
}
//作为server绑定一个port，开始监听
//成功返回0，失败 < 0
int (posix_socket_listen)(int socket_id, uint64_t tag, uint16_t local_port, void *user_data) {
    // 尚未支持
    return -1;
}
//作为server接受一个client
//成功返回0，失败 < 0
int (posix_socket_accept)(int socket_id, uint64_t tag, luat_ip_addr_t *remote_ip, uint16_t *remote_port, void *user_data) {
    // 尚未支持
    return -1;
}

//主动断开一个tcp连接，需要走完整个tcp流程，用户需要接收到close ok回调才能确认彻底断开
//成功返回0，失败 < 0
int (posix_socket_disconnect)(int socket_id, uint64_t tag, void *user_data) {
    return close(socket_id);
}

//释放掉socket的控制权，除了tag异常外，必须立刻生效
//成功返回0，失败 < 0
int (posix_socket_close)(int socket_id, uint64_t tag, void *user_data) {
    return close(socket_id);
}

//强行释放掉socket的控制权，必须立刻生效
//成功返回0，失败 < 0
int (posix_socket_force_close)(int socket_id, void *user_data) {
    return close(socket_id);
}

//tcp时，不需要remote_ip和remote_port，如果buf为NULL，则返回当前缓存区的数据量，当返回值小于len时说明已经读完了
//udp时，只返回1个block数据，需要多次读直到没有数据为止
//成功返回实际读取的值，失败 < 0
int (posix_socket_receive)(int socket_id, uint64_t tag, uint8_t *buf, uint32_t len, int flags, luat_ip_addr_t *remote_ip, uint16_t *remote_port, void *user_data) {
    
    struct timeval tv;
    tv.tv_sec = 0;
    tv.tv_usec = 1000; //暂时1ms吧
    setsockopt(socket_id, SOL_SOCKET, SO_RCVTIMEO, &tv, sizeof(tv));

    if (master_lock)
        if (luat_rtos_mutex_lock(master_lock, 100))
            return -1;
    int ret = recv(socket_id, buf, len, flags);
    if (master_lock)
        luat_rtos_mutex_unlock(master_lock);
    return ret;
}

//tcp时，不需要remote_ip和remote_port
//成功返回>0的len，缓冲区满了=0，失败 < 0，如果发送了len=0的空包，也是返回0，注意判断
int (posix_socket_send)(int socket_id, uint64_t tag, const uint8_t *buf, uint32_t len, int flags, luat_ip_addr_t *remote_ip, uint16_t remote_port, void *user_data) {
    
    struct timeval tv;
    tv.tv_sec = 0;
    tv.tv_usec = 1000; //暂时1ms吧
    setsockopt(socket_id, SOL_SOCKET, SO_SNDTIMEO, &tv, sizeof(tv));

    if (master_lock)
        if (luat_rtos_mutex_lock(master_lock, 100))
            return -1;
    int ret = send(socket_id, buf, len, flags);
    if (master_lock)
        luat_rtos_mutex_unlock(master_lock);
    return ret;
}

//检查socket合法性，成功返回0，失败 < 0
int (posix_socket_check)(int socket_id, uint64_t tag, void *user_data) {
    // TODO 通过select errorfds?
    LLOGD("CALL posix_socket_check %d %lld", socket_id, tag);
    return 0;
}

//保留有效的socket，将无效的socket关闭
void (posix_socket_clean)(int *vaild_socket_list, uint32_t num, void *user_data) {
    
}

int (posix_getsockopt)(int socket_id, uint64_t tag, int level, int optname, void *optval, uint32_t *optlen, void *user_data) {
    return getsockopt(socket_id, level, optname, optval, optlen);
}

int (posix_setsockopt)(int socket_id, uint64_t tag, int level, int optname, const void *optval, uint32_t optlen, void *user_data) {
    return setsockopt(socket_id, level, optname, optval, optlen);
}

//非posix的socket，用这个根据实际硬件设置参数
int (posix_user_cmd)(int socket_id, uint64_t tag, uint32_t cmd, uint32_t value, void *user_data) {
    return 0; // 没有这些东西
}


int (posix_dns)(const char *domain_name, uint32_t len, void *param,  void *user_data) {
    LLOGD("CALL posix_dns %.*s", len, domain_name);
    return -1; // 暂不支持DNS
}

int (posix_set_dns_server)(uint8_t server_index, luat_ip_addr_t *ip, void *user_data) {
    return 0; // 暂不支持设置DNS
}

#ifdef LUAT_USE_LWIP
int (posix_set_mac)(uint8_t *mac, void *user_data);
int (posix_set_static_ip)(luat_ip_addr_t *ip, luat_ip_addr_t *submask, luat_ip_addr_t *gateway, luat_ip_addr_t *ipv6, void *user_data);
#endif
int (posix_get_local_ip_info)(luat_ip_addr_t *ip, luat_ip_addr_t *submask, luat_ip_addr_t *gateway, void *user_data) {
    ip->ipv4 = 0;
    submask->ipv4 = 0;
    gateway->ipv4 = 0;
    return 0;
}

//所有网络消息都是通过cb_fun回调
//cb_fun回调时第一个参数为OS_EVENT，包含了socket的必要信息，第二个是luat_network_cb_param_t，其中的param是这里传入的param(就是适配器序号)
//OS_EVENT ID为EV_NW_XXX，param1是socket id param2是各自参数 param3是create_soceket传入的socket_param(就是network_ctrl *)
//dns结果是特别的，ID为EV_NW_SOCKET_DNS_RESULT，param1是获取到的IP数据量，0就是失败了，param2是ip组，动态分配的， param3是dns传入的param(就是network_ctrl *)
void (posix_socket_set_callback)(CBFuncEx_t cb_fun, void *param, void *user_data) {
    LLOGD("call posix_socket_set_callback %p %p", cb_fun, param);
    if (master_lock == NULL)
        luat_rtos_mutex_create(master_lock);
    posix_network_cb = cb_fun;
    posix_network_param = param;
}


network_adapter_info network_posix = {
    .check_ready = posix_check_ready,
    .create_soceket = posix_create_socket,
    .socket_connect  = posix_socket_connect,
    .socket_accept = posix_socket_accept,
    .socket_disconnect  = posix_socket_disconnect,
    .socket_close = posix_socket_close,
    .socket_force_close = posix_socket_force_close,
    .socket_receive = posix_socket_receive,
    .socket_send = posix_socket_send,
    .socket_clean = posix_socket_clean,
    .getsockopt = posix_getsockopt,
    .setsockopt = posix_setsockopt,
    .user_cmd  = posix_user_cmd,
    .dns = posix_dns,
    .set_dns_server = posix_set_dns_server,
    .get_local_ip_info = posix_get_local_ip_info,
    .socket_set_callback = posix_socket_set_callback,
    .name = "posix",
    .max_socket_num = 4,
    .no_accept = 1, // 暂时不支持接收
    .is_posix = 1,
};
