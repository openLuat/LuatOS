/*
 * Copyright (C) 2020-2021 Alibaba Group Holding Limited
 */
#ifndef __BOT_PLATFORM_H
#define __BOT_PLATFORM_H

#include <stdio.h>
#include <stdbool.h>
#include <string.h>
#include <stdlib.h>
#include <stdarg.h>
#include <sys/time.h>
#include <time.h>

#include "lfs.h"
#include "errno.h"
#include "sockets.h"
#include "netdb.h"
#include "FreeRTOS.h"
#include "queue.h"
#include "semphr.h"
#include "luat_fs.h"
#include "netdb.h"

#define BOT_FS_USER_DIR "\bot"              ///< bot storage folder
#define BOT_UT_MAL_CELL_PDP_OFF 

#define BOT_O_RDONLY        LFS_O_RDONLY        ///< open file as read-only
#define BOT_O_WRONLY        LFS_O_WRONLY        ///< open the file for writing only
#define BOT_O_RDWR          LFS_O_RDWR          ///< Open the file for reading and writing. The above three flags are mutually exclusive, that is, they cannot be used at the same time, but they can be combined with the following flags using the OR (|) operator.
#define BOT_O_APPEND        LFS_O_APPEND        ///< When reading and writing a file, it will move from the end of the file, that is, the written data will be added to the back of the file in an additional way.
#define BOT_O_CREAT         LFS_O_CREAT         ///< If the file to be opened does not exist, it will be created automatically.
#define BOT_O_TRUNC         LFS_O_TRUNC         ///< If the file exists and is opened in a writable mode, this flag will clear the file length to 0, and the data originally stored in the file will also disappear.

/* micro defination about file system, used for bot_fseek()'s/bot_seek()'s whence */
#define BOT_SEEK_SET        LFS_SEEK_SET        ///< beginning of file
#define BOT_SEEK_CUR        LFS_SEEK_CUR        ///< current position
#define BOT_SEEK_END        LFS_SEEK_END        ///< end of file

#define LUAT_RTOS_PRIORITY_HIGH              95
#define LUAT_RTOS_PRIORITY_ABOVE_NORMAL      75
#define LUAT_RTOS_PRIORITY_NORMAL            55
#define LUAT_RTOS_PRIORITY_BELOW_NORMAL      35
#define LUAT_RTOS_PRIORITY_LOW               15


/* bot error code defination */
#define BOT_E_EINTR         EINTR           ///< 4, Interrupted system call
#define BOT_E_EAGAIN        EAGAIN          ///< 11, Try again
#define BOT_E_EPIPE         EPIPE           ///< 32, Broken pipe
#define BOT_E_EWOULDBLOCK   EWOULDBLOCK     ///< like, EAGAIN, Operation would block
#define BOT_E_ECONNRESET    ECONNRESET      ///< 104, FConnection reset by peer

// /* socket macros */
#define BOT_AF_UNSPEC       AF_UNSPEC         ///< AF_UNSPEC
#define BOT_SOCK_STREAM     SOCK_STREAM       ///< Stream sockets
#define BOT_SOCK_DGRAM      SOCK_DGRAM        ///< Datagram sockets
#define BOT_IPPROTO_TCP     IPPROTO_TCP       ///< TCP protocol
#define BOT_IPPROTO_UDP     IPPROTO_UDP       ///< UDP protocol


#endif /* __BOT_PLATFORM_H */
