/*
@module  libmqtt
@summary mqtt协议处理
@version 1.0
@date    2020.07.03
*/
#include "luat_base.h"
#include "luat_log.h"
#include "luat_sys.h"
#include "luat_msgbus.h"
#include "luat_pack.h"

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


static int l_mqttcore_encodeUTF8(lua_State *L) {
    if(!lua_isstring(L, 1) || 0 == lua_rawlen(L, 1)) {
		lua_pushlstring(L, "", 0);
		return 1;
	}
	lua_pushlstring(L, ">P", 2);
	lua_insert(L, 1);
	return luat_pack(L);
}

#include "rotable.h"
static const rotable_Reg reg_mqttcore[] =
{
    { "encodeLen", l_mqttcore_encodeLen, 0},
    { "encodeUTF8",l_mqttcore_encodeUTF8,0},
	{ NULL, NULL }
};

LUAMOD_API int luaopen_mqttcore( lua_State *L ) {
    rotable_newlib(L, reg_mqttcore);
    return 1;
}
