/*
@module  libmqtt
@summary mqtt协议处理
@version 1.0
@date    2020.07.03
*/
#include "luat_base.h"
#include "luat_sys.h"
#include "luat_msgbus.h"
#include "luat_pack.h"

#define LUAT_LOG_TAG "luat.mqttcore"
#include "luat_log.h"

enum msgTypes
{
	CONNECT = 1, CONNACK, PUBLISH, PUBACK, PUBREC, PUBREL,
	PUBCOMP, SUBSCRIBE, SUBACK, UNSUBSCRIBE, UNSUBACK,
	PINGREQ, PINGRESP, DISCONNECT, AUTH
};
static const char *packet_names[] =
{
	"RESERVED", "CONNECT", "CONNACK", "PUBLISH", "PUBACK", "PUBREC", "PUBREL",
	"PUBCOMP", "SUBSCRIBE", "SUBACK", "UNSUBSCRIBE", "UNSUBACK",
	"PINGREQ", "PINGRESP", "DISCONNECT", "AUTH"
};

const char** MQTTClient_packet_names = packet_names;


/**
 * Converts an MQTT packet code into its name
 * @param ptype packet code
 * @return the corresponding string, or "UNKNOWN"
 */
const char* MQTTPacket_name(int ptype)
{
	return (ptype >= 0 && ptype <= AUTH) ? packet_names[ptype] : "UNKNOWN";
}

/**
 * Array of functions to build packets, indexed according to packet code
 */
// pf new_packets[] =
// {
// 	NULL,	/**< reserved */
// 	NULL,	/**< MQTTPacket_connect*/
// 	MQTTPacket_connack, /**< CONNACK */
// 	MQTTPacket_publish,	/**< PUBLISH */
// 	MQTTPacket_ack, /**< PUBACK */
// 	MQTTPacket_ack, /**< PUBREC */
// 	MQTTPacket_ack, /**< PUBREL */
// 	MQTTPacket_ack, /**< PUBCOMP */
// 	NULL, /**< MQTTPacket_subscribe*/
// 	MQTTPacket_suback, /**< SUBACK */
// 	NULL, /**< MQTTPacket_unsubscribe*/
// 	MQTTPacket_unsuback, /**< UNSUBACK */
// 	MQTTPacket_header_only, /**< PINGREQ */
// 	MQTTPacket_header_only, /**< PINGRESP */
// 	MQTTPacket_ack,  /**< DISCONNECT */
// 	MQTTPacket_ack   /**< AUTH */
// };

/**
 * Encodes the message length according to the MQTT algorithm
 * @param buf the buffer into which the encoded data is written
 * @param length the length to be encoded
 * @return the number of bytes written to buffer
 */
int MQTTPacket_encode(char* buf, size_t length)
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

// /**
//  * Calculates an integer from two bytes read from the input buffer
//  * @param pptr pointer to the input buffer - incremented by the number of bytes used & returned
//  * @return the integer value calculated
//  */
// int readInt(char** pptr)
// {
// 	char* ptr = *pptr;
// 	int len = 256*((unsigned char)(*ptr)) + (unsigned char)(*(ptr+1));
// 	*pptr += 2;
// 	return len;
// }

// /**
//  * Reads a "UTF" string from the input buffer.  UTF as in the MQTT v3 spec which really means
//  * a length delimited string.  So it reads the two byte length then the data according to
//  * that length.  The end of the buffer is provided too, so we can prevent buffer overruns caused
//  * by an incorrect length.
//  * @param pptr pointer to the input buffer - incremented by the number of bytes used & returned
//  * @param enddata pointer to the end of the buffer not to be read beyond
//  * @param len returns the calculcated value of the length bytes read
//  * @return an allocated C string holding the characters read, or NULL if the length read would
//  * have caused an overrun.
//  *
//  */
// static char* readUTFlen(char** pptr, char* enddata, int* len)
// {
// 	char* string = NULL;

// 	//FUNC_ENTRY;
// 	if (enddata - (*pptr) > 1) /* enough length to read the integer? */
// 	{
// 		*len = readInt(pptr);
// 		if (&(*pptr)[*len] <= enddata)
// 		{
// 			if ((string = malloc(*len+1)) == NULL)
// 				goto exit;
// 			memcpy(string, *pptr, *len);
// 			string[*len] = '\0';
// 			*pptr += *len;
// 		}
// 	}
// exit:
// 	//FUNC_EXIT;
// 	return string;
// }

// /**
//  * Reads a "UTF" string from the input buffer.  UTF as in the MQTT v3 spec which really means
//  * a length delimited string.  So it reads the two byte length then the data according to
//  * that length.  The end of the buffer is provided too, so we can prevent buffer overruns caused
//  * by an incorrect length.
//  * @param pptr pointer to the input buffer - incremented by the number of bytes used & returned
//  * @param enddata pointer to the end of the buffer not to be read beyond
//  * @return an allocated C string holding the characters read, or NULL if the length read would
//  * have caused an overrun.
//  */
// char* readUTF(char** pptr, char* enddata)
// {
// 	int len;
// 	return readUTFlen(pptr, enddata, &len);
// }

// /**
//  * Reads one character from the input buffer.
//  * @param pptr pointer to the input buffer - incremented by the number of bytes used & returned
//  * @return the character read
//  */
// unsigned char readChar(char** pptr)
// {
// 	unsigned char c = **pptr;
// 	(*pptr)++;
// 	return c;
// }

// /**
//  * Writes one character to an output buffer.
//  * @param pptr pointer to the output buffer - incremented by the number of bytes used & returned
//  * @param c the character to write
//  */
// void writeChar(char** pptr, char c)
// {
// 	**pptr = c;
// 	(*pptr)++;
// }

// /**
//  * Writes an integer as 2 bytes to an output buffer.
//  * @param pptr pointer to the output buffer - incremented by the number of bytes used & returned
//  * @param anInt the integer to write
//  */
// void writeInt(char** pptr, int anInt)
// {
// 	**pptr = (char)(anInt / 256);
// 	(*pptr)++;
// 	**pptr = (char)(anInt % 256);
// 	(*pptr)++;
// }

// /**
//  * Writes a "UTF" string to an output buffer.  Converts C string to length-delimited.
//  * @param pptr pointer to the output buffer - incremented by the number of bytes used & returned
//  * @param string the C string to write
//  */
// void writeUTF(char** pptr, const char* string)
// {
// 	size_t len = strlen(string);
// 	writeInt(pptr, (int)len);
// 	memcpy(*pptr, string, len);
// 	*pptr += len;
// }

// /**
//  * Writes length delimited data to an output buffer
//  * @param pptr pointer to the output buffer - incremented by the number of bytes used & returned
//  * @param data the data to write
//  * @param datalen the length of the data to write
//  */
// void writeData(char** pptr, const void* data, int datalen)
// {
// 	writeInt(pptr, datalen);
// 	memcpy(*pptr, data, datalen);
// 	*pptr += datalen;
// }

// /**
//  * Function used in the new packets table to create packets which have only a header.
//  * @param MQTTVersion the version of MQTT
//  * @param aHeader the MQTT header byte
//  * @param data the rest of the packet
//  * @param datalen the length of the rest of the packet
//  * @return pointer to the packet structure
//  */
// void* MQTTPacket_header_only(int MQTTVersion, unsigned char aHeader, char* data, size_t datalen)
// {
// 	static unsigned char header = 0;
// 	header = aHeader;
// 	return &header;
// }

// /**
//  * Writes an integer as 4 bytes to an output buffer.
//  * @param pptr pointer to the output buffer - incremented by the number of bytes used & returned
//  * @param anInt the integer to write
//  */
// void writeInt4(char** pptr, int anInt)
// {
//   **pptr = (char)(anInt / 16777216);
//   (*pptr)++;
//   anInt %= 16777216;
//   **pptr = (char)(anInt / 65536);
//   (*pptr)++;
//   anInt %= 65536;
// 	**pptr = (char)(anInt / 256);
// 	(*pptr)++;
// 	**pptr = (char)(anInt % 256);
// 	(*pptr)++;
// }

// /**
//  * Calculates an integer from two bytes read from the input buffer
//  * @param pptr pointer to the input buffer - incremented by the number of bytes used & returned
//  * @return the integer value calculated
//  */
// int readInt4(char** pptr)
// {
// 	unsigned char* ptr = (unsigned char*)*pptr;
// 	int value = 16777216*(*ptr) + 65536*(*(ptr+1)) + 256*(*(ptr+2)) + (*(ptr+3));
// 	*pptr += 4;
// 	return value;
// }

// void writeMQTTLenString(char** pptr, MQTTLenString lenstring)
// {
//   writeInt(pptr, lenstring.len);
//   memcpy(*pptr, lenstring.data, lenstring.len);
//   *pptr += lenstring.len;
// }


// int MQTTLenStringRead(MQTTLenString* lenstring, char** pptr, char* enddata)
// {
// 	int len = 0;

// 	/* the first two bytes are the length of the string */
// 	if (enddata - (*pptr) > 1) /* enough length to read the integer? */
// 	{
// 		lenstring->len = readInt(pptr); /* increments pptr to point past length */
// 		if (&(*pptr)[lenstring->len] <= enddata)
// 		{
// 			lenstring->data = (char*)*pptr;
// 			*pptr += lenstring->len;
// 			len = 2 + lenstring->len;
// 		}
// 	}
// 	return len;
// }

// /*
// if (prop->value.integer4 >= 0 && prop->value.integer4 <= 127)
//   len = 1;
// else if (prop->value.integer4 >= 128 && prop->value.integer4 <= 16383)
//   len = 2;
// else if (prop->value.integer4 >= 16384 && prop->value.integer4 < 2097151)
//   len = 3;
// else if (prop->value.integer4 >= 2097152 && prop->value.integer4 < 268435455)
//   len = 4;
// */
// int MQTTPacket_VBIlen(int rem_len)
// {
// 	int rc = 0;

// 	if (rem_len < 128)
// 		rc = 1;
// 	else if (rem_len < 16384)
// 		rc = 2;
// 	else if (rem_len < 2097152)
// 		rc = 3;
// 	else
// 		rc = 4;
//   return rc;
// }


// /**
//  * Decodes the message length according to the MQTT algorithm
//  * @param getcharfn pointer to function to read the next character from the data source
//  * @param value the decoded length returned
//  * @return the number of bytes read from the socket
//  */
// int MQTTPacket_VBIdecode(int (*getcharfn)(char*, int), unsigned int* value)
// {
// 	char c;
// 	int multiplier = 1;
// 	int len = 0;
// #define MAX_NO_OF_REMAINING_LENGTH_BYTES 4

// 	*value = 0;
// 	do
// 	{
// 		int rc = MQTTPACKET_READ_ERROR;

// 		if (++len > MAX_NO_OF_REMAINING_LENGTH_BYTES)
// 		{
// 			rc = MQTTPACKET_READ_ERROR;	/* bad data */
// 			goto exit;
// 		}
// 		rc = (*getcharfn)(&c, 1);
// 		if (rc != 1)
// 			goto exit;
// 		*value += (c & 127) * multiplier;
// 		multiplier *= 128;
// 	} while ((c & 128) != 0);
// exit:
// 	return len;
// }


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
       const char* topic = luaL_checklstring(L, -2, &len);
	   uint8_t qos = luaL_checkinteger(L, -1);
	   luaL_addchar(&buff, len >> 8);
	   luaL_addchar(&buff, len & 0xFF);
	   luaL_addlstring(&buff, topic, len);

	   luaL_addchar(&buff, qos);

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
	uint16_t packetId = luaL_checkinteger(L, 4);
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

#include "rotable.h"
static const rotable_Reg reg_mqttcore[] =
{
    { "encodeLen", l_mqttcore_encodeLen, 0},
    { "encodeUTF8",l_mqttcore_encodeUTF8,0},
	{ "packCONNECT", l_mqttcore_packCONNECT,0},
	{ "packSUBSCRIBE", l_mqttcore_packSUBSCRIBE, 0},
	{ "packPUBLISH",	l_mqttcore_packPUBLISH,	0},
	{ "packACK",		l_mqttcore_packACK,		0},
	{ "packZeroData",   l_mqttcore_packZeroData,0},
	{ "packUNSUBSCRIBE", l_mqttcore_packUNSUBSCRIBE,0},
	{ NULL, NULL }
};

LUAMOD_API int luaopen_mqttcore( lua_State *L ) {
    rotable_newlib(L, reg_mqttcore);
    return 1;
}
