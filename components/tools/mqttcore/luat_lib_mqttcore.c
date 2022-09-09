/*
@module  libmqtt
@summary mqtt协议处理,供mqtt.lua使用
@version 1.0
@date    2020.07.03
*/
#include "luat_base.h"
#include "luat_sys.h"
#include "luat_msgbus.h"
#include "luat_pack.h"

#define LUAT_LOG_TAG "mqttcore"
#include "luat_log.h"

enum msgTypes
{
	CONNECT = 1, CONNACK, PUBLISH, PUBACK, PUBREC, PUBREL,
	PUBCOMP, SUBSCRIBE, SUBACK, UNSUBSCRIBE, UNSUBACK,
	PINGREQ, PINGRESP, DISCONNECT, AUTH
};
// static const char *packet_names[] =
// {
// 	"RESERVED", "CONNECT", "CONNACK", "PUBLISH", "PUBACK", "PUBREC", "PUBREL",
// 	"PUBCOMP", "SUBSCRIBE", "SUBACK", "UNSUBSCRIBE", "UNSUBACK",
// 	"PINGREQ", "PINGRESP", "DISCONNECT", "AUTH"
// };

// static const char** MQTTClient_packet_names = packet_names;


/**
 * Converts an MQTT packet code into its name
 * @param ptype packet code
 * @return the corresponding string, or "UNKNOWN"
 */
// static const char* MQTTPacket_name(int ptype)
// {
// 	return (ptype >= 0 && ptype <= AUTH) ? packet_names[ptype] : "UNKNOWN";
// }

/**
 * Encodes the message length according to the MQTT algorithm
 * @param buf the buffer into which the encoded data is written
 * @param length the length to be encoded
 * @return the number of bytes written to buffer
 */
static int MQTTPacket_encode(char* buf, size_t length)
{
	int rc = 0;

	//FUNC_ENTRY;
	do
	{
		char d = length % 128;
		length /= 128;
		/* if there are more digits to encode, set the top bit of this digit */
		if (length > 0)
			d |= 0x80;
		if (buf)
			buf[rc++] = d;
		else
			rc++;
	} while (length > 0);
	//FUNC_EXIT_RC(rc);
	return rc;
}


static int l_mqttcore_encodeLen(lua_State *L) {
    size_t len = 0;
    char buff[4];
    len = luaL_checkinteger(L, 1);
    int rc = MQTTPacket_encode(buff, len);
    lua_pushlstring(L, (const char*)buff, rc);
    return 1;
}

static void _add_mqtt_str(luaL_Buffer *buff, const char* str, size_t len) {
	if (len == 0) return;
	luaL_addchar(buff, len / 256);
	luaL_addchar(buff, len % 256);
	luaL_addlstring(buff, str, len);
}

static int l_mqttcore_encodeUTF8(lua_State *L) {
    if(!lua_isstring(L, 1) || 0 == lua_rawlen(L, 1)) {
		lua_pushlstring(L, "", 0);
		return 1;
	}
	luaL_Buffer buff;
	luaL_buffinit(L, &buff);

	size_t len = 0;
	const char* str = lua_tolstring(L, 1, &len);
	_add_mqtt_str(&buff, str, len);
	luaL_pushresult(&buff);
	
	return 1;
}

static void mqttcore_packXXX(lua_State *L, luaL_Buffer *buff, uint8_t header) {
	luaL_Buffer buff2;
	luaL_buffinitsize(L, &buff2, buff->n + 5);

	// 标识 CONNECT
	luaL_addchar(&buff2, header);
	// 剩余长度
    char buf[4];
    int rc = MQTTPacket_encode(buf, buff->n);
    luaL_addlstring(&buff2, buf, rc);

	luaL_addlstring(&buff2, buff->b, buff->n);

	// 清理掉
	luaL_pushresult(buff);
	lua_pop(L, 1);

	luaL_pushresult(&buff2);
}

static int l_mqttcore_packCONNECT(lua_State *L) {
	luaL_Buffer buff;
	luaL_buffinit(L, &buff);

	// 把参数取一下
	// 1         2          3         4         5             6     7
	// clientId, keepAlive, username, password, cleanSession, will, version
	const char* clientId = luaL_checkstring(L, 1);
	int keepAlive = luaL_optinteger(L, 2, 240);
	const char* username = luaL_optstring(L, 3, "");
	const char* password = luaL_optstring(L, 4, "");
	int cleanSession = luaL_optinteger(L, 5, 1);
	cleanSession = 1; // 暂时强制清除

	// 处理will
	// topic payload  retain  qos flag
	lua_pushstring(L, "topic");
	lua_gettable(L, 6);
	const char* will_topic = luaL_checkstring(L, -1);
	lua_pop(L, 1);

	lua_pushstring(L, "payload");
	lua_gettable(L, 6);
	const char* will_payload = luaL_checkstring(L, -1);
	lua_pop(L, 1);

	lua_pushstring(L, "retain");
	lua_gettable(L, 6);
	uint8_t will_retain = luaL_checkinteger(L, -1);
	lua_pop(L, 1);

	lua_pushstring(L, "qos");
	lua_gettable(L, 6);
	uint8_t will_qos = luaL_checkinteger(L, -1);
	lua_pop(L, 1);

	lua_pushstring(L, "flag");
	lua_gettable(L, 6);
	uint8_t will_flag = luaL_checkinteger(L, -1);
	lua_pop(L, 1);

	// ----- 结束处理will


	// 添加固定头 MQTT
	luaL_addlstring(&buff, "\0\4MQTT", 6);

	// 版本号 4
	luaL_addchar(&buff, 4);

	// flags
	uint8_t flags = 0;
	if (strlen(username) > 0) flags += 128;
	if (strlen(password) > 0) flags += 64;
	if (will_retain) flags += 32;
	if (will_qos) flags += will_qos*8;
	if (will_flag) flags += 4;
	if (cleanSession) flags += 2;
	luaL_addchar(&buff, flags);

	// keepalive
	luaL_addchar(&buff, keepAlive / 256);
	luaL_addchar(&buff, keepAlive % 256);

	// client id
	_add_mqtt_str(&buff, clientId, strlen(clientId));

	// will_topic
	_add_mqtt_str(&buff, will_topic, strlen(will_topic));

	// will_topic
	_add_mqtt_str(&buff, will_payload, strlen(will_payload));

	// username and password
	_add_mqtt_str(&buff, username, strlen(username));
	_add_mqtt_str(&buff, password, strlen(password));

	// 然后计算总长度,坑呀

	mqttcore_packXXX(L, &buff, CONNECT * 16);
	return 1;
}

//82 2F0002002A2F613159467559364F4331652F617A4E6849624E4E546473567759326D685A6E6F2F757365722F67657400
//82 2D00    2A2F613159467559364F4331652F617A4E6849624E4E546473567759326D685A6E6F2F757365722F67657400

static int l_mqttcore_packSUBSCRIBE(lua_State *L) {
	// dup, packetId, topics
	uint8_t dup = luaL_checkinteger(L, 1);
	uint16_t packetId = luaL_checkinteger(L, 2);
	if (!lua_istable(L, 3)) {
		LLOGE("args for packSUBSCRIBE must be table");
		return 0;
	}

	luaL_Buffer buff;
	luaL_buffinit(L, &buff);

	// 添加packetId
	luaL_addchar(&buff, packetId >> 8);
	luaL_addchar(&buff, packetId & 0xFF);

	size_t len = 0;
	lua_pushnil(L);
	while (lua_next(L, 3) != 0) {
       	/* 使用 '键' （在索引 -2 处） 和 '值' （在索引 -1 处）*/
	   	if (lua_isstring(L, -2) && lua_isnumber(L, -1)) {

    		const char* topic = luaL_checklstring(L, -2, &len);
	   		uint8_t qos = luaL_checkinteger(L, -1);
	   		luaL_addchar(&buff, len >> 8);
	   		luaL_addchar(&buff, len & 0xFF);
	   		luaL_addlstring(&buff, topic, len);

	   		luaL_addchar(&buff, qos);
	   }

	   lua_pop(L, 1);
    }
	lua_pop(L, 1);

	mqttcore_packXXX(L, &buff, SUBSCRIBE * 16 + dup * 8 + 2);

	return 1;
}

static int l_mqttcore_packUNSUBSCRIBE(lua_State *L) {
	// dup, packetId, topics
	uint8_t dup = luaL_checkinteger(L, 1);
	uint16_t packetId = luaL_checkinteger(L, 2);
	if (!lua_istable(L, 3)) {
		LLOGE("args for l_mqttcore_packUNSUBSCRIBE must be table");
		return 0;
	}

	luaL_Buffer buff;
	luaL_buffinit(L, &buff);

	// 添加packetId
	luaL_addchar(&buff, packetId >> 8);
	luaL_addchar(&buff, packetId & 0xFF);

	size_t len = 0;
	lua_pushnil(L);
	while (lua_next(L, 3) != 0) {
       /* 使用 '键' （在索引 -2 处） 和 '值' （在索引 -1 处）*/
       const char* topic = luaL_checklstring(L, -1, &len);
	   luaL_addchar(&buff, len >> 8);
	   luaL_addchar(&buff, len & 0xFF);
	   luaL_addlstring(&buff, topic, len);
	   lua_pop(L, 1);
    }
	lua_pop(L, 1);

	mqttcore_packXXX(L, &buff, UNSUBSCRIBE * 16 + dup * 8 + 2);

	return 1;
}

/*
local function packPUBLISH(dup, qos, retain, packetId, topic, payload)
    local header = PUBLISH * 16 + dup * 8 + qos * 2 + retain
    local len = 2 + #topic + #payload
    if qos > 0 then
        return pack.pack(">bAPHA", header, encodeLen(len + 2), topic, packetId, payload)
    else
        return pack.pack(">bAPA", header, encodeLen(len), topic, payload)
    end
end
*/
// 32 4D00 2D 2F 61 3159467559364F4331652F617A4E6849624E4E546473567759326D685A6E6F2F757365722F757064617465 0003     74657374207075626C69736820383636383138303339393231383534
// 32 4D00 2D 2F 61 3159467559364F4331652F617A4E6849624E4E546473567759326D685A6E6F2F757365722F757064617465 0001001C 74657374207075626C69736820383636383138303339393231383534	
static int l_mqttcore_packPUBLISH(lua_State *L) {
	luaL_Buffer buff;
	luaL_buffinit(L, &buff);

	size_t topic_len = 0;
	size_t payload_len = 0;

	uint8_t dup = luaL_checkinteger(L, 1);
	uint8_t qos = luaL_checkinteger(L, 2);
	uint8_t retain = luaL_checkinteger(L, 3);
	//uint16_t packetId = luaL_checkinteger(L, 4);
	const char* topic = luaL_checklstring(L, 5, &topic_len);
	const char* payload = luaL_checklstring(L, 6, &payload_len);

	size_t total_len = 2 + topic_len + payload_len;

	// 添加头部
	uint8_t header = PUBLISH * 16 + dup * 8 + qos * 2 + retain;

	luaL_addchar(&buff, header);
	// 添加可变长度
	char buf[4];
	int rc = 0;
	if (qos > 0) {
    	rc = MQTTPacket_encode(buf, total_len + 2);
	}
	else {
		rc = MQTTPacket_encode(buf, total_len);
	}
    luaL_addlstring(&buff, buf, rc);

	// 添加topic
	luaL_addchar(&buff, topic_len >> 8);
	luaL_addchar(&buff, topic_len & 0xFF);
	luaL_addlstring(&buff, topic, topic_len);
	
	if (qos > 0) {
		luaL_addchar(&buff, qos >> 8);
		luaL_addchar(&buff, qos & 0xFF);
	}

	// 添加payload, 这里是 >A 不是 >P
	//luaL_addchar(&buff, payload_len >> 8);
	//luaL_addchar(&buff, payload_len & 0xFF);
	luaL_addlstring(&buff, payload, payload_len);

	luaL_pushresult(&buff);
	return 1;
}


static int l_mqttcore_packACK(lua_State *L) {
	// Id == ACK or PUBREL
	uint8_t id = luaL_checkinteger(L, 1);
	uint8_t dup = luaL_checkinteger(L, 2);
	uint16_t packetId = luaL_checkinteger(L, 3);

	char buff[4];
	buff[0] = id * 16 + dup * 8 + (id == PUBREL ? 1 : 0) * 2;
	buff[1] = 0x02;
	buff[2] = packetId >> 8;
	buff[3] = packetId & 0xFF;

	lua_pushlstring(L, (const char*) buff, 4);

	return 1;
}

/*
local function packZeroData(id, dup, qos, retain)
    dup = dup or 0
    qos = qos or 0
    retain = retain or 0
    return pack.pack(">bb", id * 16 + dup * 8 + qos * 2 + retain, 0)
end
*/
static int l_mqttcore_packZeroData(lua_State *L) {
	// Id == ACK or PUBREL
	uint8_t id = luaL_checkinteger(L, 1);
	uint8_t dup = luaL_optinteger(L, 2, 0);
	uint8_t qos = luaL_optinteger(L, 3, 0);
	uint8_t retain = luaL_optinteger(L, 4, 0);

	char buff[2];
	buff[0] = id * 16 + dup * 8 + qos * 2 + retain;
	buff[1] = 0;

	lua_pushlstring(L, (const char*) buff, 2);

	return 1;
}

static size_t _mqtt_unpack_P(lua_State *L, char* ptr) {
	size_t len = (0xFF & ptr[0]) * 256 + (0xFF & ptr[1]);
	//LLOGD("_mqtt_unpack_P %02X %02X len %d", (0xFF & ptr[0]), (0xFF & ptr[1]), len);
	lua_pushlstring(L, ptr+2, len);
	return len;
}

static int l_mqttcore_unpack(lua_State *L) {
	size_t slen = 0;
	size_t nextpos = 0;
	uint32_t packetId = 0;

	char* data = (char*)luaL_checklstring(L, 1, &slen);
	if (slen < 2) {
		return 0;
	}
	//LLOGD("unpack first 2 byte %02X %02X", data[0] & 0xFF, data[1] & 0xFF);
	// 首先, 获取package的长度
	size_t dlen = 0;
	size_t poffset = 1;
	size_t multiplier = 1;
	for (; poffset < 4; poffset++)
	{
		if (slen <= poffset) {
			//LLOGD("unpack, slen=%d poffset=%d, execpt more data", slen, poffset);
			return 0;
		}
		dlen += (data[poffset] & 0x7F) * multiplier;
		multiplier *= 128;
		//LLOGD("unpack dlen current %d", dlen);
		if((data[poffset] & 0x80) == 0) {
			break;
		}
	}
	//LLOGD("unpack, poffset %d dlen %d act %d", poffset, dlen, slen);
	if (poffset + dlen > slen) {
		//LLOGD("unpack, wait more data");
		return 0;
	}
	

	// 然后解析第0个字节,header的数据
	uint8_t header = data[0] & 0xFF;
	// local packet = {id = (header - (header % 16)) >> 4, 
	//                 dup = ((header % 16) - ((header % 16) % 8)) >> 3, 
	//                 qos = (header & 0x06) >> 1, 
	//                 retain = (header & 0x01)}
	int id = (header - (header % 16)) >> 4;
	int dup = ((header % 16) - ((header % 16) % 8)) >> 3;
	int qos = (header & 0x06) >> 1;
	int retain = (header & 0x01);

	//LLOGD("unpack id %d dup %d qos %d retain %d", id, dup, qos, retain);

	lua_createtable(L, 0, 7);

	lua_pushliteral(L, "id");
	lua_pushinteger(L, id);
	lua_settable(L, -3);

	lua_pushliteral(L, "dup");
	lua_pushinteger(L, dup);
	lua_settable(L, -3);
	
	lua_pushliteral(L, "qos");
	lua_pushinteger(L, qos);
	lua_settable(L, -3);
	
	lua_pushliteral(L, "retain");
	lua_pushinteger(L, retain);
	lua_settable(L, -3);

	nextpos = poffset+1;

	switch(id) {
	case CONNACK:
			lua_pushliteral(L, "ackFlag");
			lua_pushinteger(L, 0xFF & data[nextpos++]);
			lua_settable(L, -3);

			lua_pushliteral(L, "rc");
			lua_pushinteger(L, 0xFF & data[nextpos++]);
			lua_settable(L, -3);
			break;
	case PUBLISH:
			lua_pushliteral(L, "topic");
			nextpos += _mqtt_unpack_P(L, data + nextpos) + 2;
			//LLOGD("nextpos %d after topic", nextpos);
			lua_settable(L, -3);
			if (qos > 0) {
				lua_pushliteral(L, "packetId");
				packetId = 0xFF & data[nextpos++];
				packetId = packetId * 256;
				packetId = packetId + (0xFF & data[nextpos++]);
				lua_pushinteger(L, packetId);
				lua_settable(L, -3);
				//LLOGD("nextpos %d after packetId", nextpos);
			}
			//LLOGD("nextpos %d before payload", nextpos);
			lua_pushliteral(L, "payload");
			//LLOGD("payload strlen=%d dlen %d poffset %d nextpos %d", dlen+poffset+1 - nextpos, dlen, poffset, nextpos);
			lua_pushlstring(L, data+nextpos, dlen+poffset+1 - nextpos);
			lua_settable(L, -3);
			break;
	case PINGRESP:
			if (dlen) {
				lua_pushliteral(L, "packetId");
				packetId = 0xFF & data[nextpos++];
				packetId = packetId * 256;
				packetId = packetId + (0xFF & data[nextpos++]);
				lua_pushinteger(L, packetId);
				lua_settable(L, -3);
			}
			break;
	}

	lua_pushinteger(L, poffset+dlen+2);// Lua的索引从1开始,所以需要额外加1
	return 2;
}

#include "rotable2.h"
static const rotable_Reg_t reg_mqttcore[] =
{
    { "encodeLen", 		ROREG_FUNC(l_mqttcore_encodeLen)},
    { "encodeUTF8",		ROREG_FUNC(l_mqttcore_encodeUTF8)},
	{ "packCONNECT", 	ROREG_FUNC(l_mqttcore_packCONNECT)},
	{ "packSUBSCRIBE", 	ROREG_FUNC(l_mqttcore_packSUBSCRIBE)},
	{ "packPUBLISH",	ROREG_FUNC(l_mqttcore_packPUBLISH)},
	{ "packACK",		ROREG_FUNC(l_mqttcore_packACK)},
	{ "packZeroData",   ROREG_FUNC(l_mqttcore_packZeroData)},
	{ "packUNSUBSCRIBE",ROREG_FUNC(l_mqttcore_packUNSUBSCRIBE)},
	{ "unpack",  		ROREG_FUNC(l_mqttcore_unpack)},
	{ NULL,             ROREG_INT(0) }
};

LUAMOD_API int luaopen_mqttcore( lua_State *L ) {
    luat_newlib2(L, reg_mqttcore);
    return 1;
}
