#ifndef __NW_API_H__
#define __NW_API_H__
/*
* 网络link相关API，如wifi连接/断开AP，蜂窝网络建立/去除PDP承载，以太网网线接入/断开，以及进入/退出飞行模式。
*/
#if (LUATOS_USE_NW_API == 1)
void luatos_nw_init(void);
#else

#endif
#endif