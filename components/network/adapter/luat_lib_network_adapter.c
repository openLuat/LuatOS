/*
@module  network_adapter
@summary 网络接口适配
@version 1.0
@date    2022.04.11
*/
#include "luat_base.h"
#include "luat_rtos.h"
#include "luat_zbuff.h"
#define LUAT_LOG_TAG "net_adapter"
#include "luat_log.h"

#include "rotable2.h"
static const rotable_Reg_t reg_network_adapter[] =
{
    { "ETH0",           ROREG_INT(0)},
	{ "ETH1",           ROREG_INT(1)},
	{ "AP",     		ROREG_INT(2)},
	{ "STA",          	ROREG_INT(3)},
	{ NULL,            {}}
};
