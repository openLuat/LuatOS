/*****************************************************************************
* | File      	:	Debug.h
* | Author      :   Waveshare team
* | Function    :	debug with printf
* | Info        :
*   Image scanning
*      Please use progressive scanning to generate images or fonts
*----------------
* |	This version:   V1.0
* | Date        :   2018-01-11
* | Info        :   Basic version
*
******************************************************************************/
#ifndef __DEBUG_H
#define __DEBUG_H

#ifndef LUAT_LOG
#define LUAT_LOG_TAG "luat.epaper"
#include "luat_log.h"
#endif

#define DEBUG 1
#if DEBUG
	#define Debug LLOGD
#else
	#define Debug(__info,...)  
#endif

#endif
