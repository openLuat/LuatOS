/*
 * File      : netclient.h
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
#ifndef __netCLIENT_H__
#define __netCLIENT_H__

#include <rtthread.h>

#define NETC_TYPE_TCP 0
#define NETC_TYPE_UDP 1

#define NETC_EVENT_CONNECT_OK 1
#define NETC_EVENT_CONNECT_FAIL 2
#define NETC_EVENT_RECV    4
#define NETC_EVENT_ERROR   7
#define NETC_EVENT_CLOSE   8


typedef struct rt_netc_ent {
    rt_uint32_t netc_id;
    rt_uint64_t lua_ref;
    rt_uint16_t event;
    rt_uint16_t len;
}rt_netc_ent_t;

typedef void (*rt_tpc_cb_t)(rt_netc_ent_t* ent);

typedef struct rt_netclient
{
    rt_uint32_t id;
    char hostname[32];
    rt_uint32_t port;
    rt_uint16_t type;
    rt_uint16_t closed;
    int sock_fd;
    int pipe_read_fd;
    int pipe_write_fd;
    char pipe_name[12];
    rt_tpc_cb_t rx;

    // Lua callback function
    int cb_recv;
    int cb_close;
    int cb_connect;
    int cb_any;
    int cb_error;
}rt_netclient_t;

rt_uint32_t rt_netc_next_no(void);
//rt_netclient_t *rt_netclient_create(void);
rt_int32_t *rt_netclient_start(rt_netclient_t * thiz);
void rt_netclient_close(rt_netclient_t *thiz);
//rt_int32_t rt_netclient_attach_rx_cb(rt_netclient_t *thiz, rt_tpc_cb_t cb);
rt_int32_t rt_netclient_send(rt_netclient_t *thiz, const void *buff, rt_size_t len);

#endif