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

#ifndef __LIBRS232_H__
#define __LIBRS232_H__

#include <time.h>

#define RS232_STRLEN 512
#define RS232_STRLEN_DEVICE 256

#ifdef __linux__
#define RS232_PORT_POSIX "/dev/ttyS0"
#else
#define RS232_PORT_POSIX "/dev/cua00"
#endif /* __linux__ */

#define RS232_PORT_WIN32 "COM1"

// #if defined(WIN32) || defined(UNDER_CE) || defined(_MSC_VER)
 #include "librs232/rs232_windows.h"
//  #ifdef _MSC_VER
//   #pragma warning(disable:4996)
//   #define snprintf _snprintf
//  #endif
// #else
//  #include "librs232/rs232_posix.h"
// #endif

/*Ensure destination string is zero terminated*/
#define strncpyz(dest, src, size) strncpy(dest, src, size); dest[size-1]='\0'

#ifdef RS232_DEBUG
const char* rs232_hex_dump(const void *data, unsigned int len);
const char* rs232_ascii_dump(const void *data, unsigned int len);

 #if defined(WIN32) || defined(UNDER_CE)
  #include <windows.h>
  #define DBG(x, ...) \
 		{ \
			SYSTEMTIME t; \
			GetLocalTime(&t); \
			fprintf(stderr, "[%02d:%02d:%02d.%03d] %s(%d):%s: " x, t.wHour, t.wMinute, \
				t.wSecond, t.wMilliseconds,  __FILE__, __LINE__, __FUNCTION__, ## __VA_ARGS__); \
		}
 #else
  #define DBG(x, ...) \
		{ \
			time_t now = time(NULL); \
			struct tm* t = localtime(&now); \
			fprintf(stderr, "[%02d:%02d:%02d] %s(%d):%s: " x, t->tm_hour, t->tm_min, \
				t->tm_sec,  __FILE__, __LINE__, __FUNCTION__, ## __VA_ARGS__); \
		}
 #endif /* #if defined(WIN32) || defined(UNDER_CE) */
#else
 #define DBG(x, ...)
 #define rs232_hex_dump(x, y)
 #define rs232_ascii_dump(x, y)
#endif /* RS232_DEBUG */

enum rs232_baud_e {
	RS232_BAUD_300,
	RS232_BAUD_2400,
	RS232_BAUD_4800,
	RS232_BAUD_9600,
	RS232_BAUD_19200,
	RS232_BAUD_38400,
	RS232_BAUD_57600,
	RS232_BAUD_115200,
	RS232_BAUD_460800,
	RS232_BAUD_MAX
};

enum rs232_data_e {
	RS232_DATA_5,
	RS232_DATA_6,
	RS232_DATA_7,
	RS232_DATA_8,
	RS232_DATA_MAX
};

enum rs232_parity_e {
	RS232_PARITY_NONE,
	RS232_PARITY_ODD,
	RS232_PARITY_EVEN,
	RS232_PARITY_MAX
};

enum rs232_stop_e {
	RS232_STOP_1,
	RS232_STOP_2,
	RS232_STOP_MAX
};

enum rs232_flow_e {
	RS232_FLOW_OFF,
	RS232_FLOW_HW,
	RS232_FLOW_XON_XOFF,
	RS232_FLOW_MAX
};

enum rs232_status_e {
	RS232_PORT_CLOSED,
	RS232_PORT_OPEN,
};

enum rs232_dtr_e {
	RS232_DTR_OFF,
	RS232_DTR_ON,
	RS232_DTR_MAX
};

enum rs232_rts_e {
	RS232_RTS_OFF,
	RS232_RTS_ON,
	RS232_RTS_MAX
};

struct rs232_port_t {
	char dev[RS232_STRLEN_DEVICE+1];
	void *pt; /* platform specific stuff */
	enum rs232_baud_e baud;
	enum rs232_data_e data;
	enum rs232_stop_e stop;
	enum rs232_flow_e flow;
	enum rs232_parity_e parity;
	enum rs232_status_e status;
	enum rs232_dtr_e dtr;
	enum rs232_rts_e rts;
};

enum rs232_error_e {
	RS232_ERR_NOERROR,
	RS232_ERR_UNKNOWN,
	RS232_ERR_OPEN,
	RS232_ERR_CLOSE,
	RS232_ERR_FLUSH,
	RS232_ERR_CONFIG,
	RS232_ERR_READ,
	RS232_ERR_WRITE,
	RS232_ERR_SELECT,
	RS232_ERR_TIMEOUT,
	RS232_ERR_IOCTL,
	RS232_ERR_PORT_CLOSED,
	RS232_ERR_BREAK,
	RS232_ERR_FRAME,
	RS232_ERR_PARITY,
	RS232_ERR_RXOVERFLOW,
	RS232_ERR_OVERRUN,
	RS232_ERR_MAX
};

// #if (defined(WIN32) || defined(UNDER_CE)) && !defined(RS232_STATIC)
// 	#ifdef RS232_EXPORT
// 		#define RS232_LIB __declspec(dllexport)
// 	#else
// 		#define RS232_LIB __declspec(dllimport)
// 	#endif
// #else
	#define RS232_LIB
// #endif

RS232_LIB struct rs232_port_t * rs232_init(void);
RS232_LIB void rs232_end(struct rs232_port_t *p);
RS232_LIB unsigned int rs232_open(struct rs232_port_t *p);
RS232_LIB unsigned int rs232_port_open(struct rs232_port_t *p);
RS232_LIB unsigned int rs232_close(struct rs232_port_t *p);
RS232_LIB unsigned int rs232_flush(struct rs232_port_t *p);
RS232_LIB void rs232_set_device(struct rs232_port_t *p, const char *device);
RS232_LIB unsigned int rs232_set_baud(struct rs232_port_t *p, unsigned int baud);
RS232_LIB unsigned int rs232_set_stop(struct rs232_port_t *p, unsigned int stop);
RS232_LIB unsigned int rs232_set_data(struct rs232_port_t *p, unsigned int data);
RS232_LIB unsigned int rs232_set_parity(struct rs232_port_t *p, unsigned int parity);
RS232_LIB unsigned int rs232_set_flow(struct rs232_port_t *p, unsigned int flow);
RS232_LIB unsigned int rs232_set_dtr(struct rs232_port_t *p, unsigned int dtr);
RS232_LIB unsigned int rs232_set_rts(struct rs232_port_t *p, unsigned int rts);
RS232_LIB const char * rs232_get_device(struct rs232_port_t *p);
RS232_LIB unsigned int rs232_get_baud(struct rs232_port_t *p);
RS232_LIB unsigned int rs232_get_stop(struct rs232_port_t *p);
RS232_LIB unsigned int rs232_get_data(struct rs232_port_t *p);
RS232_LIB unsigned int rs232_get_parity(struct rs232_port_t *p);
RS232_LIB unsigned int rs232_get_flow(struct rs232_port_t *p);
RS232_LIB unsigned int rs232_get_dtr(struct rs232_port_t *p);
RS232_LIB unsigned int rs232_get_rts(struct rs232_port_t *p);
RS232_LIB unsigned int rs232_read(struct rs232_port_t *p, unsigned char *buf, unsigned int buf_len, unsigned int *read_len);
RS232_LIB unsigned int rs232_read_timeout(struct rs232_port_t *p, unsigned char *buf, unsigned int buf_len, unsigned int *read_len, unsigned int timeout);
RS232_LIB unsigned int rs232_read_timeout_forced(struct rs232_port_t *p, unsigned char *buf, unsigned int buf_len, unsigned int *read_len, unsigned int timeout);
RS232_LIB unsigned int rs232_write(struct rs232_port_t *p, const unsigned char *buf, unsigned int buf_len, unsigned int *write_len);
RS232_LIB unsigned int rs232_write_timeout(struct rs232_port_t *p, const unsigned char *buf, unsigned int buf_len, unsigned int *write_len, unsigned int timeout);
RS232_LIB unsigned int rs232_in_queue(struct rs232_port_t *p, unsigned int *in_bytes);
RS232_LIB void rs232_in_queue_clear(struct rs232_port_t *p);
RS232_LIB const char * rs232_to_string(struct rs232_port_t *p);
RS232_LIB const char * rs232_strerror(unsigned int error);
RS232_LIB const char * rs232_strbaud(unsigned int baud);
RS232_LIB const char * rs232_strdata(unsigned int data);
RS232_LIB const char * rs232_strparity(unsigned int parity);
RS232_LIB const char * rs232_strstop(unsigned int stop);
RS232_LIB const char * rs232_strflow(unsigned int flow);
RS232_LIB const char * rs232_strdtr(unsigned int dtr);
RS232_LIB const char * rs232_strrts(unsigned int rts);
RS232_LIB unsigned int rs232_fd(struct rs232_port_t *p);

#endif /* __LIBRS232_H__ */
