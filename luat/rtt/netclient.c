/*
 * File      : netclient.c
 * This file is part of RT-Thread
 * COPYRIGHT (C) 2006 - 2018, RT-Thread Development Team
 *
 *  This program is free software; you can redistribute it and/or modify
 *  it under the terms of the GNU General Public License as published by
 *  the Free Software Foundation; either version 2 of the License, or
 *  (at your option) any later version.
 *
 *  This program is distributed in the hope that it will be useful,
 *  but WITHOUT ANY WARRANTY; without even the implied warranty of
 *  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 *  GNU General Public License for more details.
 *
 *  You should have received a copy of the GNU General Public License along
 *  with this program; if not, write to the Free Software Foundation, Inc.,
 *  51 Franklin Street, Fifth Floor, Boston, MA 02110-1301 USA.
 *
 * Change Logs:
 * Date           Author       Notes
 * 2018-08-10     never        the first version
 */
#include <rtthread.h>
#include <rtdevice.h>
#include <sys/socket.h>
#include <sys/select.h>
#include <sys/types.h>
#include <unistd.h>
#include <netdb.h>
#include <stdio.h>
#include <string.h>
#include <stdlib.h>
//#include "elog.h"
#include "netclient.h"

#define DBG_TAG           "luat.netc"
#define DBG_LVL           DBG_INFO
#include <rtdbg.h>



#define BUFF_SIZE (1024)
#define MAX_VAL(A, B) ((A) > (B) ? (A) : (B))
#define STRCMP(a, R, b) (strcmp((a), (b)) R 0)
// #define RX_CB_HANDLE(_buff, _len)  \
//     do                             \
//     {                              \
//         if (thiz->rx)              \
//             thiz->rx(_buff, _len); \
//     } while (0)
// 
// #define EXCEPTION_HANDLE(_bytes, _tag, _info_a, _info_b)                  \
//     do                                                                    \
//     {                                                                     \
//         if (_bytes < 0)                                                   \
//         {                                                                 \
//             LOG_E("return: %d", _bytes);                \
//             goto exit;                                                    \
//         }                                                                 \
//         if (_bytes == 0)                                                  \
//         {                                                                 \
//             if (STRCMP(_info_b, ==, "warning"))                           \
//                 LOG_W("return: %d", _bytes);            \
//             else                                                          \
//             {                                                             \
//                 LOG_E("return: %d", _bytes);            \
//                                                                           \
//                 goto exit;                                                \
//             }                                                             \
//         }                                                                 \
//     } while (0)

// #define EXIT_HANDLE(_buff)                                            \
//     do                                                                \
//     {                                                                 \
//         if (STRCMP(_buff, ==, "exit"))                                \
//         {                                                             \
//             LOG_I("exit handle : receive [exit], exit thread");     \
//             goto exit;                                                \
//         }                                                             \
//     } while (0)

static rt_netclient_t *netclient_create(void);
static rt_int32_t netclient_destory(rt_netclient_t *thiz);
static rt_int32_t socket_init(rt_netclient_t *thiz, const char *hostname, rt_uint32_t port);
static rt_int32_t socket_deinit(rt_netclient_t *thiz);
static rt_int32_t pipe_init(rt_netclient_t *thiz);
static rt_int32_t pipe_deinit(rt_netclient_t *thiz);
static void select_handle(rt_netclient_t *thiz, char *pipe_buff, char *sock_buff);
static rt_int32_t netclient_thread_init(rt_netclient_t *thiz);
static void netclient_thread_entry(void *param);

rt_netclient_t *rt_netclient_create(void)
{
    rt_netclient_t *thiz = RT_NULL;

    thiz = rt_malloc(sizeof(rt_netclient_t));
    if (thiz == RT_NULL)
    {
        LOG_E("netclient alloc : malloc error");
        return RT_NULL;
    }

    thiz->sock_fd = -1;
    thiz->pipe_read_fd = -1;
    thiz->pipe_write_fd = -1;
    memset(thiz->pipe_name, 0, sizeof(thiz->pipe_name));
    thiz->rx = RT_NULL;
    
    return thiz;
}

static rt_int32_t netclient_destory(rt_netclient_t *thiz)
{
    int res = 0;

    if (thiz == RT_NULL)
    {
        LOG_E("netclient del : param is NULL, delete failed");
        return -1;
    }

    if (thiz->sock_fd != -1)
        socket_deinit(thiz);

    pipe_deinit(thiz);

    return 0;
}

static rt_int32_t socket_init(rt_netclient_t *thiz, const char *url, rt_uint32_t port)
{
    struct sockaddr_in dst_addr;
    struct hostent *hostname;
    rt_int32_t res = 0;
    //const char *str = "socket create succeed";

    if (thiz == RT_NULL)
        return -1;

    thiz->sock_fd = socket(AF_INET, SOCK_STREAM, 0);
    if (thiz->sock_fd == -1)
    {
        LOG_E("socket init : socket create failed");
        return -1;
    }

    hostname = gethostbyname(url);

    // TODO: print ip for hostname
    //LOG_I("socket host=%s port=%d", hostname, port);

    dst_addr.sin_family = AF_INET;
    dst_addr.sin_port = htons(port);
    dst_addr.sin_addr = *((struct in_addr *)hostname->h_addr);
    memset(&(dst_addr.sin_zero), 0, sizeof(dst_addr.sin_zero));

    res = connect(thiz->sock_fd, (struct sockaddr *)&dst_addr, sizeof(struct sockaddr));
    if (res == -1)
    {
        LOG_E("socket init : connect failed");
        return -1;
    }

    LOG_I("socket init : connected succeed");

    //send(thiz->sock_fd, str, strlen(str), 0);

    return 0;
}

static rt_int32_t socket_deinit(rt_netclient_t *thiz)
{
    int res = 0;

    if (thiz == RT_NULL)
    {
        LOG_E("socket deinit : param is NULL, socket deinit failed");
        return -1;
    }
    if (thiz->sock_fd < 0)
        return 0;

    res = closesocket(thiz->sock_fd);
    //RT_ASSERT(res == 0);

    thiz->sock_fd = -1;

    LOG_I("socket deinit : socket close succeed");

    return 0;
}

static rt_int32_t pipe_init(rt_netclient_t *thiz)
{
    char dev_name[32];
    static int pipeno = 0;
    rt_pipe_t *pipe = RT_NULL;

    if (thiz == RT_NULL)
    {
        LOG_E("pipe init : param is NULL");
        return -1;
    }

    snprintf(thiz->pipe_name, sizeof(thiz->pipe_name), "pipe%d", pipeno++);

    pipe = rt_pipe_create(thiz->pipe_name, PIPE_BUFSZ);
    if (pipe == RT_NULL)
    {
        LOG_E("pipe create : pipe create failed");
        return -1;
    }

    snprintf(dev_name, sizeof(dev_name), "/dev/%s", thiz->pipe_name);
    thiz->pipe_read_fd = open(dev_name, O_RDONLY, 0);
    if (thiz->pipe_read_fd < 0)
        goto fail_read;

    thiz->pipe_write_fd = open(dev_name, O_WRONLY, 0);
    if (thiz->pipe_write_fd < 0)
        goto fail_write;

    LOG_I("pipe init : pipe init succeed");
    return 0;

fail_write:
    close(thiz->pipe_read_fd);
fail_read:
    return -1;
}

static rt_int32_t pipe_deinit(rt_netclient_t *thiz)
{
    int res = 0;

    if (thiz == RT_NULL)
    {
        LOG_E("pipe deinit : param is NULL, pipe deinit failed");
        return -1;
    }

    if (thiz->pipe_read_fd != -1) {
        res = close(thiz->pipe_read_fd);
        thiz->pipe_read_fd = -1;
    }

    if (thiz->pipe_write_fd != -1) {
        res = close(thiz->pipe_write_fd);
        thiz->pipe_write_fd = -1;
    }
    if (thiz->pipe_name[0] != 0) {
        rt_pipe_delete(thiz->pipe_name);
    }

    LOG_I("pipe deinit : pipe close succeed");
    return 0;
}

static rt_int32_t netclient_thread_init(rt_netclient_t *thiz)
{
    rt_thread_t netclient_tid = RT_NULL;

    netclient_tid = rt_thread_create("netc", netclient_thread_entry, thiz, 2048, 12, 10);
    if (netclient_tid == RT_NULL)
    {
        LOG_E("netclient thread : thread create failed");
        return -1;
    }

    rt_thread_startup(netclient_tid);

    LOG_D("netclient thread : thread init succeed");
    return 0;
}

static void select_handle(rt_netclient_t *thiz, char *pipe_buff, char *sock_buff)
{
    fd_set fds;
    rt_int32_t max_fd = 0, res = 0;

    max_fd = MAX_VAL(thiz->sock_fd, thiz->pipe_read_fd) + 1;
    FD_ZERO(&fds);

    while (1)
    {
        FD_SET(thiz->sock_fd, &fds);
        FD_SET(thiz->pipe_read_fd, &fds);

        res = select(max_fd, &fds, RT_NULL, RT_NULL, RT_NULL);

        /* exception handling: exit */
        if (res <= 0) {
            LOG_I("select result=%d, goto cleanup", res);
            goto exit;
        }

        /* socket is ready */
        if (FD_ISSET(thiz->sock_fd, &fds))
        {
            res = recv(thiz->sock_fd, sock_buff, BUFF_SIZE, 0);

            if (res > 0) {
                LOG_I("data recv len=%d", res);
                if (thiz->rx) {
                    rt_netc_ent_t ent;
                    ent.thiz = thiz;
                    ent.event = NETC_EVENT_REVC;
                    ent.len = res;
                    ent.buff = sock_buff;
                    thiz->rx(ent);
                }
            }
            else {
                LOG_I("recv return error=%d", res);
                if (thiz->rx) {
                    rt_netc_ent_t ent;
                    ent.thiz = thiz;
                    ent.event = NETC_EVENT_ERROR;
                    thiz->rx(ent);
                }
                goto exit;
            }
        }

        /* pipe is read */
        if (FD_ISSET(thiz->pipe_read_fd, &fds))
        {
            /* read pipe */
            res = read(thiz->pipe_read_fd, pipe_buff, BUFF_SIZE);

            if (res <= 0) {
                thiz->closed;
                goto exit;
            }
            else if (thiz->closed) {
                goto exit;
            }
            else if (res > 0) {
                send(thiz->sock_fd, pipe_buff, res, 0);
            }
        }
    }
exit:
    LOG_I("select loop exit, cleanup");
    free(pipe_buff);
    free(sock_buff);
    if (thiz != NULL) {
        thiz->closed = 1;
        rt_netclient_close(thiz);
        if (thiz->rx) {
            rt_netc_ent_t ent;
            ent.thiz = thiz;
            ent.event = NETC_EVENT_CLOSE;
            thiz->rx(ent);
        }
    }
}

static void netclient_thread_entry(void *param)
{
    rt_netclient_t *thiz = param;
    char *pipe_buff = RT_NULL, *sock_buff = RT_NULL;

    if (socket_init(thiz, thiz->hostname, thiz->port) != 0) {
        LOG_E("sockect_init fail!!!");
        if (thiz->rx) {
            rt_netc_ent_t ent;
            ent.event = NETC_EVENT_CONNECT_FAIL;
            thiz->rx(ent);
        }
        return;
    }

    pipe_buff = malloc(BUFF_SIZE);
    if (pipe_buff == RT_NULL)
    {
        LOG_E("fail to malloc pipe_buff!!!");
        return;
    }

    sock_buff = malloc(BUFF_SIZE);
    if (sock_buff == RT_NULL)
    {
        free(pipe_buff);
        LOG_E("fail to malloc sock_buff!!!");
        return;
    }

    memset(sock_buff, 0, BUFF_SIZE);
    memset(pipe_buff, 0, BUFF_SIZE);

    select_handle(thiz, pipe_buff, sock_buff);
}

rt_int32_t *rt_netclient_start(rt_netclient_t * thiz) {

    if (pipe_init(thiz) != 0)
        goto quit;

    if (netclient_thread_init(thiz) != 0)
        goto quit;

    LOG_I("netc start succeed");
    return 0;

quit:
    netclient_destory(thiz);
    return 1;
}

void rt_netclient_close(rt_netclient_t *thiz)
{
    LOG_I("netc deinit : begin");
    netclient_destory(thiz);
    LOG_W("netc deinit : end");
}

rt_int32_t rt_netclient_send(rt_netclient_t *thiz, const void *buff, rt_size_t len)
{
    rt_size_t bytes = 0;

    if (thiz == RT_NULL)
    {
        LOG_W("netclient send : param is NULL");
        return -1;
    }

    if (buff == RT_NULL)
    {
        LOG_W("netclient send : buff is NULL");
        return -1;
    }

    LOG_D("send data len=%d buff=[%s]", len, buff);

    bytes = write(thiz->pipe_write_fd, buff, len);
    return bytes;
}

// rt_int32_t rt_netclient_attach_rx_cb(rt_netclient_t *thiz, rx_cb_t cb)
// {
//     if (thiz == RT_NULL)
//     {
//         elog_e("callback attach", "param is NULL\n");
//         return -1;
//     }

//     thiz->rx = cb;
//     elog_i("callback attach", "attach succeed\n");
//     return 0;
// }

// int easy_log_init(void)
// {
//     /* initialize EasyFlash and EasyLogger */
//     elog_init();
//     /* set enabled format */
//     elog_set_fmt(ELOG_LVL_ASSERT, ELOG_FMT_ALL & ~ELOG_FMT_P_INFO);
//     elog_set_fmt(ELOG_LVL_ERROR, ELOG_FMT_LVL | ELOG_FMT_TAG);
//     elog_set_fmt(ELOG_LVL_WARN, ELOG_FMT_LVL | ELOG_FMT_TAG);
//     elog_set_fmt(ELOG_LVL_INFO, ELOG_FMT_LVL | ELOG_FMT_TAG );
//     elog_set_fmt(ELOG_LVL_DEBUG, ELOG_FMT_LVL | ELOG_FMT_TAG);
//     elog_set_fmt(ELOG_LVL_VERBOSE, ELOG_FMT_LVL | ELOG_FMT_TAG);
//     /* start EasyLogger */
//     elog_start();
// }
// INIT_APP_EXPORT(easy_log_init);
