/**
 * Copyright (c) 2015-2022 QXSI. All rights reserved.
 *
 * @file qxwz_user_impl.h
 * @brief header of APIs which user need implement
 * @version 1.0.0
 * @author Kong Yingjun
 * @date   2022-03-16
 *
 * CHANGELOG:
 * DATE             AUTHOR          REASON
 * 2022-03-16       Kong Yingjun    Init version;
 */
#ifndef QXWZ_USER_IMPL_H__
#define QXWZ_USER_IMPL_H__

#ifdef __cplusplus
extern "C" {
#endif

#include "qxwz_types.h"
/*
 *Log
 */
qxwz_int32_t qxwz_printf(const qxwz_char_t *fmt, ...);
/*
 * Mutex lock
 */

extern char test_of_extern[64];

typedef struct {
    qxwz_void_t *mutex_entity;
} qxwz_mutex_t;

qxwz_int32_t qxwz_mutex_init(qxwz_mutex_t *mutex);
qxwz_int32_t qxwz_mutex_trylock(qxwz_mutex_t *mutex);
qxwz_int32_t qxwz_mutex_lock(qxwz_mutex_t *mutex);
qxwz_int32_t qxwz_mutex_unlock(qxwz_mutex_t *mutex);
qxwz_int32_t qxwz_mutex_destroy(qxwz_mutex_t *mutex);
/*
 * Memory
 */
qxwz_void_t *qxwz_malloc(qxwz_uint32_t size);
qxwz_void_t *qxwz_calloc(qxwz_uint32_t nmemb, qxwz_uint32_t size);
qxwz_void_t *qxwz_realloc(qxwz_void_t *ptr, qxwz_uint32_t size);
qxwz_void_t qxwz_free(qxwz_void_t *ptr);

#define QXWZ_ERR_SOCK_DISCONNECTED      -1  /* socket is closed by peer */
#define QXWZ_ERR_SOCK_CONNECT           -2  /* something wrong happens when try to connect to the server */
#define QXWZ_ERR_SOCK_SEND              -3  /* something wrong happens when try to send data to server */
#define QXWZ_ERR_SOCK_RECV              -4  /* something wrong happens when try to receive data from server */
#define QXWZ_ERR_SOCK_UNKNOWN           -5  /* unknown error happens to socket */

typedef struct {
    const qxwz_char_t *hostname;
    qxwz_uint16_t port;
} qxwz_sock_host_t;


/*
 * Create a socket handler.
 *
 * @return:
 *    >= 0: succeeds, identifier of the socket handler;
 *      -1: failed;
 */
qxwz_int32_t qxwz_sock_create(void);

/*
 * Establish a connection to the server specified by the argument `serv` in a blocking way.
 * @param[in]  sock: socket handler;
 * @param[in]  serv: the server info, see `qxwz_sock_host_t`;
 *
 * @return:
 *      0: connecting succeeded;
 *     -1: connecting failed;
 */
qxwz_int32_t qxwz_sock_connect(qxwz_int32_t sock, qxwz_sock_host_t *serv);

/*
 * Send data in a non-blocking way.
 * @param[in]  sock: socket handler;
 * @param[in]  send_buf: pointer of the buffer to be sent;
 * @param[in]  len: length of the buffer;
 *
 * @return:
 *    >=0: the number of bytes sent;
 *     -1: fails;
 */
qxwz_int32_t qxwz_sock_send(qxwz_int32_t sock, const qxwz_uint8_t *send_buf, qxwz_uint32_t len);

/*
 * Receive data in a non-blocking way.
 * @param[in]  sock: socket handler;
 * @param[in]  recv_buf: pointer of the buffer to recv the data;
 * @param[in]  len: length of the buffer;
 *
 * @return:
 *     >0: the number of bytes received;
 *      0: connection is closed by peer
 *     -1: no data received this time
 *     -2: error occur;
 */
qxwz_int32_t qxwz_sock_recv(qxwz_int32_t sock, qxwz_uint8_t *recv_buf, qxwz_uint32_t len);


/*
 * Close a socket handler.
 * @param[in]  sock: socket handler.
 *
 * @return:
 *      0: succeeds;
 *     -1: fails;
 */
qxwz_int32_t qxwz_sock_close(qxwz_int32_t sock);

#ifdef __cplusplus
}
#endif

#endif
