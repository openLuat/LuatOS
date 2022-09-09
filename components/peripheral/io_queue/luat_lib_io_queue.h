/******************************************************************************
 *  io_queue设备操作抽象层
 *****************************************************************************/
#ifndef __LUAT_IO_QUEUE_H__
#define __LUAT_IO_QUEUE_H__

#include "luat_base.h"
int l_io_queue_done_handler(lua_State *L, void* ptr);
int l_io_queue_capture_handler(lua_State *L, void* ptr);
#endif
