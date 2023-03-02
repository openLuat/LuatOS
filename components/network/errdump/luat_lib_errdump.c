
/*
@module  errDump
@summary 错误上报
@version 1.0
@date    2022.12.15
@demo    errDump
@tag     LUAT_CONF_ERRDUMP
@usage
-- 基本用法, 10分钟上报一次,如果有的话
if errDump then
    errDump.config(true, 600)
end

-- 附开源服务器端: https://gitee.com/openLuat/luatos-devlog
*/
#include "luat_base.h"
#include "luat_sys.h"
#include "luat_msgbus.h"
#include "luat_zbuff.h"
#include "ldebug.h"
#include "luat_rtos.h"
#include "luat_mobile.h"
#include "luat_network_adapter.h"
#define LUAT_ERRDUMP_TAG "log"
#include "luat_errdump.h"

#define LUAT_LOG_TAG "errDump"
#include "luat_log.h"

#define ERR_DUMP_LEN_MAX	(4096)
#define LUAT_ERRDUMP_PORT	(12425)
const char luat_errdump_domain[] = "dev_msg1.openluat.com";
enum
{
	LUAT_ERRDUMP_RECORD_TYPE_SYS,
	LUAT_ERRDUMP_RECORD_TYPE_USR,
	LUAT_ERRDUMP_RECORD_TYPE_NONE,

	LUAT_ERRDUMP_CONNECT = 0,
	LUAT_ERRDUMP_TX,
	LUAT_ERRDUMP_RX,
	LUAT_ERRDUMP_CLOSE,
};

static const char sys_error_log_file_path[] = {'/',0xaa,'s','e','r','r',0};
static const char user_error_log_file_path[] = {'/',0xaa,'u','e','r','r',0};
typedef struct luat_errdump_conf
{
	Buffer_Struct tx_buf;
	network_ctrl_t *netc;
	char *user_string;
	uint32_t upload_period;
	uint32_t sys_error_r_cnt;
	uint32_t sys_error_w_cnt;
	uint32_t user_error_r_cnt;
	uint32_t user_error_w_cnt;
	luat_rtos_timer_t upload_timer;
	luat_rtos_timer_t network_timer;
	uint8_t is_uploading;
	uint8_t error_dump_enable;
	uint8_t upload_poweron_reason_done;
}luat_errdump_conf_t;

static luat_errdump_conf_t econf;

static void luat_errdump_load(const char *path, Buffer_Struct *buffer);
static void luat_errdump_clear(const char *path);
static int32_t l_errdump_callback(lua_State *L, void* ptr);
static LUAT_RT_RET_TYPE luat_errdump_timer_callback(LUAT_RT_CB_PARAM);
static LUAT_RT_RET_TYPE luat_errdump_rx_timer_callback(LUAT_RT_CB_PARAM);
static int luat_errdump_network_callback(void *data, void *param)
{
	OS_EVENT *event = (OS_EVENT *)data;
	int ret = 0;
	rtos_msg_t msg = {0};

	if (event->Param1)
	{
		LLOGE("errdump fail, after %d second retry", econf.upload_period);
		econf.is_uploading = 0;
		msg.handler = l_errdump_callback,
		msg.arg1 = LUAT_ERRDUMP_CLOSE,
		luat_msgbus_put(&msg, 0);
		luat_rtos_timer_start(econf.upload_timer, econf.upload_period * 1000, 0, luat_errdump_timer_callback, NULL);
		OS_DeInitBuffer(&econf.tx_buf);
		return 0;
	}
	switch(event->ID)
	{
	case EV_NW_RESULT_CONNECT:
		msg.handler = l_errdump_callback,
		msg.arg1 = LUAT_ERRDUMP_TX,
		luat_msgbus_put(&msg, 0);
		break;
	case EV_NW_RESULT_EVENT:
		msg.handler = l_errdump_callback,
		msg.arg1 = LUAT_ERRDUMP_RX,
		luat_msgbus_put(&msg, 0);
		network_wait_event(econf.netc, NULL, 0, 0);
		break;
	case EV_NW_RESULT_CLOSE:
		break;
	}
	return 0;
}

static void luat_errdump_make_data(lua_State *L)
{
	const char *project = "unkonw";
	const char *version = "";
	char imei[16] = {0};
	char *sn = version;
	FILE* fd;
	size_t len;
	luat_mobile_get_imei(0, imei, 15);
    lua_getglobal(L, "PROJECT");
    size_t version_len, project_len;
    if (LUA_TSTRING == lua_type(L, -1))
    {
    	project = luaL_tolstring(L, -1, &project_len);
    }
    lua_getglobal(L, "VERSION");
    if (LUA_TSTRING == lua_type(L, -1))
    {
    	version = luaL_tolstring(L, -1, &version_len);
    }
    int32_t file_len[LUAT_ERRDUMP_RECORD_TYPE_NONE];
    econf.sys_error_r_cnt = econf.sys_error_w_cnt;
    file_len[LUAT_ERRDUMP_RECORD_TYPE_SYS] = luat_fs_fsize(sys_error_log_file_path);
    econf.user_error_r_cnt = econf.user_error_w_cnt;
    file_len[LUAT_ERRDUMP_RECORD_TYPE_USR] = luat_fs_fsize(user_error_log_file_path);
    if (file_len[LUAT_ERRDUMP_RECORD_TYPE_SYS] < 0)
    {
    	file_len[LUAT_ERRDUMP_RECORD_TYPE_SYS] = 0;
    }
    if (file_len[LUAT_ERRDUMP_RECORD_TYPE_USR] < 0)
    {
    	file_len[LUAT_ERRDUMP_RECORD_TYPE_USR] = 0;
    }
    if (econf.user_string)
    {
    	sn = econf.user_string;
    }
    OS_ReInitBuffer(&econf.tx_buf, file_len[LUAT_ERRDUMP_RECORD_TYPE_USR] + file_len[LUAT_ERRDUMP_RECORD_TYPE_SYS] + 128);
    econf.tx_buf.Pos = sprintf_(econf.tx_buf.Data, "%s_LuatOS-SoC_%s_%s,%s,%s,%s,\r\n", project, luat_version_str(), luat_os_bsp(), version, imei, sn);
    if (!econf.upload_poweron_reason_done)
    {
    	econf.tx_buf.Pos += sprintf_(econf.tx_buf.Data + econf.tx_buf.Pos, "poweron reason:%d\r\n", luat_pm_get_poweron_reason());
    }
    if (file_len[LUAT_ERRDUMP_RECORD_TYPE_SYS] > 0)
    {
    	fd = luat_fs_fopen(sys_error_log_file_path, "r");
    	len = luat_fs_fread(econf.tx_buf.Data + econf.tx_buf.Pos, file_len[LUAT_ERRDUMP_RECORD_TYPE_SYS], 1, fd);
    	if (len > 0)
    	{
    		econf.tx_buf.Pos += len;
    		econf.tx_buf.Data[econf.tx_buf.Pos] = '\r';
    		econf.tx_buf.Data[econf.tx_buf.Pos + 1] = '\n';
    		econf.tx_buf.Pos += 2;
    	}
    	luat_fs_fclose(fd);
    }
    if (file_len[LUAT_ERRDUMP_RECORD_TYPE_USR] > 0)
    {
    	fd = luat_fs_fopen(user_error_log_file_path, "r");
    	len = luat_fs_fread(econf.tx_buf.Data + econf.tx_buf.Pos, file_len[LUAT_ERRDUMP_RECORD_TYPE_USR], 1, fd);
    	if (len > 0)
    	{
    		econf.tx_buf.Pos += len;
    		econf.tx_buf.Data[econf.tx_buf.Pos] = '\r';
    		econf.tx_buf.Data[econf.tx_buf.Pos + 1] = '\n';
    		econf.tx_buf.Pos += 2;
    	}
    	luat_fs_fclose(fd);
    }
}

static int32_t l_errdump_callback(lua_State *L, void* ptr)
{
	uint8_t response[16];
	luat_ip_addr_t remote_ip;
	uint16_t remote_port;
	uint32_t dummy_len;
    rtos_msg_t* msg = (rtos_msg_t*)lua_topointer(L, -1);
    const char *ok_result = "{\"r\": 1}";
    switch(msg->arg1)
    {
    case LUAT_ERRDUMP_CONNECT:
    	econf.netc = network_alloc_ctrl(network_get_last_register_adapter());
    	if (!econf.netc)
    	{
    		LLOGE("no socket, errdump fail, after %d second retry", econf.upload_period);
    		econf.is_uploading = 0;
    		luat_rtos_timer_start(econf.upload_timer, econf.upload_period * 1000, 0, luat_errdump_timer_callback, NULL);
    		OS_DeInitBuffer(&econf.tx_buf);

    	}
    	else
    	{
    		network_init_ctrl(econf.netc, NULL, luat_errdump_network_callback, NULL);
    		network_set_base_mode(econf.netc, 0, 0, 0, 0, 0, 0);
    		luat_rtos_timer_start(econf.network_timer, 30000, 0, luat_errdump_rx_timer_callback, NULL);
    		network_connect(econf.netc, luat_errdump_domain, sizeof(luat_errdump_domain), NULL, LUAT_ERRDUMP_PORT, 0);
    	}
    	break;
    case LUAT_ERRDUMP_TX:
    	if (!econf.tx_buf.Data)
    	{
    		luat_errdump_make_data(L);
    	}
    	else
    	{
    		if (econf.sys_error_r_cnt != econf.sys_error_w_cnt || econf.user_error_r_cnt != econf.user_error_w_cnt)
    		{
    			msg->arg2 = 0;
    			luat_errdump_make_data(L);
    		}
    	}

    	if (network_tx(econf.netc, econf.tx_buf.Data, econf.tx_buf.Pos, 0, NULL, 0, &dummy_len, 0) < 0)
    	{
    		LLOGE("socket tx error, errdump fail, after %d second retry", econf.upload_period);
    		luat_rtos_timer_start(econf.upload_timer, econf.upload_period * 1000, 0, luat_errdump_timer_callback, NULL);
			goto SOCKET_CLOSE;
    	}
    	network_wait_event(econf.netc, NULL, 0, 0);
    	luat_rtos_timer_start(econf.network_timer, 10000, 0, luat_errdump_rx_timer_callback, (void *)(msg->arg2 + 1));
    	break;
    case LUAT_ERRDUMP_RX:

    	if (network_rx(econf.netc, response, 16, 0, &remote_ip, &remote_port, &dummy_len))
    	{
    		LLOGE("socket rx error, errdump fail, after %d second retry", econf.upload_period);
    		luat_rtos_timer_start(econf.upload_timer, econf.upload_period * 1000, 0, luat_errdump_timer_callback, NULL);
			goto SOCKET_CLOSE;
    	}
    	if (8 == dummy_len)
    	{
    		if (memcmp(response, ok_result, 8))
    		{
    			LLOGD("errdump response error %.*s", dummy_len, response);
    			break;
    		}
    	}
    	else if (2 == dummy_len)
    	{
    		if (memcmp(response, "OK", 2))
    		{
    			LLOGD("errdump response error %.*s", dummy_len, response);
    			break;
    		}
    	}
    	else
    	{
    		LLOGD("errdump response maybe new %.*s", dummy_len, response);
    	}
		if (econf.sys_error_r_cnt != econf.sys_error_w_cnt || econf.user_error_r_cnt != econf.user_error_w_cnt)
		{
			LLOGD("errdump need retry!");
			luat_errdump_make_data(L);
			if (network_tx(econf.netc, econf.tx_buf.Data, econf.tx_buf.Pos, 0, NULL, 0, &dummy_len, 0))
			{
				LLOGE("socket tx error, errdump fail, after %d second retry", econf.upload_period);
				luat_rtos_timer_start(econf.upload_timer, econf.upload_period * 1000, 0, luat_errdump_timer_callback, NULL);
				goto SOCKET_CLOSE;
			}
			network_wait_event(econf.netc, NULL, 0, 0);
			luat_rtos_timer_start(econf.network_timer, 10000, 0, luat_errdump_rx_timer_callback, (void *)1);
		}
		else
		{
			LLOGD("errdump ok!");
			luat_errdump_clear(sys_error_log_file_path);
			luat_errdump_clear(user_error_log_file_path);
			econf.upload_poweron_reason_done = 1;
			goto SOCKET_CLOSE;
		}
    	break;
    case LUAT_ERRDUMP_CLOSE:
    	goto SOCKET_CLOSE;
    	break;
    }
    return 0;
SOCKET_CLOSE:
	luat_rtos_timer_stop(econf.network_timer);
	econf.is_uploading = 0;
	if (econf.netc)
	{
		network_close(econf.netc, 0);
		network_release_ctrl(econf.netc);
		OS_DeInitBuffer(&econf.tx_buf);
		econf.netc = NULL;
	}
	return 0;
}

static LUAT_RT_RET_TYPE luat_errdump_rx_timer_callback(LUAT_RT_CB_PARAM)
{
	if (param)
	{
		uint32_t retry = (uint32_t)param;
		if (retry < 3)
		{
			LLOGE("errdump tx fail %d cnt, retry", retry);
			rtos_msg_t msg = {
				.handler = l_errdump_callback,
				.ptr = NULL,
				.arg1 = LUAT_ERRDUMP_TX,
				.arg2 = retry,
			};
			luat_msgbus_put(&msg, 0);
		}
	}
	else
	{
		LLOGE("errdump server connect fail, after %d second retry", econf.upload_period);
		rtos_msg_t msg = {
			.handler = l_errdump_callback,
			.ptr = NULL,
			.arg1 = LUAT_ERRDUMP_CLOSE,
			.arg2 = 0,
		};
		luat_msgbus_put(&msg, 0);
		econf.is_uploading = 0;
		luat_rtos_timer_start(econf.upload_timer, econf.upload_period * 1000, 0, luat_errdump_timer_callback, NULL);
	}
}



static LUAT_RT_RET_TYPE luat_errdump_timer_callback(LUAT_RT_CB_PARAM)
{

	if (!econf.upload_poweron_reason_done || luat_fs_fsize(sys_error_log_file_path) > 0 || luat_fs_fsize(user_error_log_file_path) > 0)
	{
		econf.is_uploading = 1;
		rtos_msg_t msg = {
			.handler = l_errdump_callback,
			.ptr = NULL,
			.arg1 = LUAT_ERRDUMP_CONNECT,
			.arg2 = 0,
		};
		luat_msgbus_put(&msg, 0);
	}
	else
	{
		LLOGD("no info errdump stop");
	}
}

static void luat_errdump_save(const char *path, const uint8_t *data, uint32_t len)
{
	if (!econf.error_dump_enable) return;
	size_t now_len = luat_fs_fsize(path);
	FILE* fd = NULL;
	// 分情况处理
	if (len >= ERR_DUMP_LEN_MAX) {
		// 新数据直接超过了最大长度, 那老数据没意义了
		// 而且新数据必须截断
		data += (len - ERR_DUMP_LEN_MAX);
		len = ERR_DUMP_LEN_MAX;
		fd = luat_fs_fopen(path, "w+"); // 这里会截断
	}
	else if (now_len + len > ERR_DUMP_LEN_MAX) {
		// 新数据小于ERR_DUMP_LEN_MAX, 但新数据+老数据<ERR_DUMP_LEN_MAX
		size_t keep_len = ERR_DUMP_LEN_MAX - len;// 老数据保留措施
		uint8_t *buffer = luat_heap_malloc(keep_len); 
		if (buffer) {
			// 打开原文件,读取现有的数据
			fd = luat_fs_fopen(path, "r");
			if (fd) {
				luat_fs_fseek(fd, now_len - keep_len, SEEK_SET);
				luat_fs_fread(buffer, keep_len, 1, fd);
				luat_fs_fclose(fd);
				// 再次打开文件,进行写入
				fd = luat_fs_fopen(path, "w+");
				if (fd) {
					luat_fs_fwrite(buffer, keep_len, 1, fd);
				} // 老数据读不到就无视吧
			} // 老数据读不到就无视吧
			luat_heap_free(buffer);
		}
	}
	else {
		// 数据直接追加就可以了
		fd = luat_fs_fopen(path, "a+");
	}
	if (fd == NULL) {
		// 最后的尝试
		luat_fs_remove(path);
		fd = luat_fs_fopen(path, "w+"); 
	}

	// 最后的最后, 写入新数据
	if (fd) {
		luat_fs_fwrite(data, len, 1, fd);
		luat_fs_fclose(fd);
	}
	else {
		// TODO 这里要return吗?
	}

	if (!econf.is_uploading  && econf.upload_period)
	{
		luat_rtos_timer_start(econf.upload_timer, 2000, 0, luat_errdump_timer_callback, NULL);
	}

}

static void luat_errdump_clear(const char *path)
{
	if (luat_fs_fexist(path)) luat_fs_remove(path);
}

static void luat_errdump_load(const char *path, Buffer_Struct *buffer)
{
	if (!econf.error_dump_enable) return;
	size_t len = luat_fs_fsize(path);
	if (!len)
	{
		return;
	}
	FILE* fd = luat_fs_fopen(path, "a+");
	if (buffer->MaxLen < len)
	{
		OS_ReInitBuffer(buffer, len);
	}
	len = luat_fs_fread(buffer->Data, len, 1, fd);
	if (len > 0)
	{
		buffer->Pos = len;
	}
	luat_fs_fclose(fd);
}

void luat_errdump_save_file(const uint8_t *data, uint32_t len)
{
	econf.sys_error_w_cnt++;
	luat_errdump_save(sys_error_log_file_path, data, len);
	econf.sys_error_w_cnt++;
}

void luat_errdump_record_init(uint8_t enable, uint32_t upload_period)
{
	econf.error_dump_enable = enable;
	if (econf.error_dump_enable)
	{
		if (upload_period)
		{
			if (!econf.upload_timer)
			{
				luat_rtos_timer_create(&econf.upload_timer);
			}
			if (!econf.network_timer)
			{
				luat_rtos_timer_create(&econf.network_timer);
			}
			econf.upload_period = upload_period;
			luat_rtos_timer_start(econf.upload_timer, 2000, 0, luat_errdump_timer_callback, NULL);
			luat_rtos_timer_stop(econf.network_timer);
		}
		else
		{
			econf.upload_period = 0;
			luat_rtos_timer_delete(econf.upload_timer);
			luat_rtos_timer_delete(econf.network_timer);
		}
	}
	else
	{
		luat_errdump_clear(sys_error_log_file_path);
		luat_errdump_clear(user_error_log_file_path);
		luat_rtos_timer_delete(econf.upload_timer);
		luat_rtos_timer_delete(econf.network_timer);
		if (econf.user_string)
		{
			luat_heap_free(econf.user_string);
			econf.user_string = NULL;
		}
	}
}

/*
手动读取异常日志，主要用于用户将日志发送给自己的服务器而不是IOT平台，如果在errDump.config配置了周期上传，则不能使用本函数
@api    errDump.dump(zbuff, type, isDelete)
@zbuff 日志信息缓存，如果为nil就不会读出，一般当
@int 日志类型，目前只有errDump.TYPE_SYS和errDump.TYPE_USR
@boolean 是否删除日志
@return boolean true表示本次读取前并没有写入数据，false反之，在删除日志前，最好再读一下确保没有新的数据写入了
@usage
local result = errDump.dump(buff, errDump.TYPE_SYS, false) --读出系统记录的异常日志
local result = errDump.dump(nil, errDump.TYPE_SYS, true) --清除系统记录的异常日志
*/
static int l_errdump_dump(lua_State *L) {
	int is_delete = 0;
	if (LUA_TBOOLEAN == lua_type(L, 3))
	{
		is_delete = lua_toboolean(L, 3);
	}
	luat_zbuff_t *buff = NULL;
	if (lua_touserdata(L, 1))
	{
		buff = tozbuff(L);
	}
	int result = 0;
	const char *path = NULL;
	int type = luaL_optinteger(L, 2, LUAT_ERRDUMP_RECORD_TYPE_USR);
	if (type >= LUAT_ERRDUMP_RECORD_TYPE_NONE)
	{
		lua_pushboolean(L, 1);
		return 1;
	}

	switch(type)
	{
	case LUAT_ERRDUMP_RECORD_TYPE_SYS:
		result = (econf.sys_error_r_cnt != econf.sys_error_w_cnt);
		path = sys_error_log_file_path;
		break;
	case LUAT_ERRDUMP_RECORD_TYPE_USR:
		result = (econf.user_error_r_cnt != econf.user_error_w_cnt);
		path = user_error_log_file_path;
		break;
	}
	if (buff)
	{
		Buffer_Struct buffer;
		buffer.Data = buff->addr;
		buffer.MaxLen = buff->len;
		buffer.Pos = 0;
		switch(type)
		{
		case LUAT_ERRDUMP_RECORD_TYPE_SYS:
			econf.sys_error_r_cnt = econf.sys_error_w_cnt;
			break;
		case LUAT_ERRDUMP_RECORD_TYPE_USR:
			econf.user_error_r_cnt = econf.user_error_w_cnt;
			break;
		}
		luat_errdump_load(path, &buffer);
		buff->addr = buffer.Data;
		buff->len = buffer.MaxLen;
		buff->used = buffer.Pos;
	}
	lua_pushboolean(L, result);
	if (is_delete)
	{
		luat_errdump_clear(path);
	}
	return 1;
}

/*
写入用户的异常日志，注意最大只有4KB，超过部分新的覆盖旧的，开启自动上传后会上传到合宙IOT平台
@api    errDump.record(string)
@string  日志
@return nil 无返回值
@usage
errDump.record("socket long time no connect") --记录下"socket long time no connect"
*/
static int l_errdump_record(lua_State *L) {
	if (LUA_TSTRING == lua_type(L, 1))
	{
		size_t len = 0;
		const char *str = luaL_tolstring(L, 1, &len);
		if (len)
		{
			econf.user_error_w_cnt++;
			luat_errdump_save(user_error_log_file_path, str, len);
			econf.user_error_w_cnt++;
		}
	}
	return 0;
}

/*
配置关键日志上传IOT平台，这里的日志包括引起luavm异常退出的日志和用户通过record写入的日志，类似于air的errDump
@api    errDump.config(enable, period, user_flag)
@boolean  是否启用记录功能，false的话将不会记录任何日志
@int     定时上传周期，单位秒，默认600秒，这个是自动上传时候后的重试时间时间，在开机后或者有record操作后会很快尝试上传到合宙IOT平台一次，如果为0，则不会上传，由用户dump后自己上传自己的平台
@string 用户的特殊标识，可以为空
@return nil 无返回值
@usage
errDump.config(true, 3600, "12345678")	--一个小时尝试上次一次，上传时会在imei后附加上12345678
errDump.config(false)	--关闭记录功能，不再上传
errDump.config(true, 0)	--记录，但是不会主动上传，由用户实现上传功能
*/
static int l_errdump_upload_config(lua_State *L) {
	if (LUA_TBOOLEAN == lua_type(L, 1))
	{
		luat_errdump_record_init(lua_toboolean(L, 1), luaL_optinteger(L, 2, 600));
	}
	if (econf.error_dump_enable)
	{
		if (LUA_TSTRING == lua_type(L, 3))
		{
			size_t len = 0;
			const char *str = luaL_tolstring(L, 3, &len);
			if (econf.user_string)
			{
				luat_heap_free(econf.user_string);
				econf.user_string = NULL;
			}
			econf.user_string = luat_heap_malloc(len + 1);
			memcpy(econf.user_string, str, len + 1);
		}
	}
	return 0;
}

#include "rotable2.h"
static const rotable_Reg_t reg_errdump[] =
{
	{ "dump",		    ROREG_FUNC(l_errdump_dump)},
	{ "record", 	    ROREG_FUNC(l_errdump_record)},
	{ "config", 	ROREG_FUNC(l_errdump_upload_config)},
	{ "TYPE_SYS",       ROREG_INT(LUAT_ERRDUMP_RECORD_TYPE_SYS)},
	{ "TYPE_USR",       ROREG_INT(LUAT_ERRDUMP_RECORD_TYPE_USR)},
	{ NULL,             ROREG_INT(0) }
};

LUAMOD_API int luaopen_errdump( lua_State *L ) {
    luat_newlib2(L, reg_errdump);
    return 1;
}
