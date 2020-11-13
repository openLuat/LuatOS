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

#include "luat_base.h"

#define NETC_TYPE_TCP 0
#define NETC_TYPE_UDP 1

#define NETC_EVENT_CONNECT_OK 1
#define NETC_EVENT_CONNECT_FAIL 2
#define NETC_EVENT_RECV    4
#define NETC_EVENT_ERROR   7
//#define NETC_EVENT_CLOSE   8
#define NETC_EVENT_END     9


typedef struct netc_ent {
    int netc_id;
    int lua_ref;
    int event;
    size_t len;
    void* buff;
}netc_ent_t;

typedef int (*tpc_cb_t)(netc_ent_t* ent);

typedef struct netclient
{
    int id;
    char idStr[10];
    char hostname[64];
    uint32_t ipv4;
    int port;
    int type;
    int closed;
    int sock_fd;
    int pipe_read_fd;
    int pipe_write_fd;
    char pipe_name[12];
    tpc_cb_t rx;

    // Lua callback function
    int cb_recv;
    //int cb_close;
    int cb_connect;
    int cb_any;
    int cb_error;
    int self_ref;
}netclient_t;

uint32_t netc_next_no(void);
//netclient_t *netclient_create(void);
int32_t netclient_start(netclient_t * thiz);
int32_t netclient_rebind(netclient_t * thiz);
void netclient_close(netclient_t *thiz);
//int32_t netclient_attach_rx_cb(netclient_t *thiz, tpc_cb_t cb);
int32_t netclient_send(netclient_t *thiz, const void *buff, size_t len, int flags);

#endif
