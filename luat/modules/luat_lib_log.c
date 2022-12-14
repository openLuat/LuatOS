
/*
@module  log
@summary 日志库
@version 1.0
@date    2020.03.30
@tag LUAT_CONF_BSP
*/
#include "luat_base.h"
#include "luat_sys.h"
#include "luat_msgbus.h"
#include "luat_zbuff.h"
#include "ldebug.h"
#include "luat_network_adapter.h"
#include "luat_rtos.h"
#include "luat_mobile.h"
#define LUAT_LOG_TAG "log"
#include "luat_log.h"
#define ERR_DUMP_LEN_MAX	(4096)
#define LUAT_ERRDUMP_PORT	(12425)
const char luat_errdump_domain[] = "dev_msg1.openluat.com";
enum
{
	LUAT_LOG_RECORD_TYPE_SYS,
	LUAT_LOG_RECORD_TYPE_USR,
	LUAT_LOG_RECORD_TYPE_NONE,

	LUAT_ERRDUMP_CONNECT = 0,
	LUAT_ERRDUMP_TX,
	LUAT_ERRDUMP_RX,
	LUAT_ERRDUMP_CLOSE,
};

static const char sys_error_log_file_path[] = {'/',0xaa,'s','e','r','r',0};
static const char user_error_log_file_path[] = {'/',0xaa,'u','e','r','r',0};
typedef struct luat_log_conf
{
#ifdef LUAT_USE_ERR_DUMP
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
#endif
    uint8_t style;

}luat_log_conf_t;

#define LOG_STYLE_NORMAL        0
#define LOG_STYLE_DEBUG_INFO    1
#define LOG_STYLE_FULL          2

static luat_log_conf_t lconf = {
    .style=0
};

static int add_debug_info(lua_State *L, uint8_t pos, const char* LEVEL) {
    lua_Debug ar;
    // int arg;
    // int d = 0;
    // // 查找当前stack的深度
    // while (lua_getstack(L, d, &ar) != 0) {
    //     d++;
    // }
    // // 防御一下, 不太可能直接d==0都失败
    // if (d == 0)
    //     return 0;
    // 获取真正的stack位置信息
    if (!lua_getstack(L, 1, &ar))
        return 0;
    // S包含源码, l包含当前行号
    if (0 == lua_getinfo(L, "Sl", &ar))
        return 0;
    // 没有调试信息就跳过了
    if (ar.source == NULL)
        return 0;
    int line = ar.currentline > 64*1024 ? 0 : ar.currentline;
    // 推入文件名和行号, 注意: 源码路径的第一个字符是标识,需要跳过
    if (LEVEL)
        lua_pushfstring(L, "%s/%s:%d", LEVEL, ar.source + 1, line);
    else
        lua_pushfstring(L, "%s:%d", ar.source + 1, line);
    if (lua_gettop(L) > pos)
        lua_insert(L, pos);
    return 1;
}

/*
设置日志级别
@api   log.setLevel(level)
@string  level 日志级别,可用字符串或数值, 字符串为(SILENT,DEBUG,INFO,WARN,ERROR,FATAL), 数值为(0,1,2,3,4,5)
@return nil 无返回值
@usage
-- 设置日志级别为INFO
log.setLevel("INFO")
*/
static int l_log_set_level(lua_State *L) {
    int LOG_LEVEL = 0;
    if (lua_isinteger(L, 1)) {
        LOG_LEVEL = lua_tointeger(L, 1);
    }
    else if (lua_isstring(L, 1)) {
        const char* lv = lua_tostring(L, 1);
        if (strcmp("SILENT", lv) == 0) {
            LOG_LEVEL = LUAT_LOG_CLOSE;
        }
        else if (strcmp("DEBUG", lv) == 0) {
            LOG_LEVEL = LUAT_LOG_DEBUG;
        }
        else if (strcmp("INFO", lv) == 0) {
            LOG_LEVEL = LUAT_LOG_INFO;
        }
        else if (strcmp("WARN", lv) == 0) {
            LOG_LEVEL = LUAT_LOG_WARN;
        }
        else if (strcmp("ERROR", lv) == 0) {
            LOG_LEVEL = LUAT_LOG_ERROR;
        }
    }
    if (LOG_LEVEL == 0) {
        LOG_LEVEL = LUAT_LOG_CLOSE;
    }
    luat_log_set_level(LOG_LEVEL);
    return 0;
}

/*
设置日志风格
@api log.style(val)
@int 日志风格,默认为0, 不传就是获取当前值
@return int 当前的日志风格
@usage
-- 以 log.info("ABC", "DEF", 123) 为例, 假设该代码位于main.lua的12行
-- 默认日志0
-- I/user.ABC DEF 123
-- 调试风格1, 添加额外的调试信息
-- I/main.lua:12 ABC DEF 123
-- 调试风格2, 添加额外的调试信息, 位置有所区别
-- I/user.ABC main.lua:12 DEF 123

log.style(0) -- 默认风格0
log.style(1) -- 调试风格1
log.style(2) -- 调试风格2
 */
static int l_log_style(lua_State *L) {
    if (lua_isinteger(L, 1))
        lconf.style = luaL_checkinteger(L, 1);
    lua_pushinteger(L, lconf.style);
    return 1;
}

/*
获取日志级别
@api   log.getLevel()
@return  int   日志级别对应0,1,2,3,4,5
@usage
-- 得到日志级别
log.getLevel()
*/
int l_log_get_level(lua_State *L) {
    lua_pushinteger(L, luat_log_get_level());
    return 1;
}

static int l_log_2_log(lua_State *L, const char* LEVEL) {
    // 是不是什么都不传呀?
    int argc = lua_gettop(L);
    if (argc < 1) {
        // 最起码传1个参数
        return 0;
    }
    if (lconf.style == LOG_STYLE_NORMAL) {
        lua_pushfstring(L, "%s/user.%s", LEVEL, lua_tostring(L, 1));
        lua_remove(L, 1); // remove tag
        lua_insert(L, 1);
    }
    else if (lconf.style == LOG_STYLE_DEBUG_INFO) {
        add_debug_info(L, 1, LEVEL);
    }
    else if (lconf.style == LOG_STYLE_FULL) {
        lua_pushfstring(L, "%s/user.%s", LEVEL, lua_tostring(L, 1));
        lua_remove(L, 1); // remove tag
        lua_insert(L, 1);
        add_debug_info(L, 2, NULL);
    }
    lua_getglobal(L, "print");
    lua_insert(L, 1);
    lua_call(L, lua_gettop(L) - 1, 0);
    return 0;
}

/*
输出日志,级别debug
@api    log.debug(tag, val, val2, val3, ...)
@string  tag         日志标识,必须是字符串
@...         需打印的参数
@return nil 无返回值
@usage
-- 日志输出 D/onenet connect ok
log.debug("onenet", "connect ok")
*/
static int l_log_debug(lua_State *L) {
    if (luat_log_get_level() > LUAT_LOG_DEBUG) return 0;
    return l_log_2_log(L, "D");
}

/*
输出日志,级别info
@api    log.info(tag, val, val2, val3, ...)
@string  tag         日志标识,必须是字符串
@...         需打印的参数
@return nil 无返回值
@usage
-- 日志输出 I/onenet connect ok
log.info("onenet", "connect ok")
*/
static int l_log_info(lua_State *L) {
    if (luat_log_get_level() > LUAT_LOG_INFO) return 0;
    return l_log_2_log(L, "I");
}

/*
输出日志,级别warn
@api    log.warn(tag, val, val2, val3, ...)
@string  tag         日志标识,必须是字符串
@...         需打印的参数
@return nil 无返回值
@usage
-- 日志输出 W/onenet connect ok
log.warn("onenet", "connect ok")
*/
static int l_log_warn(lua_State *L) {
    if (luat_log_get_level() > LUAT_LOG_WARN) return 0;
    return l_log_2_log(L, "W");
}

/*
输出日志,级别error
@api    log.error(tag, val, val2, val3, ...)
@string  tag         日志标识,必须是字符串
@...         需打印的参数
@return nil 无返回值
@usage
-- 日志输出 E/onenet connect ok
log.error("onenet", "connect ok")
*/
static int l_log_error(lua_State *L) {
    if (luat_log_get_level() > LUAT_LOG_ERROR) return 0;
    return l_log_2_log(L, "E");
}

#ifdef LUAT_USE_ERR_DUMP
static void luat_log_load(const char *path, Buffer_Struct *buffer);
static void luat_log_clear(const char *path);
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
		LLOGE("errdump fail, after %d second retry", lconf.upload_period);
		lconf.is_uploading = 0;
		msg.handler = l_errdump_callback,
		msg.arg1 = LUAT_ERRDUMP_CLOSE,
		luat_msgbus_put(&msg, 0);
		luat_rtos_timer_start(lconf.upload_timer, lconf.upload_period * 1000, 0, luat_errdump_timer_callback, NULL);
		OS_DeInitBuffer(&lconf.tx_buf);
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
		network_wait_event(lconf.netc, NULL, 0, 0);
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
    int32_t file_len[LUAT_LOG_RECORD_TYPE_NONE];
    lconf.sys_error_r_cnt = lconf.sys_error_w_cnt;
    file_len[LUAT_LOG_RECORD_TYPE_SYS] = luat_fs_fsize(sys_error_log_file_path);
    lconf.user_error_r_cnt = lconf.user_error_w_cnt;
    file_len[LUAT_LOG_RECORD_TYPE_USR] = luat_fs_fsize(user_error_log_file_path);
    if (file_len[LUAT_LOG_RECORD_TYPE_SYS] < 0)
    {
    	file_len[LUAT_LOG_RECORD_TYPE_SYS] = 0;
    }
    if (file_len[LUAT_LOG_RECORD_TYPE_USR] < 0)
    {
    	file_len[LUAT_LOG_RECORD_TYPE_USR] = 0;
    }
    if (lconf.user_string)
    {
    	sn = lconf.user_string;
    }
    OS_ReInitBuffer(&lconf.tx_buf, file_len[LUAT_LOG_RECORD_TYPE_USR] + file_len[LUAT_LOG_RECORD_TYPE_SYS] + 128);
    lconf.tx_buf.Pos = sprintf_(lconf.tx_buf.Data, "%s_LuatOS-SoC_%s_%s,%s,%s,%s,\r\n", project, luat_version_str(), luat_os_bsp(), version, imei, sn);
    if (!lconf.upload_poweron_reason_done)
    {
    	lconf.tx_buf.Pos += sprintf_(lconf.tx_buf.Data + lconf.tx_buf.Pos, "poweron reason:%d\r\n", luat_pm_get_poweron_reason());
    }
    if (file_len[LUAT_LOG_RECORD_TYPE_SYS] > 0)
    {
    	fd = luat_fs_fopen(sys_error_log_file_path, "r");
    	len = luat_fs_fread(lconf.tx_buf.Data + lconf.tx_buf.Pos, file_len[LUAT_LOG_RECORD_TYPE_SYS], 1, fd);
    	if (len > 0)
    	{
    		lconf.tx_buf.Pos += len;
    		lconf.tx_buf.Data[lconf.tx_buf.Pos] = '\r';
    		lconf.tx_buf.Data[lconf.tx_buf.Pos + 1] = '\n';
    		lconf.tx_buf.Pos += 2;
    	}
    	luat_fs_fclose(fd);
    }
    if (file_len[LUAT_LOG_RECORD_TYPE_USR] > 0)
    {
    	fd = luat_fs_fopen(user_error_log_file_path, "r");
    	len = luat_fs_fread(lconf.tx_buf.Data + lconf.tx_buf.Pos, file_len[LUAT_LOG_RECORD_TYPE_USR], 1, fd);
    	if (len > 0)
    	{
    		lconf.tx_buf.Pos += len;
    		lconf.tx_buf.Data[lconf.tx_buf.Pos] = '\r';
    		lconf.tx_buf.Data[lconf.tx_buf.Pos + 1] = '\n';
    		lconf.tx_buf.Pos += 2;
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
    	lconf.netc = network_alloc_ctrl(network_get_last_register_adapter());
    	if (!lconf.netc)
    	{
    		LLOGE("no socket, errdump fail, after %d second retry", lconf.upload_period);
    		lconf.is_uploading = 0;
    		luat_rtos_timer_start(lconf.upload_timer, lconf.upload_period * 1000, 0, luat_errdump_timer_callback, NULL);
    		OS_DeInitBuffer(&lconf.tx_buf);

    	}
    	else
    	{
    		network_init_ctrl(lconf.netc, NULL, luat_errdump_network_callback, NULL);
    		network_set_base_mode(lconf.netc, 0, 0, 0, 0, 0, 0);
    		lconf.netc->is_debug = 1;
    		luat_rtos_timer_start(lconf.network_timer, 30000, 0, luat_errdump_rx_timer_callback, NULL);
    		network_connect(lconf.netc, luat_errdump_domain, sizeof(luat_errdump_domain), NULL, LUAT_ERRDUMP_PORT, 0);
    	}
    	break;
    case LUAT_ERRDUMP_TX:
    	if (!lconf.tx_buf.Data)
    	{
    		luat_errdump_make_data(L);
    	}
    	else
    	{
    		if (lconf.sys_error_r_cnt != lconf.sys_error_w_cnt || lconf.user_error_r_cnt != lconf.user_error_w_cnt)
    		{
    			msg->arg2 = 0;
    			luat_errdump_make_data(L);
    		}
    	}

    	if (network_tx(lconf.netc, lconf.tx_buf.Data, lconf.tx_buf.Pos, 0, NULL, 0, &dummy_len, 0) < 0)
    	{
    		LLOGE("socket tx error, errdump fail, after %d second retry", lconf.upload_period);
    		luat_rtos_timer_start(lconf.upload_timer, lconf.upload_period * 1000, 0, luat_errdump_timer_callback, NULL);
			goto SOCKET_CLOSE;
    	}
    	network_wait_event(lconf.netc, NULL, 0, 0);
    	luat_rtos_timer_start(lconf.network_timer, 10000, 0, luat_errdump_rx_timer_callback, (void *)(msg->arg2 + 1));
    	break;
    case LUAT_ERRDUMP_RX:

    	if (network_rx(lconf.netc, response, 16, 0, &remote_ip, &remote_port, &dummy_len))
    	{
    		LLOGE("socket rx error, errdump fail, after %d second retry", lconf.upload_period);
    		luat_rtos_timer_start(lconf.upload_timer, lconf.upload_period * 1000, 0, luat_errdump_timer_callback, NULL);
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
    		LLOGD("errdump response meybe new %.*s", dummy_len, response);
    	}
		if (lconf.sys_error_r_cnt != lconf.sys_error_w_cnt || lconf.user_error_r_cnt != lconf.user_error_w_cnt)
		{
			LLOGD("errdump need retry!");
			luat_errdump_make_data(L);
			if (network_tx(lconf.netc, lconf.tx_buf.Data, lconf.tx_buf.Pos, 0, NULL, 0, &dummy_len, 0))
			{
				LLOGE("socket tx error, errdump fail, after %d second retry", lconf.upload_period);
				luat_rtos_timer_start(lconf.upload_timer, lconf.upload_period * 1000, 0, luat_errdump_timer_callback, NULL);
				goto SOCKET_CLOSE;
			}
			network_wait_event(lconf.netc, NULL, 0, 0);
			luat_rtos_timer_start(lconf.network_timer, 10000, 0, luat_errdump_rx_timer_callback, (void *)1);
		}
		else
		{
			LLOGD("errdump ok!");
			luat_log_clear(sys_error_log_file_path);
			luat_log_clear(user_error_log_file_path);
			lconf.upload_poweron_reason_done = 1;
			goto SOCKET_CLOSE;
		}
    	break;
    case LUAT_ERRDUMP_CLOSE:
    	goto SOCKET_CLOSE;
    	break;
    }
    return 0;
SOCKET_CLOSE:
	luat_rtos_timer_stop(lconf.network_timer);
	lconf.is_uploading = 0;
	network_close(lconf.netc, 0);
	network_release_ctrl(lconf.netc);
	OS_DeInitBuffer(&lconf.tx_buf);
	lconf.netc = NULL;
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
		LLOGE("errdump server connect fail, after %d second retry", lconf.upload_period);
		rtos_msg_t msg = {
			.handler = l_errdump_callback,
			.ptr = NULL,
			.arg1 = LUAT_ERRDUMP_CLOSE,
			.arg2 = 0,
		};
		luat_msgbus_put(&msg, 0);
		lconf.is_uploading = 0;
		luat_rtos_timer_start(lconf.upload_timer, lconf.upload_period * 1000, 0, luat_errdump_timer_callback, NULL);
	}
}



static LUAT_RT_RET_TYPE luat_errdump_timer_callback(LUAT_RT_CB_PARAM)
{

	if (!lconf.upload_poweron_reason_done || luat_fs_fsize(sys_error_log_file_path) > 0 || luat_fs_fsize(user_error_log_file_path) > 0)
	{
		lconf.is_uploading = 1;
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

static void luat_log_save(const char *path, const uint8_t *data, uint32_t len)
{
	if (!lconf.error_dump_enable) return;
	FILE* fd = luat_fs_fopen(path, "a+");
	if (!fd)
	{
		return;
	}
	size_t now_len = luat_fs_fsize(path);
	if ((now_len + len) > ERR_DUMP_LEN_MAX)
	{
		uint8_t *buffer = luat_heap_malloc(now_len + len);
		if (!buffer)
		{
			luat_fs_fclose(fd);
			return;
		}
		luat_fs_fseek(fd, 0, SEEK_SET);
		luat_fs_fread(buffer, now_len, 1, fd);
		memcpy(buffer + now_len, data, len);
		luat_fs_fseek(fd, 0, SEEK_SET);
		luat_fs_fwrite(buffer + (now_len + len) - ERR_DUMP_LEN_MAX, ERR_DUMP_LEN_MAX, 1, fd);
		luat_heap_free(buffer);
	}
	else
	{
		luat_fs_fwrite(data, len, 1, fd);
	}
	luat_fs_fclose(fd);
	if (!lconf.is_uploading)
	{
		luat_rtos_timer_start(lconf.upload_timer, 2000, 0, luat_errdump_timer_callback, NULL);
	}

}

static void luat_log_clear(const char *path)
{
	if (luat_fs_fexist(path)) luat_fs_remove(path);
}

static void luat_log_load(const char *path, Buffer_Struct *buffer)
{
	if (!lconf.error_dump_enable) return;
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



#endif

void luat_log_save_file(const uint8_t *data, uint32_t len)
{
#ifdef LUAT_USE_ERR_DUMP
	lconf.sys_error_w_cnt++;
	luat_log_save(sys_error_log_file_path, data, len);
	lconf.sys_error_w_cnt++;
#endif
}

void luat_log_record_init(uint8_t enable, uint32_t upload_period)
{
#ifdef LUAT_USE_ERR_DUMP
	lconf.error_dump_enable = enable;
	if (lconf.error_dump_enable)
	{
		if (upload_period)
		{
			if (!lconf.upload_timer)
			{
				luat_rtos_timer_create(&lconf.upload_timer);
			}
			if (!lconf.network_timer)
			{
				luat_rtos_timer_create(&lconf.network_timer);
			}
			lconf.upload_period = upload_period;
			luat_rtos_timer_start(lconf.upload_timer, 2000, 0, luat_errdump_timer_callback, NULL);
			luat_rtos_timer_stop(lconf.network_timer);
		}
		else
		{
			lconf.upload_period = 0;
			luat_rtos_timer_delete(lconf.upload_timer);
			luat_rtos_timer_delete(lconf.network_timer);
		}
	}
	else
	{
		luat_log_clear(sys_error_log_file_path);
		luat_log_clear(user_error_log_file_path);
		luat_rtos_timer_delete(lconf.upload_timer);
		luat_rtos_timer_delete(lconf.network_timer);
		if (lconf.user_string)
		{
			luat_heap_free(lconf.user_string);
			lconf.user_string = NULL;
		}
	}
#endif
}

/*
读取异常日志，这里可以读取系统和用户的，主要用于用户发送给自己的服务器，如果配置了周期上传，请不要使用！！！
@api    log.dump(zbuff, type, isDelete)
@zbuff 日志信息缓存，如果为nil就不会读出，一般当
@int 日志类型，目前只有log.TYPE_SYS和log.TYPE_USR
@boolean 是否删除日志
@return boolean true表示本次读取前并没有写入数据，false反之，在删除日志前，最好再读一下确保没有新的数据写入了
@usage
local result = log.dump(buff, log.TYPE_SYS, false) --读出系统记录的异常日志
local result = log.dump(nil, log.TYPE_SYS, true) --清除系统记录的异常日志
*/
static int l_log_dump(lua_State *L) {
#ifdef LUAT_USE_ERR_DUMP
	int is_delete = 0;
	if (LUA_TBOOLEAN == lua_type(L, 3))
	{
		is_delete = lua_toboolean(L, 3);
	}
	luat_zbuff_t *buff = tozbuff(L);
	int result = 0;
	const char *path = NULL;
	int type = luaL_optinteger(L, 2, LUAT_LOG_RECORD_TYPE_USR);
	if (type >= LUAT_LOG_RECORD_TYPE_NONE)
	{
		lua_pushboolean(L, 1);
		return 1;
	}

	switch(type)
	{
	case LUAT_LOG_RECORD_TYPE_SYS:
		result = (lconf.sys_error_r_cnt != lconf.sys_error_w_cnt);
		path = sys_error_log_file_path;
		break;
	case LUAT_LOG_RECORD_TYPE_USR:
		result = (lconf.user_error_r_cnt != lconf.user_error_w_cnt);
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
		case LUAT_LOG_RECORD_TYPE_SYS:
			lconf.sys_error_r_cnt = lconf.sys_error_w_cnt;
			break;
		case LUAT_LOG_RECORD_TYPE_USR:
			lconf.user_error_r_cnt = lconf.user_error_w_cnt;
			break;
		}

		buff->addr = buffer.Data;
		buff->len = buffer.MaxLen;
		buff->used = buffer.Pos;
		luat_log_load(path, &buffer);
	}
	lua_pushboolean(L, result);
	if (is_delete)
	{
		luat_log_clear(path);
	}
#else
	lua_pushboolean(L, 1);
#endif
	return 1;
}

/*
写入用户的异常日志，注意最大只有4KB，超过部分新的覆盖旧的，开启自动上传后会上传到合宙IOT平台
@api    log.record(string)
@string  日志
@return nil 无返回值
@usage
log.record("socket long time no connect") --记录下"socket long time no connect"
*/
static int l_log_record(lua_State *L) {
#ifdef LUAT_USE_ERR_DUMP
	if (LUA_TSTRING == lua_type(L, 1))
	{
		size_t len = 0;
		const char *str = luaL_tolstring(L, 1, &len);
		if (len)
		{
			lconf.user_error_w_cnt++;
			luat_log_save(user_error_log_file_path, str, len);
			lconf.user_error_w_cnt++;
		}
	}
#endif
	return 0;
}

/*
配置关键日志上传IOT平台，这里的日志包括引起luavm异常退出的日志和用户通过record写入的日志，类似于air的errDump
@api    log.uploadConfig(enable, period, user_flag)
@boolean  是否启用记录功能，false的话将不会记录任何日志
@int     定时上传周期，单位秒，默认600秒，这个是自动上传时候后的重试时间时间，在开机后或者有record操作后会很快尝试上传到合宙IOT平台一次，如果为0，则不会上传，由用户dump后自己上传自己的平台
@string 用户的特殊标识，可以为空
@return nil 无返回值
@usage
log.uploadConfig(true, 3600, "12345678")	--一个小时尝试上次一次，上传时会在imei后附加上12345678
log.uploadConfig(false)	--关闭记录功能，不再上传
log.uploadConfig(true, 0)	--记录，但是不会主动上传，由用户实现上传功能
*/
static int l_log_upload_config(lua_State *L) {
#ifdef LUAT_USE_ERR_DUMP
	if (LUA_TBOOLEAN == lua_type(L, 1))
	{
		luat_log_record_init(lua_toboolean(L, 1), luaL_optinteger(L, 2, 600));
	}
	if (lconf.error_dump_enable)
	{
		if (LUA_TSTRING == lua_type(L, 3))
		{
			size_t len = 0;
			const char *str = luaL_tolstring(L, 3, &len);
			if (lconf.user_string)
			{
				luat_heap_free(lconf.user_string);
				lconf.user_string = NULL;
			}
			lconf.user_string = luat_heap_malloc(len + 1);
			memcpy(lconf.user_string, str, len + 1);
		}
	}

#endif
	return 0;
}

#include "rotable2.h"
static const rotable_Reg_t reg_log[] =
{
    { "debug" ,     ROREG_FUNC(l_log_debug)},
    { "info" ,      ROREG_FUNC(l_log_info)},
    { "warn" ,      ROREG_FUNC(l_log_warn)},
    { "error" ,     ROREG_FUNC(l_log_error)},
    { "fatal" ,     ROREG_FUNC(l_log_error)}, // 以error对待
    { "setLevel" ,  ROREG_FUNC(l_log_set_level)},
    { "getLevel" ,  ROREG_FUNC(l_log_get_level)},
    { "style",      ROREG_FUNC(l_log_style)},
	{ "dump",		ROREG_FUNC(l_log_dump)},
	{ "record", 	ROREG_FUNC(l_log_record)},
	{ "uploadConfig", 	ROREG_FUNC(l_log_upload_config)},
    //{ "_log" ,      ROREG_FUNC(l_log_2_log)},


    //@const LOG_SILENT number 无日志模式
    { "LOG_SILENT", ROREG_INT(LUAT_LOG_CLOSE)},
    //@const LOG_DEBUG number debug日志模式
    { "LOG_DEBUG",  ROREG_INT(LUAT_LOG_DEBUG)},
    //@const LOG_INFO number info日志模式
    { "LOG_INFO",   ROREG_INT(LUAT_LOG_INFO)},
    //@const LOG_WARN number warning日志模式
    { "LOG_WARN",   ROREG_INT(LUAT_LOG_WARN)},
    //@const LOG_ERROR number error日志模式
    { "LOG_ERROR",  ROREG_INT(LUAT_LOG_ERROR)},
	{ "TYPE_SYS",  ROREG_INT(LUAT_LOG_RECORD_TYPE_SYS)},
	{ "TYPE_USR",  ROREG_INT(LUAT_LOG_RECORD_TYPE_USR)},
	{ NULL,         ROREG_INT(0) }
};

LUAMOD_API int luaopen_log( lua_State *L ) {
    luat_newlib2(L, reg_log);
    return 1;
}
