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

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <ctype.h>
#include <assert.h>

#ifndef UNDER_CE
#include <errno.h>
#endif

#include "librs232/rs232.h"

typedef DWORD monotonic_time_t;
typedef DWORD monotonic_diff_t;

static monotonic_time_t GetMonotonicTime(){
	return GetTickCount();
}

static monotonic_diff_t GetMonotonicDelta(monotonic_time_t StartTime, monotonic_time_t EndTime){
	if(StartTime > EndTime)
		return (MAXDWORD - StartTime) + EndTime;
	return EndTime - StartTime;
}

#define READ_EVENTS     (EV_RXCHAR | EV_ERR | EV_BREAK)
#define READ_LATENTENCY 500
#define R_BUFFER_SIZE   1024
#define W_BUFFER_SIZE   1024

#define USE_OVERLAPPED

static wchar_t *
a2w(const char *astr)
{
	size_t len = 0;
	wchar_t *ret = NULL;

	if (astr == NULL)
		return NULL;

	len = strlen(astr);
	if (len > 0) {
		ret = (wchar_t*)malloc((len*2)+1 * sizeof(wchar_t*));
		memset(ret, 0, (len*2));
		MultiByteToWideChar(CP_ACP, 0, astr, -1, ret, (int)len);
		ret[len] = '\0';
	} else
		ret = NULL;

	return ret;
}

#ifdef RS232_DEBUG
static char * last_error(void)
{
	DWORD err = 0;
	DWORD ret = 0;
	char errbuf[MAX_PATH+1] = {0};
	static char retbuf[MAX_PATH+1] = {0};

	err = GetLastError();
	ret = FormatMessageA(FORMAT_MESSAGE_FROM_SYSTEM, NULL, err, 0, errbuf, MAX_PATH, NULL);
	if (ret != 0) {
		/* CRLF fun */
		errbuf[ret-2] = 0;
		snprintf(retbuf, MAX_PATH, "LastError: %s (%ld)", errbuf, ret);
	}
	else
		snprintf(retbuf, MAX_PATH, "LastError: %ld (FormatMessageA failed)", ret);

	return retbuf;
}
#endif

RS232_LIB struct rs232_port_t *
rs232_init(void)
{
	struct rs232_port_t *p = NULL;
	struct rs232_windows_t *wx = NULL;
	p = (struct rs232_port_t *) malloc(sizeof(struct rs232_port_t));
	if (p == NULL)
		return NULL;

	p->pt = (struct rs232_windows_t *) malloc(sizeof(struct rs232_windows_t));
	if (p->pt == NULL) {
		free(p);
		return NULL;
	}

	DBG("p=%p p->pt=%p\n", (void *)p, p->pt);

	memset(p->dev, 0, RS232_STRLEN_DEVICE+1);
	strncpyz(p->dev, RS232_PORT_WIN32, RS232_STRLEN_DEVICE);

	p->baud = RS232_BAUD_115200;
	p->data = RS232_DATA_8;
	p->parity = RS232_PARITY_NONE;
	p->stop = RS232_STOP_1;
	p->flow = RS232_FLOW_OFF;
	p->status = RS232_PORT_CLOSED;
	p->dtr = RS232_DTR_OFF;
	p->rts = RS232_RTS_OFF;

	wx = (struct rs232_windows_t *) p->pt;
	wx->r_timeout = READ_LATENTENCY;
	wx->w_timeout = READ_LATENTENCY;
	wx->r_buffer = R_BUFFER_SIZE;
	wx->w_buffer = W_BUFFER_SIZE;

	return p;
}

static unsigned int
port_buffers(struct rs232_port_t *p, unsigned int rb, unsigned int wb)
{
	struct rs232_windows_t *wx = p->pt;

	DBG("p=%p p->pt=%p rb=%d wb=%d\n", (void *)p, p->pt, rb, wb);

	if (!SetupComm(wx->fd, rb, wb)) {
		DBG("SetupComm() %s\n", last_error());
		return RS232_ERR_UNKNOWN;
	}

	wx->r_buffer = rb;
	wx->w_buffer = wb;

	return RS232_ERR_NOERROR;
}

static unsigned int
port_timeout(struct rs232_port_t *p, unsigned int rt, unsigned int wt)
{
	struct rs232_windows_t *wx = p->pt;
	COMMTIMEOUTS t;

	GET_PORT_TIMEOUTS(wx->fd, &t);

	t.ReadIntervalTimeout = 0;
	t.ReadTotalTimeoutMultiplier = 0;
	t.ReadTotalTimeoutConstant = rt;
	t.WriteTotalTimeoutMultiplier = 0;
	t.WriteTotalTimeoutConstant = wt;

	SET_PORT_TIMEOUTS(wx->fd, &t);

	wx->w_timeout = wt;
	wx->r_timeout = rt;

	return RS232_ERR_NOERROR;
}

RS232_LIB void
rs232_end(struct rs232_port_t *p)
{
	struct rs232_windows_t *wx = p->pt;

	DBG("p=%p p->pt=%p\n", (void *)p, p->pt);

	if (!rs232_port_open(p)) {
		free(p->pt);
		free(p);
		return;
	}

	rs232_flush(p);

	if (!SetCommState(wx->fd, &wx->old_dcb)) {
		DBG("SetCommState() %s\n", last_error());
		return;
	}

	if (!SetCommTimeouts(wx->fd, &wx->old_tm)) {
		DBG("SetCommTimeouts() %s\n", last_error());
		return;
	}

	rs232_close(p);
	free(p->pt);
	free(p);
}

RS232_LIB unsigned int
rs232_in_queue(struct rs232_port_t *p, unsigned int *in_bytes)
{
	COMSTAT cs;
	unsigned long errmask = 0;
	struct rs232_windows_t *wx = p->pt;

	DBG("p=%p p->pt=%p\n", (void *)p, p->pt);

	if (!rs232_port_open(p))
		return RS232_ERR_PORT_CLOSED;

	if (!ClearCommError(wx->fd, &errmask, &cs)) {
		DBG("ClearCommError() %s\n", last_error());
		return RS232_ERR_IOCTL;
	}

	*in_bytes = cs.cbInQue;
	DBG("in_bytes=%d\n", cs.cbInQue);

	return RS232_ERR_NOERROR;
}

/* some USB<->RS232 converters buffer a lot, so this function tries to discard
   this buffer - useful mainly after rs232_open() */
RS232_LIB void
rs232_in_queue_clear(struct rs232_port_t *p)
{
	struct rs232_windows_t *wx = p->pt;

	DBG("p=%p p->pt=%p\n", (void *)p, p->pt);

	if (!rs232_port_open(p))
		return;

	if (!PurgeComm(wx->fd, PURGE_RXABORT | PURGE_RXCLEAR)) {
		DBG("PurgeComm() %s\n", last_error());
		return;
	}

	return;
}

//{ Non overlapped IO

static unsigned int
rs232_read_impl(struct rs232_port_t *p, unsigned char *buf, unsigned int buf_len,
	unsigned int *read_len)
{
	DWORD r = 0;
	struct rs232_windows_t *wx = p->pt;

	if (!ReadFile(wx->fd, buf, buf_len, &r, NULL)) {
		*read_len = 0;
		DBG("ReadFile() %s\n", last_error());
		return RS232_ERR_READ;
	}

	*read_len = r;

	return RS232_ERR_NOERROR;
}

static unsigned int
rs232_read_timeout_impl(struct rs232_port_t *p, unsigned char *buf,
		   unsigned int buf_len, unsigned int *read_len,
		   unsigned int timeout)
{
	DWORD r = 0;
	struct rs232_windows_t *wx = p->pt;
	unsigned int rt = wx->r_timeout;

	*read_len = 0;

	if (port_timeout(p, timeout, wx->w_timeout))
		return RS232_ERR_UNKNOWN;

	if (!ReadFile(wx->fd, buf, buf_len, &r, NULL)) {
		*read_len = 0;
		DBG("ReadFile() %s\n", last_error());
		return RS232_ERR_READ;
	}

	if (port_timeout(p, rt, wx->w_timeout))
		return RS232_ERR_UNKNOWN;

	*read_len = r;

	/* TODO - This is lame, since we rely on the fact, that if we read 0 bytes,
	 * that the read probably timeouted. So we should rather measure the reading
	 * interval or rework it using overlapped I/O */
	return *read_len == 0 ? RS232_ERR_TIMEOUT : RS232_ERR_NOERROR;
}

/* this function waits either for timeout or buf_len bytes,
   whatever happens first and doesn't return earlier */
static unsigned int
rs232_read_timeout_forced_impl(struct rs232_port_t *p, unsigned char *buf,
		   unsigned int buf_len, unsigned int *read_len,
		   unsigned int timeout)
{
	monotonic_time_t started = GetMonotonicTime();

	*read_len = 0;
	while(*read_len < buf_len){
		monotonic_diff_t elapsed = GetMonotonicDelta(started, GetMonotonicTime());
		unsigned int ret, readed = 0;
		if(elapsed >= timeout){
			return RS232_ERR_TIMEOUT;
		}

		ret = rs232_read_timeout_impl(p, &buf[*read_len], buf_len - *read_len, &readed, timeout - elapsed);
		if(ret == RS232_ERR_NOERROR){
			*read_len += readed;
		}
		else if(ret != RS232_ERR_TIMEOUT){
			return ret;
		}
	}

	return RS232_ERR_NOERROR;
}

static unsigned int
rs232_write_impl(struct rs232_port_t *p, const unsigned char *buf, unsigned int buf_len,
		unsigned int *write_len)
{
	DWORD w = 0;
	struct rs232_windows_t *wx = p->pt;

	if (!WriteFile(wx->fd, buf, buf_len, &w, NULL)) {
		*write_len = 0;
		DBG("WriteFile() %s\n", last_error());
		return RS232_ERR_WRITE;
	}

	if (buf_len != w)
		DBG("WriteFile() %s\n", last_error());

	*write_len = w;

	return RS232_ERR_NOERROR;
}

static unsigned int
rs232_write_timeout_impl(struct rs232_port_t *p, const unsigned char *buf,
			unsigned int buf_len, unsigned int *write_len,
			unsigned int timeout)
{
	DWORD w = 0;
	struct rs232_windows_t *wx = p->pt;
	unsigned int wt = wx->w_timeout;

	if (port_timeout(p, wx->r_timeout, timeout))
		return RS232_ERR_UNKNOWN;

	if (!WriteFile(wx->fd, buf, buf_len, &w, NULL)) {
		*write_len = 0;
		DBG("WriteFile() %s\n", last_error());
		return RS232_ERR_WRITE;
	}

	if (port_timeout(p, wx->r_timeout, wt))
		return RS232_ERR_UNKNOWN;

	*write_len = w;

	return RS232_ERR_NOERROR;
}

//}

//{ Overlapped IO

static unsigned int
poll_ovl(struct rs232_port_t *p, unsigned int timeout, DWORD events, DWORD *mask){
	struct rs232_windows_t *wx = p->pt;
	DWORD ret;
	monotonic_time_t started = GetMonotonicTime();

	if(!SetCommMask(wx->fd, events))
		return RS232_ERR_IOCTL;

	*mask = 0;

	while(1){
		monotonic_diff_t elapsed = GetMonotonicDelta(started, GetMonotonicTime());
		if(elapsed >= timeout)
			return RS232_ERR_TIMEOUT;

		if(!wx->wait_progress){
			wx->wait_mask = 0;
			if (WaitCommEvent(wx->fd, &wx->wait_mask, &wx->oWait))
				goto readed;

			if (GetLastError() != ERROR_IO_PENDING)
				return RS232_ERR_IOCTL;
		}

		wx->wait_progress = 1;

		ret = WaitForSingleObject(wx->oWait.hEvent, timeout - elapsed);
		if(ret != WAIT_OBJECT_0)
			return RS232_ERR_TIMEOUT;

		if(!GetOverlappedResult(wx->fd, &wx->oWait, &ret, FALSE))
			return RS232_ERR_IOCTL;

readed:

		wx->wait_progress = 0;

		if(wx->wait_mask)
			break;
	}

	*mask = wx->wait_mask;
	return RS232_ERR_NOERROR;
}

static unsigned int
read_n_ovl(struct rs232_port_t *p, unsigned char *buf, unsigned int buf_len,
		DWORD *read_len, DWORD *ermask
)
{
	/* read avaliable data without waiting */
	struct rs232_windows_t *wx = p->pt;
	OVERLAPPED ovl = {0};
	COMSTAT cs = {0};
	DWORD readed, avaliable;

	*read_len = 0;

	if (!ClearCommError(wx->fd, ermask, &cs))
		return RS232_ERR_IOCTL;

	avaliable = cs.cbInQue > buf_len ? buf_len : cs.cbInQue;
	if (avaliable) {
		if (!ReadFile(wx->fd, buf, avaliable, &readed, &ovl)) {
			if (GetLastError() != ERROR_IO_PENDING)
				return RS232_ERR_READ;

			if(!GetOverlappedResult(wx->fd, &ovl, &readed, TRUE))
				return RS232_ERR_READ;
		}
		*read_len = readed;
	}

	return RS232_ERR_NOERROR;
}

static unsigned int
rs232_read_ovl(struct rs232_port_t *p, unsigned char *buf,
		unsigned int buf_len, unsigned int *read_len,
		unsigned int timeout, unsigned int lat,
		DWORD events, unsigned int *evmask
)
{
	struct rs232_windows_t *wx = p->pt;
	monotonic_time_t started = GetMonotonicTime();
	unsigned char *ptr = buf;

	*read_len = 0;

	while (1) {
		DWORD readed, error_mask, event_mask;
		unsigned int ret;
		monotonic_diff_t elapsed = GetMonotonicDelta(started, GetMonotonicTime());

		if (elapsed > timeout)
			return *read_len ? RS232_ERR_NOERROR : RS232_ERR_TIMEOUT;

		ret = read_n_ovl(p, ptr, buf_len - *read_len, &readed, &error_mask);

		if (error_mask) {
			if (error_mask & CE_BREAK)
				ret = RS232_ERR_BREAK;

			if (error_mask & CE_RXOVER)
				ret = RS232_ERR_RXOVERFLOW;

			if (error_mask & CE_OVERRUN)
				ret = RS232_ERR_OVERRUN;

			if (error_mask & CE_FRAME)
				ret = RS232_ERR_FRAME;

			if (error_mask & CE_RXPARITY)
				ret = RS232_ERR_PARITY;
		}

		if (ret != RS232_ERR_NOERROR)
			return ret;

		if(readed){/* reduce timeout to max latentency*/
			if((timeout - elapsed) > lat)
				timeout = elapsed + lat;
		}

		if(!readed){
			ret = poll_ovl(p, timeout - elapsed, events, &event_mask);

			if(evmask) *evmask = event_mask;

			if(ret != RS232_ERR_NOERROR)
				return *read_len ? RS232_ERR_NOERROR : RS232_ERR_TIMEOUT;

			//! @todo check event_mask (e.g. (event_mask & EV_BREAK) || (event_mask & EV_ERR))

			continue;
		}

		ptr += readed;
		*read_len += readed;

		assert(*read_len <= buf_len);

		if(*read_len == buf_len)
			break;
	}

	return RS232_ERR_NOERROR;
}

static unsigned int
rs232_read_ovl_impl(struct rs232_port_t *p, unsigned char *buf, unsigned int buf_len,
	unsigned int *read_len)
{
	struct rs232_windows_t *wx = p->pt;

	if (!rs232_port_open(p))
		return RS232_ERR_PORT_CLOSED;

	return rs232_read_ovl(p, buf, buf_len, read_len, INFINITE, READ_LATENTENCY, READ_EVENTS, NULL);
}

/* this function waits either for timeout or buf_len bytes,
   whatever happens first and doesn't return earlier */
static unsigned int
rs232_read_timeout_forced_ovl_impl(struct rs232_port_t *p, unsigned char *buf,
		   unsigned int buf_len, unsigned int *read_len,
		   unsigned int timeout)
{
	struct rs232_windows_t *wx = p->pt;

	if (!rs232_port_open(p))
		return RS232_ERR_PORT_CLOSED;

	return rs232_read_ovl(p, buf, buf_len, read_len, timeout, timeout, READ_EVENTS, NULL);
}

static unsigned int
rs232_read_timeout_ovl_impl(struct rs232_port_t *p, unsigned char *buf,
		   unsigned int buf_len, unsigned int *read_len,
		   unsigned int timeout)
{
	struct rs232_windows_t *wx = p->pt;

	if (!rs232_port_open(p))
		return RS232_ERR_PORT_CLOSED;

	return rs232_read_ovl(p, buf, buf_len, read_len, timeout, READ_LATENTENCY, READ_EVENTS, NULL);
}

static unsigned int
rs232_write_ovl(struct rs232_port_t *p, const unsigned char *buf, unsigned int buf_len,
		unsigned int *write_len)
{
	OVERLAPPED oWrite = {0};
	DWORD w = 0;
	struct rs232_windows_t *wx = p->pt;

	*write_len = 0;

	if(!WriteFile(wx->fd, buf, buf_len, &w, &oWrite)){
		DWORD ret;
		if(GetLastError() != ERROR_IO_PENDING){
			DBG("WriteFile() %s\n", last_error());
			return RS232_ERR_WRITE;
		}
		if(!GetOverlappedResult(wx->fd, &oWrite, &ret, TRUE)){
			DBG("OverlappedResult() %s\n", last_error());
			// wtf? If we get error how cancel current write operation?
			return RS232_ERR_WRITE;
		}
		w = ret;
	}

	*write_len = w;
	return RS232_ERR_NOERROR;
}

static unsigned int
rs232_write_ovl_impl(struct rs232_port_t *p, const unsigned char *buf, unsigned int buf_len,
		unsigned int *write_len)
{
	struct rs232_windows_t *wx = p->pt;
	unsigned int ret;

	DBG("p=%p p->pt=%p buf_len:%d\n", (void *)p, p->pt, buf_len);

	if (!rs232_port_open(p))
		return RS232_ERR_PORT_CLOSED;

	ret = rs232_write_ovl(p, buf, buf_len, write_len);
	if (ret != RS232_ERR_NOERROR) {
		return ret;
	}

	if (buf_len != *write_len)
		DBG("WriteFile() %s\n", last_error());

	DBG("write_len=%d hex='%s' ascii='%s'\n", *write_len, rs232_hex_dump(buf, w),
	    rs232_ascii_dump(buf, w));

	return RS232_ERR_NOERROR;
}

static unsigned int
rs232_write_timeout_ovl_impl(struct rs232_port_t *p, const unsigned char *buf,
			unsigned int buf_len, unsigned int *write_len,
			unsigned int timeout)
{
	struct rs232_windows_t *wx = p->pt;
	unsigned int wt = wx->w_timeout;
	unsigned int ret;

	if (port_timeout(p, wx->r_timeout, timeout))
		return RS232_ERR_UNKNOWN;

	ret = rs232_write_ovl(p, buf, buf_len, write_len);
	if (ret != RS232_ERR_NOERROR)
		return ret;

	if (port_timeout(p, wx->r_timeout, wt))
		return RS232_ERR_UNKNOWN;

	return RS232_ERR_NOERROR;
}

//}

//{ Public API IP

RS232_LIB unsigned int
rs232_read(struct rs232_port_t *p, unsigned char *buf, unsigned int buf_len,
	unsigned int *read_len)
{
	unsigned int ret;

	DBG("p=%p p->pt=%p buf_len:%d\n", (void *)p, p->pt, buf_len);

	if (!rs232_port_open(p))
		return RS232_ERR_PORT_CLOSED;

#ifdef USE_OVERLAPPED
	ret = rs232_read_ovl_impl(p, buf, buf_len, read_len);
#else
	ret = rs232_read_impl(p, buf, buf_len, read_len);
#endif

	DBG("read_len=%d hex='%s' ascii='%s'\n", r, rs232_hex_dump(buf, *read_len),
		rs232_ascii_dump(buf, *read_len));

	return ret;
}

/* this function waits either for timeout or buf_len bytes,
   whatever happens first and doesn't return earlier */
RS232_LIB unsigned int
rs232_read_timeout_forced(struct rs232_port_t *p, unsigned char *buf,
		   unsigned int buf_len, unsigned int *read_len,
		   unsigned int timeout)
{
	unsigned int ret;

	DBG("p=%p p->pt=%p buf_len:%d timeout:%d\n", (void *)p, p->pt, buf_len, timeout);

	if (!rs232_port_open(p))
		return RS232_ERR_PORT_CLOSED;

#ifdef USE_OVERLAPPED
	ret = rs232_read_timeout_forced_ovl_impl(p, buf, buf_len, read_len, timeout);
#else
	ret = rs232_read_timeout_forced_impl(p, buf, buf_len, read_len, timeout);
#endif

	DBG("read_len=%d hex='%s' ascii='%s'\n", r, rs232_hex_dump(buf, *read_len),
		rs232_ascii_dump(buf, *read_len));

	return ret;
}

RS232_LIB unsigned int
rs232_read_timeout(struct rs232_port_t *p, unsigned char *buf,
		   unsigned int buf_len, unsigned int *read_len,
		   unsigned int timeout)
{
	unsigned int ret;

	DBG("p=%p p->pt=%p buf_len:%d timeout:%d\n", (void *)p, p->pt, buf_len, timeout);

	if (!rs232_port_open(p))
		return RS232_ERR_PORT_CLOSED;

#ifdef USE_OVERLAPPED
	ret = rs232_read_timeout_ovl_impl(p, buf, buf_len, read_len, timeout);
#else
	ret = rs232_read_timeout_impl(p, buf, buf_len, read_len, timeout);
#endif

	DBG("read_len=%d hex='%s' ascii='%s'\n", r, rs232_hex_dump(buf, *read_len),
		rs232_ascii_dump(buf, *read_len));

	return ret;
}

RS232_LIB unsigned int
rs232_write(struct rs232_port_t *p, const unsigned char *buf, unsigned int buf_len,
		unsigned int *write_len)
{
	unsigned int ret;

	DBG("p=%p p->pt=%p buf_len:%d\n", (void *)p, p->pt, buf_len);

	if (!rs232_port_open(p))
		return RS232_ERR_PORT_CLOSED;

#ifdef USE_OVERLAPPED
	ret = rs232_write_ovl_impl(p, buf, buf_len, write_len);
#else
	ret = rs232_write_impl(p, buf, buf_len, write_len);
#endif

	DBG("write_len=%d hex='%s' ascii='%s'\n", w, rs232_hex_dump(buf, *write_len),
	    rs232_ascii_dump(buf, *write_len));

	return ret;
}

RS232_LIB unsigned int
rs232_write_timeout(struct rs232_port_t *p, const unsigned char *buf,
			unsigned int buf_len, unsigned int *write_len,
			unsigned int timeout)
{
	unsigned int ret;

	DBG("p=%p p->pt=%p buf_len:%d timeout: %d\n", (void *)p, p->pt, buf_len, timeout);

	if (!rs232_port_open(p))
		return RS232_ERR_PORT_CLOSED;

#ifdef USE_OVERLAPPED
	ret = rs232_write_timeout_ovl_impl(p, buf, buf_len, write_len, timeout);
#else
	ret = rs232_write_timeout_impl(p, buf, buf_len, write_len, timeout);
#endif

	DBG("write_len=%d hex='%s' ascii='%s'\n", w, rs232_hex_dump(buf, *write_len),
	    rs232_ascii_dump(buf, *write_len));

	return ret;
}

//}

static char *
fix_device_name(char *device, char *ret)
{
	char *s = device;
	/* meh, Windows CE is special and can't handle URN path, just COM1: format */

	if((s[0] == '\\')&&(s[1] == '\\')&&(s[2] == '.')&&(s[3] == '\\')){
#ifdef UNDER_CE
	/* remove URN prefix */
	snprintf(ret, RS232_STRLEN_DEVICE, "%s", s + 4);
	return ret;
#else
	return s;
#endif
	}

#ifdef UNDER_CE
	return s;
#else
	snprintf(ret, RS232_STRLEN_DEVICE, "\\\\.\\%s", s);
	return ret;
#endif
}

RS232_LIB unsigned int
rs232_open(struct rs232_port_t *p)
{
	char tmp[RS232_STRLEN_DEVICE+1] = {0};
	wchar_t *wname = a2w(fix_device_name(p->dev, tmp));
	struct rs232_windows_t *wx = p->pt;

	DBG("p=%p p->pt=%p name='%s' fix='%s'\n",
	    (void *)p, p->pt, p->dev, fix_device_name(p->dev, tmp));

	if (wname == NULL)
		return RS232_ERR_UNKNOWN;

	wx->fd = CreateFileW(wname, GENERIC_READ | GENERIC_WRITE,
			0, NULL, OPEN_EXISTING,
#ifdef USE_OVERLAPPED
			FILE_FLAG_OVERLAPPED,
#else
			0,
#endif
			NULL);

	if (wname)
		free(wname);

	if (wx->fd == INVALID_HANDLE_VALUE) {
		DBG("CreateFile() %s\n", last_error());
		return RS232_ERR_OPEN;
	}

#ifdef USE_OVERLAPPED
	memset(&wx->oWait, 0, sizeof(wx->oWait));
	wx->oWait.hEvent = CreateEvent(NULL, TRUE, FALSE, NULL);
	if(wx->oWait.hEvent == NULL){
		CloseHandle(wx->fd);
		wx->fd = INVALID_HANDLE_VALUE;
		return RS232_ERR_OPEN;
	}
	wx->wait_progress = 0;
#endif

	p->status = RS232_PORT_OPEN;
	rs232_flush(p);

	GET_PORT_STATE(wx->fd, &wx->old_dcb);
	GET_PORT_TIMEOUTS(wx->fd, &wx->old_tm);

	port_timeout(p, wx->r_timeout, wx->w_timeout);
	port_buffers(p, wx->r_buffer, wx->w_buffer);

	rs232_set_baud(p, p->baud);
	rs232_set_data(p, p->data);
	rs232_set_parity(p, p->parity);
	rs232_set_stop(p, p->stop);
	rs232_set_flow(p, p->flow);

	return RS232_ERR_NOERROR;
}

RS232_LIB void
rs232_set_device(struct rs232_port_t *p, const char *device)
{
	DBG("p=%p old=%s new=%s\n", (void *)p, p->dev, device);
	strncpyz(p->dev, device, RS232_STRLEN_DEVICE);

	return;
}

RS232_LIB unsigned int
rs232_set_baud(struct rs232_port_t *p, enum rs232_baud_e baud)
{
	DCB pdcb;
	struct rs232_windows_t *wx = p->pt;

	DBG("p=%p p->pt=%p baud=%d (%s bauds)\n",
	    (void *)p, p->pt, baud, rs232_strbaud(baud));

	if (!rs232_port_open(p))
		return RS232_ERR_PORT_CLOSED;

	GET_PORT_STATE(wx->fd, &pdcb);

	switch (baud) {
	case RS232_BAUD_300:
		pdcb.BaudRate = CBR_300;
		break;
	case RS232_BAUD_2400:
		pdcb.BaudRate = CBR_2400;
		break;
	case RS232_BAUD_4800:
		pdcb.BaudRate = CBR_4800;
		break;
	case RS232_BAUD_9600:
		pdcb.BaudRate = CBR_9600;
		break;
	case RS232_BAUD_19200:
		pdcb.BaudRate = CBR_19200;
		break;
	case RS232_BAUD_38400:
		pdcb.BaudRate = CBR_38400;
		break;
	case RS232_BAUD_57600:
		pdcb.BaudRate = CBR_57600;
		break;
	case RS232_BAUD_115200:
		pdcb.BaudRate = CBR_115200;
		break;
	case RS232_BAUD_460800:
		pdcb.BaudRate = CBR_460800;
		break;
	default:
		return RS232_ERR_UNKNOWN;
	}

	SET_PORT_STATE(wx->fd, &pdcb);
	p->baud = baud;

	return RS232_ERR_NOERROR;
}

RS232_LIB unsigned int
rs232_set_dtr(struct rs232_port_t *p, enum rs232_dtr_e state)
{
	DCB pdcb;
	struct rs232_windows_t *wx = p->pt;

	DBG("p=%p p->pt=%p dtr=%d (dtr control %s)\n",
	    (void *)p, p->pt, state, rs232_strdtr(state));

	if (!rs232_port_open(p))
		return RS232_ERR_PORT_CLOSED;

	GET_PORT_STATE(wx->fd, &pdcb);

	switch (state) {
	case RS232_DTR_OFF:
		pdcb.fDtrControl = DTR_CONTROL_DISABLE;
		break;
	case RS232_DTR_ON:
		pdcb.fDtrControl = DTR_CONTROL_ENABLE;
		break;
	default:
		return RS232_ERR_UNKNOWN;
	}

	SET_PORT_STATE(wx->fd, &pdcb);
	p->dtr = state;

	return RS232_ERR_NOERROR;
}

RS232_LIB unsigned int
rs232_set_rts(struct rs232_port_t *p, enum rs232_rts_e state)
{
	DCB pdcb;
	struct rs232_windows_t *wx = p->pt;

	DBG("p=%p p->pt=%p rts=%d (rts control %s)\n",
	    (void *)p, p->pt, state, rs232_strrts(state));

	if (!rs232_port_open(p))
		return RS232_ERR_PORT_CLOSED;

	GET_PORT_STATE(wx->fd, &pdcb);

	switch (state) {
	case RS232_RTS_OFF:
		pdcb.fRtsControl = RTS_CONTROL_DISABLE;
		break;
	case RS232_RTS_ON:
		pdcb.fRtsControl = RTS_CONTROL_ENABLE;
		break;
	default:
		return RS232_ERR_UNKNOWN;
	}

	SET_PORT_STATE(wx->fd, &pdcb);
	p->rts = state;

	return RS232_ERR_NOERROR;
}

RS232_LIB unsigned int
rs232_set_parity(struct rs232_port_t *p, enum rs232_parity_e parity)
{
	DCB pdcb;
	struct rs232_windows_t *wx = p->pt;

	DBG("p=%p p->pt=%p parity=%d (parity %s)\n",
	    (void *)p, p->pt, parity, rs232_strparity(parity));

	if (!rs232_port_open(p))
		return RS232_ERR_PORT_CLOSED;

	GET_PORT_STATE(wx->fd, &pdcb);

	switch (parity) {
	case RS232_PARITY_NONE:
		pdcb.Parity = NOPARITY;
		break;
	case RS232_PARITY_ODD:
		pdcb.Parity = ODDPARITY;
		break;
	case RS232_PARITY_EVEN:
		pdcb.Parity = EVENPARITY;
		break;
	default:
		return RS232_ERR_UNKNOWN;
	}

	SET_PORT_STATE(wx->fd, &pdcb);
	p->parity = parity;

	return RS232_ERR_NOERROR;
}

RS232_LIB unsigned int
rs232_set_stop(struct rs232_port_t *p, enum rs232_stop_e stop)
{
	DCB pdcb;
	struct rs232_windows_t *wx = p->pt;

	DBG("p=%p p->pt=%p stop=%d (%s stop bits)\n",
	    (void *)p, p->pt, stop, rs232_strstop(stop));

	if (!rs232_port_open(p))
		return RS232_ERR_PORT_CLOSED;

	GET_PORT_STATE(wx->fd, &pdcb);

	switch (stop) {
	case RS232_STOP_1:
		pdcb.StopBits = ONESTOPBIT;
		break;
	case RS232_STOP_2:
		pdcb.StopBits = TWOSTOPBITS;
		break;
	default:
		return RS232_ERR_UNKNOWN;
	}

	SET_PORT_STATE(wx->fd, &pdcb);
	p->stop = stop;

	return RS232_ERR_NOERROR;
}

RS232_LIB unsigned int
rs232_set_data(struct rs232_port_t *p, enum rs232_data_e data)
{
	DCB pdcb;
	struct rs232_windows_t *wx = p->pt;

	DBG("p=%p p->pt=%p data=%d (%s data bits)\n",
	    (void *)p, p->pt, data, rs232_strdata(data));

	if (!rs232_port_open(p))
		return RS232_ERR_PORT_CLOSED;

	GET_PORT_STATE(wx->fd, &pdcb);

	switch (data) {
	case RS232_DATA_5:
		pdcb.ByteSize = 5;
		break;
	case RS232_DATA_6:
		pdcb.ByteSize = 6;
		break;
	case RS232_DATA_7:
		pdcb.ByteSize = 7;
		break;
	case RS232_DATA_8:
		pdcb.ByteSize = 8;
		break;
	default:
		return RS232_ERR_UNKNOWN;
	}

	SET_PORT_STATE(wx->fd, &pdcb);
	p->data = data;

	return RS232_ERR_NOERROR;
}

RS232_LIB unsigned int
rs232_set_flow(struct rs232_port_t *p, enum rs232_flow_e flow)
{
	DCB pdcb;
	struct rs232_windows_t *wx = p->pt;

	DBG("p=%p p->pt=%p flow=%d (flow control %s)\n",
	    (void *)p, p->pt, flow, rs232_strflow(flow));

	if (!rs232_port_open(p))
		return RS232_ERR_PORT_CLOSED;

	GET_PORT_STATE(wx->fd, &pdcb);

	switch (flow) {
	case RS232_FLOW_OFF:
		pdcb.fOutxCtsFlow = FALSE;
		pdcb.fRtsControl = RTS_CONTROL_DISABLE;
		pdcb.fInX = FALSE;
		pdcb.fOutX = FALSE;
		break;
	case RS232_FLOW_HW:
		pdcb.fOutxCtsFlow = TRUE;
		pdcb.fRtsControl = RTS_CONTROL_HANDSHAKE;
		pdcb.fInX = FALSE;
		pdcb.fOutX = FALSE;
		break;
	case RS232_FLOW_XON_XOFF:
		pdcb.fOutxCtsFlow = FALSE;
		pdcb.fRtsControl = RTS_CONTROL_DISABLE;
		pdcb.fInX = TRUE;
		pdcb.fOutX = TRUE;
		break;
	default:
		return RS232_ERR_UNKNOWN;
	}

	SET_PORT_STATE(wx->fd, &pdcb);

	p->flow = flow;

	return RS232_ERR_NOERROR;
}

RS232_LIB unsigned int
rs232_flush(struct rs232_port_t *p)
{
	struct rs232_windows_t *wx = p->pt;

	DBG("p=%p p->pt=%p\n", (void *)p, p->pt);

	if (!rs232_port_open(p))
		return RS232_ERR_PORT_CLOSED;

	if (!FlushFileBuffers(wx->fd)) {
		DBG("FlushFileBuffers() %s\n", last_error());
		return RS232_ERR_FLUSH;
	}

	if (!PurgeComm(wx->fd, PURGE_TXABORT | PURGE_RXABORT |
		       PURGE_TXCLEAR | PURGE_RXCLEAR)) {
		DBG("PurgeComm() %s\n", last_error());
		return RS232_ERR_FLUSH;
	}

	return RS232_ERR_NOERROR;
}

RS232_LIB unsigned int
rs232_close(struct rs232_port_t *p)
{
	int ret;
	struct rs232_windows_t *wx = p->pt;

	DBG("p=%p p->pt=%p\n", (void *)p, p->pt);

	if (!rs232_port_open(p))
		return RS232_ERR_PORT_CLOSED;

	ret = CloseHandle(wx->fd);
	if (ret == 0) {
		DBG("CloseHandle() %s\n", last_error());
		return RS232_ERR_CLOSE;
	}

#ifdef USE_OVERLAPPED
	ret = CloseHandle(wx->oWait.hEvent);
	if (ret == 0) {
		DBG("CloseHandle() %s\n", last_error());
		 return RS232_ERR_CLOSE;
	}

	wx->wait_progress = 0;
#endif

	return RS232_ERR_NOERROR;
}

RS232_LIB unsigned int
rs232_fd(struct rs232_port_t *p)
{
	struct rs232_windows_t *wx = p->pt;

	DBG("p=%p p->pt=%p wx->fd=%d\n", (void *)p, p->pt, wx->fd);

	return (unsigned int) wx->fd;
}
