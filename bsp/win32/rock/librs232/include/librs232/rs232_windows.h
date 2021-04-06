/*
 * Copyright (c) 2011 Petr Stetiar <ynezz@true.cz>, Gaben Ltd.
 *
 * Permission is hereby granted, free of charge, to any person
 * obtaining a copy of this software and associated documentation
 * files (the "Software"), to deal in the Software without
 * restriction, including without limitation the rights to use,
 * copy, modify, merge, publish, distribute, sublicense, and/or sell
 * copies of the Software, and to permit persons to whom the
 * Software is furnished to do so, subject to the following
 * conditions:
 * 
 * The above copyright notice and this permission notice shall be
 * included in all copies or substantial portions of the Software.
 * 
 * THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
 * EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES
 * OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND
 * NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT
 * HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY,
 * WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING
 * FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR
 * OTHER DEALINGS IN THE SOFTWARE.
 *
 */

#ifndef __LIBRS232_WINDOWS_H__
#define __LIBRS232_WINDOWS_H__

#include <windows.h>

#ifndef CBR_460800
#define CBR_460800 460800
#endif

struct rs232_windows_t {
	HANDLE fd;
	COMMTIMEOUTS old_tm;
	DCB old_dcb;
	unsigned int r_timeout;
	unsigned int w_timeout;
	unsigned int r_buffer;
	unsigned int w_buffer;
	OVERLAPPED oWait;
	unsigned char wait_progress;
	DWORD wait_mask;
};

#define GET_PORT_TIMEOUTS(fd, t) \
	memset(t, 0, sizeof(COMMTIMEOUTS)); \
	if (!GetCommTimeouts(fd, t)) { \
		DBG("GetCommTimeouts() %s\n", last_error()); \
		return RS232_ERR_UNKNOWN; \
	}

#define SET_PORT_TIMEOUTS(fd, t) \
	if (!SetCommTimeouts(fd, t)) { \
		DBG("SetCommTimeouts() %s\n", last_error()); \
		return RS232_ERR_UNKNOWN; \
	}

#define GET_PORT_STATE(fd, pdcb) \
	memset(pdcb, 0, sizeof(DCB)); \
	if (!GetCommState(fd, pdcb)) { \
		DBG("GetCommState() %s\n", last_error()); \
		return RS232_ERR_UNKNOWN; \
	}

#define SET_PORT_STATE(fd, pdcb) \
	if (!SetCommState(fd, pdcb)) { \
		DBG("SetCommState() %s\n", last_error()); \
		return RS232_ERR_UNKNOWN; \
	}

#endif /* __LIBRS232_WINDOWS_H__ */
