#include "luat_base.h"

#include "luat_network_adapter.h"
#include "luat_rtos.h"
#include "luat_zbuff.h"
#include "luat_malloc.h"
#include "luat_websocket.h"
// #include "http_parser.h"

#define LUAT_LOG_TAG "websocket"
#include "luat_log.h"

#define WEBSOCKET_DEBUG 0
#if WEBSOCKET_DEBUG == 0
#undef LLOGD
#define LLOGD(...)
#endif

#if WEBSOCKET_DEBUG
static void print_pkg(const char *tag, char *buff, luat_websocket_pkg_t *pkg)
{
	if (pkg == NULL)
	{
		LLOGD("pkg is NULL");
		return;
	}
	LLOGD("%s pkg %02X%02X", tag, buff[0], buff[1]);
	LLOGD("%s pkg FIN %d R %d OPT %d MARK %d PLEN %d", tag, pkg->FIN, pkg->R, pkg->OPT_CODE, pkg->mark, pkg->plen);
}
#else
#define print_pkg(...)
#endif

int luat_websocket_payload(char *buf, luat_websocket_pkg_t *pkg, size_t limit)
{
	uint32_t pkg_len = 0;
	// 先处理FIN
	if (buf[0] && (1 << 7))
	{
		pkg->FIN = 1;
	}
	// 处理操作码
	pkg->OPT_CODE = buf[0] & 0xF;
	// 然后处理plen
	pkg->plen = buf[1] & 0x7F;

	print_pkg("downlink", buf, pkg);
	// websocket的payload长度支持3种情况:
	// 0字节(小于126,放在头部)
	// 2个字节 126 ~ 0xFFFF
	// 6个字节 0x1000 ~ 0xFFFFFFFF, 不打算支持.
	if (pkg->plen == 126)
	{
		if (limit < 4)
		{
			// 还缺1个字节,等吧
			LLOGD("wait more data offset %d", limit);
			return 0;
		}
		pkg->plen = (buf[2] & 0xFF) << 8;
		pkg->plen += (buf[3] & 0xFF);
		pkg_len = 4 + pkg->plen;
		pkg->payload = buf + 4;
	}
	else if (pkg->plen == 127)
	{
		// 后续还要8个字节,但这个包也太大了吧!!!
		LLOGE("websocket payload is too large!!!");
		return -1;
	}
	else
	{
		pkg_len = 2 + pkg->plen;
		pkg->payload = buf + 2;
	}

	LLOGD("payload %04X pkg %04X", pkg->plen, pkg_len);
	if (limit < pkg_len)
	{
		LLOGD("wait more data offset %d", limit);
		return 0;
	}

	return 1;
}

int luat_websocket_send_packet(void *socket_info, const void *buf, unsigned int count)
{
	luat_websocket_ctrl_t *websocket_ctrl = (luat_websocket_ctrl_t *)socket_info;
	uint32_t tx_len = 0;
	int ret = network_tx(websocket_ctrl->netc, buf, count, 0, NULL, 0, &tx_len, 0);
	if (ret < 0)
	{
		LLOGI("network_tx %d , close socket", ret);
		luat_websocket_close_socket(websocket_ctrl);
		return 0;
	}
	return count;
}

void luat_websocket_ping(luat_websocket_ctrl_t *websocket_ctrl)
{
	if (websocket_ctrl->websocket_state != 0)
		return;
	luat_websocket_pkg_t pkg = {
		.FIN = 1,
		.OPT_CODE = WebSocket_OP_PING,
		.plen = 0};
	luat_websocket_send_frame(websocket_ctrl, &pkg);
}

void luat_websocket_pong(luat_websocket_ctrl_t *websocket_ctrl)
{
	luat_websocket_pkg_t pkg = {
		.FIN = 1,
		.OPT_CODE = WebSocket_OP_PONG,
		.plen = 0};
	luat_websocket_send_frame(websocket_ctrl, &pkg);
}

void luat_websocket_reconnect(luat_websocket_ctrl_t *websocket_ctrl) {
	int ret = luat_websocket_connect(websocket_ctrl);
	if (ret)
	{
		LLOGI("reconnect init socket ret=%d\n", ret);
		luat_websocket_close_socket(websocket_ctrl);
	}
}

LUAT_RT_RET_TYPE luat_websocket_timer_callback(LUAT_RT_CB_PARAM)
{
	luat_websocket_ctrl_t *websocket_ctrl = (luat_websocket_ctrl_t *)param;
	l_luat_websocket_msg_cb(websocket_ctrl, WEBSOCKET_MSG_TIMER_PING, 0);
}

static void reconnect_timer_cb(LUAT_RT_CB_PARAM)
{
	luat_websocket_ctrl_t *websocket_ctrl = (luat_websocket_ctrl_t *)param;
	l_luat_websocket_msg_cb(websocket_ctrl, WEBSOCKET_MSG_RECONNECT, 0);
}

int luat_websocket_init(luat_websocket_ctrl_t *websocket_ctrl, int adapter_index)
{
	memset(websocket_ctrl, 0, sizeof(luat_websocket_ctrl_t));
	websocket_ctrl->adapter_index = adapter_index;
	websocket_ctrl->netc = network_alloc_ctrl(adapter_index);
	if (!websocket_ctrl->netc)
	{
		LLOGW("network_alloc_ctrl fail");
		return -1;
	}
	network_init_ctrl(websocket_ctrl->netc, NULL, luat_websocket_callback, websocket_ctrl);

	websocket_ctrl->websocket_state = 0;
	websocket_ctrl->netc->is_debug = 0;
	websocket_ctrl->keepalive = 60;
	network_set_base_mode(websocket_ctrl->netc, 1, 10000, 0, 0, 0, 0);
	network_set_local_port(websocket_ctrl->netc, 0);
	websocket_ctrl->reconnect_timer = luat_create_rtos_timer(reconnect_timer_cb, websocket_ctrl, NULL);
	websocket_ctrl->ping_timer = luat_create_rtos_timer(luat_websocket_timer_callback, websocket_ctrl, NULL);
	return 0;
}

int luat_websocket_set_connopts(luat_websocket_ctrl_t *websocket_ctrl, const char *url)
{
	int is_tls = 0;
	const char *tmp = url;
	LLOGD("url %s", url);

	// TODO 支持基本授权的URL ws://wendal:123@wendal.cn:8080/abc

	websocket_ctrl->host[0] = 0;
	char port_tmp[6] = {0};
	uint16_t port = 0;

	if (!memcmp(tmp, "wss://", strlen("wss://")))
	{
		// LLOGD("using WSS");
		is_tls = 1;
		tmp += strlen("wss://");
	}
	else if (!memcmp(tmp, "ws://", strlen("ws://")))
	{
		// LLOGD("using ws");
		is_tls = 0;
		tmp += strlen("ws://");
	}

	// LLOGD("tmp %s", tmp);
	size_t uri_start_index = 0;
	for (size_t i = 0; i < strlen(tmp); i++)
	{
		if (tmp[i] == '/')
		{
			uri_start_index = i;
			break;
		}
	}
	if (uri_start_index < 2) {
		uri_start_index = strlen(tmp);
	}
	for (size_t j = 0; j < uri_start_index; j++)
	{
		if (tmp[j] == ':')
		{
			memcpy(websocket_ctrl->host, tmp, j);
			websocket_ctrl->host[j] = 0;
			memcpy(port_tmp, tmp + j + 1, uri_start_index - j - 1);
			port = atoi(port_tmp);
			//LLOGD("port str %s %d", port_tmp, port);
			// LLOGD("found custom host %s port %d", websocket_ctrl->host, port);
			break;
		}
	}
	// 没有自定义host
	if (websocket_ctrl->host[0] == 0)
	{
		memcpy(websocket_ctrl->host, tmp, uri_start_index);
		websocket_ctrl->host[uri_start_index] = 0;
		// LLOGD("found custom host %s", websocket_ctrl->host);
	}
	memcpy(websocket_ctrl->uri, tmp + uri_start_index, strlen(tmp) - uri_start_index);
	websocket_ctrl->uri[strlen(tmp) - uri_start_index] = 0;

	if (port == 0) {
		port = is_tls ? 443 : 80;
	}

	if (websocket_ctrl->uri[0] == 0)
	{
		websocket_ctrl->uri[0] = '/';
		websocket_ctrl->uri[1] = 0x00;
	}

	// LLOGD("host %s port %d uri %s", host, port, uri);
	// memcpy(websocket_ctrl->host, host, strlen(host) + 1);
	websocket_ctrl->remote_port = port;
	// memcpy(websocket_ctrl->uri, uri, strlen(uri) + 1);
	LLOGD("host %s port %d uri %s", websocket_ctrl->host, port, websocket_ctrl->uri);

	if (is_tls)
	{
		if (network_init_tls(websocket_ctrl->netc, 0)){
			return -1;
		}
	}
	else
	{
		network_deinit_tls(websocket_ctrl->netc);
	}
	return 0;
}

static void websocket_reconnect(luat_websocket_ctrl_t *websocket_ctrl)
{
	LLOGI("reconnect after %dms", websocket_ctrl->reconnect_time);
	websocket_ctrl->buffer_offset = 0;
	//websocket_ctrl->reconnect_timer = luat_create_rtos_timer(reconnect_timer_cb, websocket_ctrl, NULL);
	luat_stop_rtos_timer(websocket_ctrl->reconnect_timer);
	luat_start_rtos_timer(websocket_ctrl->reconnect_timer, websocket_ctrl->reconnect_time, 0);
}

void luat_websocket_close_socket(luat_websocket_ctrl_t *websocket_ctrl)
{
	LLOGI("websocket closing socket");
	if (websocket_ctrl->netc)
	{
		network_force_close_socket(websocket_ctrl->netc);
	}
	l_luat_websocket_msg_cb(websocket_ctrl, WEBSOCKET_MSG_DISCONNECT, 0);
	luat_stop_rtos_timer(websocket_ctrl->ping_timer);
	websocket_ctrl->websocket_state = 0;
	if (websocket_ctrl->reconnect) {
		websocket_reconnect(websocket_ctrl);
	}
}

void luat_websocket_release_socket(luat_websocket_ctrl_t *websocket_ctrl)
{
	l_luat_websocket_msg_cb(websocket_ctrl, WEBSOCKET_MSG_RELEASE, 0);
	if (websocket_ctrl->ping_timer) {
		luat_release_rtos_timer(websocket_ctrl->ping_timer);
    	websocket_ctrl->ping_timer = NULL;
	}
	if (websocket_ctrl->reconnect_timer) {
		luat_release_rtos_timer(websocket_ctrl->reconnect_timer);
    	websocket_ctrl->reconnect_timer = NULL;
	}
	if (websocket_ctrl->headers) {
		luat_heap_free(websocket_ctrl->headers);
		websocket_ctrl->headers = NULL;
	}
	if (websocket_ctrl->netc)
	{
		network_release_ctrl(websocket_ctrl->netc);
		websocket_ctrl->netc = NULL;
	}
}

static const char* ws_headers = 
						"Upgrade: websocket\r\n"
						"Connection: Upgrade\r\n"
						"Sec-WebSocket-Key: w4v7O6xFTi36lq3RNcgctw==\r\n"
						"Sec-WebSocket-Version: 13\r\n"
						"\r\n";

static int websocket_connect(luat_websocket_ctrl_t *websocket_ctrl)
{
	LLOGD("request host %s port %d uri %s", websocket_ctrl->host, websocket_ctrl->remote_port, websocket_ctrl->uri);
	// 借用pkg_buff
	int ret = snprintf_((char*)websocket_ctrl->pkg_buff,
						WEBSOCKET_RECV_BUF_LEN_MAX,
						"GET %s HTTP/1.1\r\n"
						"Host: %s\r\n",
						websocket_ctrl->uri, websocket_ctrl->host);
	//LLOGD("Request %s", websocket_ctrl->pkg_buff);
	ret = luat_websocket_send_packet(websocket_ctrl, websocket_ctrl->pkg_buff, ret);
	if (websocket_ctrl->headers) {
		luat_websocket_send_packet(websocket_ctrl, websocket_ctrl->headers, strlen(websocket_ctrl->headers));
	}
	luat_websocket_send_packet(websocket_ctrl, ws_headers, strlen(ws_headers));
	LLOGD("websocket_connect ret %d", ret);
	return ret;
}

int luat_websocket_send_frame(luat_websocket_ctrl_t *websocket_ctrl, luat_websocket_pkg_t *pkg)
{
	char *dst = luat_heap_malloc(pkg->plen + 8);
	if (dst == NULL) {
		LLOGE("out of memory when send_frame");
		return -2;
	}
	memset(dst, 0, pkg->plen + 8);
	size_t offset = 0;
	size_t ret = 0;
	// first byte, FIN and OPTCODE
	dst[0] = pkg->FIN << 7;
	dst[0] |= pkg->OPT_CODE & 0xF;
	if (pkg->plen < 126)
	{
		dst[1] = pkg->plen;
		offset = 2;
	}
	else if (pkg->plen < 0xFFFF)
	{
		dst[1] = 126;
		dst[2] = pkg->plen >> 8;
		dst[3] = pkg->plen & 0xFF;
		offset = 4;
	}
	else {
		LLOGE("pkg too large %d", pkg->plen);
		luat_heap_free(dst);
		return -1;
	}
	dst[1] |= 1 << 7;

	print_pkg("uplink", dst, pkg);

	// 添加mark, TODO 改成随机?
	char mark[] = {0, 1, 2, 3};
	memcpy(dst + offset, mark, 4);
	offset += 4;

	if (pkg->plen > 0)
	{
		for (size_t i = 0; i < pkg->plen; i++)
		{
			dst[offset + i] = pkg->payload[i] ^ (mark[i % 4]);
		}
	}

	ret = luat_websocket_send_packet(websocket_ctrl, dst, offset + pkg->plen);
	luat_heap_free(dst);
	return ret;
}

static int websocket_parse(luat_websocket_ctrl_t *websocket_ctrl)
{
	int ret = 0;
	char *buf = (char*)websocket_ctrl->pkg_buff;
	LLOGD("websocket_parse offset %d %d", websocket_ctrl->buffer_offset, websocket_ctrl->websocket_state);
	if (websocket_ctrl->websocket_state == 0)
	{
		if (websocket_ctrl->buffer_offset < strlen("HTTP/1.1 101"))
		{ // 最起码得等5个字符
			LLOGD("wait more data offset %d", websocket_ctrl->buffer_offset);
			return 0;
		}
		// 前3个字符肯定是101, 否则必然是不合法的
		if (memcmp("HTTP/1.1 101", buf, strlen("HTTP/1.1 101")))
		{
			buf[websocket_ctrl->buffer_offset] = 0;
			LLOGD("server not support websocket? resp code %s", buf);
			return -1;
		}
		// 然后找\r\n\r\n
		for (size_t i = 4; i < websocket_ctrl->buffer_offset; i++)
		{
			if (!memcmp("\r\n\r\n", buf + i, 4))
			{
				// LLOGD("Found \\r\\n\\r\\n");
				//  找到了!! 但貌似完全不用处理呢
				websocket_ctrl->buffer_offset = 0;
				LLOGD("ready!!");
				websocket_ctrl->websocket_state = 1;
				luat_stop_rtos_timer(websocket_ctrl->ping_timer);
				luat_start_rtos_timer(websocket_ctrl->ping_timer, 30000, 1);
				l_luat_websocket_msg_cb(websocket_ctrl, WEBSOCKET_MSG_CONNACK, 0);
				return 1;
			}
		}
		// LLOGD("Not Found \\r\\n\\r\\n %s", buf);
		return 0;
	}

	if (websocket_ctrl->buffer_offset < 2)
	{
		LLOGD("wait more data offset %d", websocket_ctrl->buffer_offset);
		return 0;
	}
	// 判断数据长度, 前几个字节能判断出够不够读出websocket的头

	luat_websocket_pkg_t pkg = {0};
	ret = luat_websocket_payload(buf, &pkg, websocket_ctrl->buffer_offset);
	if (ret == 0) {
		LLOGD("wait more data offset %d", websocket_ctrl->buffer_offset);
		return 0;
	}
	if (ret < 0) {
		LLOGI("payload too large!!!");
		return -1;
	}

	switch (pkg.OPT_CODE)
	{
	case 0x01: // 文本帧
		break;
	case 0x02: // 二进制帧
		break;
	case 0x08:
		// 主动断开? 我擦
		LLOGD("server say CLOSE");
		return -1;
	case 0x09:
		// ping->pong
		luat_websocket_pong(websocket_ctrl);
		break;
	case 0x0A:
		break;

	default:
		LLOGE("unkown optcode %0x2X", pkg.OPT_CODE);
		return -1;
	}

	size_t pkg_len = pkg.plen >= 126 ? pkg.plen + 4 : pkg.plen + 2;

	if (pkg.OPT_CODE <= 0x02)
	{
		char *buff = luat_heap_malloc(pkg_len);
		if (buff == NULL)
		{
			LLOGE("out of memory when malloc websocket buff");
			return -1;
		}
		memcpy(buff, buf, pkg_len);
		l_luat_websocket_msg_cb(websocket_ctrl, WEBSOCKET_MSG_PUBLISH, (int)buff);
	}

	// 处理完成后, 如果还有数据, 移动数据, 继续处理
	websocket_ctrl->buffer_offset -= pkg_len;
	if (websocket_ctrl->buffer_offset > 0)
	{
		memmove(websocket_ctrl->pkg_buff, websocket_ctrl->pkg_buff + pkg_len, websocket_ctrl->buffer_offset);
		return 1;
	}
	return 0;
}

int luat_websocket_read_packet(luat_websocket_ctrl_t *websocket_ctrl)
{
	// LLOGD("luat_websocket_read_packet websocket_ctrl->buffer_offset:%d",websocket_ctrl->buffer_offset);
	// int ret = -1;
	// uint8_t *read_buff = NULL;
	uint32_t total_len = 0;
	uint32_t rx_len = 0;
	int result = network_rx(websocket_ctrl->netc, NULL, 0, 0, NULL, NULL, &total_len);
	// if (total_len > 0xFFFF)
	// {
	// 	LLOGE("too many data wait for recv %d", total_len);
	// 	//luat_websocket_close_socket(websocket_ctrl);
	// 	return -1;
	// }
	if (total_len == 0)
	{
		LLOGW("rx event but NO data wait for recv");
		return 0;
	}
	if (WEBSOCKET_RECV_BUF_LEN_MAX - websocket_ctrl->buffer_offset <= 0)
	{
		LLOGE("buff is FULL, websocket packet too big");
		//luat_websocket_close_socket(websocket_ctrl);
		return -1;
	}
#define MAX_READ (1024)
	int recv_want = 0;

	while (WEBSOCKET_RECV_BUF_LEN_MAX - websocket_ctrl->buffer_offset > 0)
	{
		if (MAX_READ > (WEBSOCKET_RECV_BUF_LEN_MAX - websocket_ctrl->buffer_offset))
		{
			recv_want = WEBSOCKET_RECV_BUF_LEN_MAX - websocket_ctrl->buffer_offset;
		}
		else
		{
			recv_want = MAX_READ;
		}
		// 从网络接收数据
		result = network_rx(websocket_ctrl->netc, websocket_ctrl->pkg_buff + websocket_ctrl->buffer_offset, recv_want, 0, NULL, NULL, &rx_len);
		if (rx_len == 0 || result != 0)
		{
			LLOGD("rx_len %d result %d", rx_len, result);
			break;
		}
		// 收到数据了, 传给处理函数继续处理
		// 数据的长度变更, 触发传递
		websocket_ctrl->buffer_offset += rx_len;
		LLOGD("data recv %d offset %d", rx_len, websocket_ctrl->buffer_offset);
	further:
		result = websocket_parse(websocket_ctrl);
		if (result == 0)
		{
			// OK
		}
		else if (result == 1)
		{
			if (websocket_ctrl->buffer_offset > 0)
				goto further;
			else
			{
				continue;
			}
		}
		else
		{
			LLOGW("websocket_parse ret %d", result);
			//luat_websocket_close_socket(websocket_ctrl);
			return -1;
		}
	}
	return 0;
}

int32_t luat_websocket_callback(void *data, void *param)
{
	OS_EVENT *event = (OS_EVENT *)data;
	luat_websocket_ctrl_t *websocket_ctrl = (luat_websocket_ctrl_t *)param;
	int ret = 0;
	// LLOGD("LINK %d ON_LINE %d EVENT %d TX_OK %d CLOSED %d",EV_NW_RESULT_LINK & 0x0fffffff,EV_NW_RESULT_CONNECT & 0x0fffffff,EV_NW_RESULT_EVENT & 0x0fffffff,EV_NW_RESULT_TX & 0x0fffffff,EV_NW_RESULT_CLOSE & 0x0fffffff);
	//LLOGD("network websocket cb %8X %s %8X", event->ID & 0x0ffffffff, network_ctrl_callback_event_string(event->ID), event->Param1);
	if (event->ID == EV_NW_RESULT_LINK)
	{
		return 0; // 这里应该直接返回, 不能往下调用network_wait_event
	}
	else if (event->ID == EV_NW_RESULT_CONNECT)
	{
		if (event->Param1 == 0) {
			ret = websocket_connect(websocket_ctrl);
			if (ret < 0) {
				return 0; // 发送失败, 那么
			}
		}
		else {
			// 连接失败, 重连吧.
		}
	}
	else if (event->ID == EV_NW_RESULT_EVENT)
	{
		if (event->Param1 == 0)
		{
			ret = luat_websocket_read_packet(websocket_ctrl);
			if (ret < 0) {
				luat_websocket_close_socket(websocket_ctrl);
				return ret;
			}
			// LLOGD("luat_websocket_read_packet ret:%d",ret);
			luat_stop_rtos_timer(websocket_ctrl->ping_timer);
			luat_start_rtos_timer(websocket_ctrl->ping_timer, websocket_ctrl->keepalive * 1000 * 0.75, 1);
		}
	}
	else if (event->ID == EV_NW_RESULT_TX)
	{
		luat_stop_rtos_timer(websocket_ctrl->ping_timer);
		luat_start_rtos_timer(websocket_ctrl->ping_timer, websocket_ctrl->keepalive * 1000 * 0.75, 1);
		if (websocket_ctrl->frame_wait) {
			websocket_ctrl->frame_wait --;
			l_luat_websocket_msg_cb(websocket_ctrl, WEBSOCKET_MSG_SENT, 0);
		}
	}
	else if (event->ID == EV_NW_RESULT_CLOSE)
	{
	}
	if (event->Param1)
	{
		LLOGW("websocket_callback param1 %d, closing socket", event->Param1);
		luat_websocket_close_socket(websocket_ctrl);
		return 0;
	}
	ret = network_wait_event(websocket_ctrl->netc, NULL, 0, NULL);
	if (ret < 0)
	{
		LLOGW("network_wait_event ret %d, closing socket", ret);
		luat_websocket_close_socket(websocket_ctrl);
		return -1;
	}
	return 0;
}

int luat_websocket_connect(luat_websocket_ctrl_t *websocket_ctrl)
{
	int ret = 0;
	const char *hostname = websocket_ctrl->host;
	uint16_t port = websocket_ctrl->remote_port;
	LLOGI("connect host %s port %d", hostname, port);
	network_close(websocket_ctrl->netc, 0);
	ret = network_connect(websocket_ctrl->netc, hostname, strlen(hostname), (!network_ip_is_vaild(&websocket_ctrl->ip_addr)) ? NULL : &(websocket_ctrl->ip_addr), port, 0) < 0;
	LLOGD("network_connect ret %d", ret);
	if (ret < 0)
	{
		network_close(websocket_ctrl->netc, 0);
		return -1;
	}
	return 0;
}

int luat_websocket_set_headers(luat_websocket_ctrl_t *websocket_ctrl, const char *headers) {
	if (websocket_ctrl == NULL)
		return 0;
	if (websocket_ctrl->headers != NULL) {
		luat_heap_free(websocket_ctrl->headers);
		websocket_ctrl->headers = NULL;
	}
	if (headers) {
		websocket_ctrl->headers = headers;
	}
	return 0;
}
