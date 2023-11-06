
#ifndef __CRC_H__
#define __CRC_H__

#ifndef uint8_t
#define uint8_t unsigned char
#define uint16_t unsigned short
#define uint32_t unsigned int
#define BOOL unsigned char
#define TRUE 1
#define FALSE 0
#endif

#include "string.h"

//uint16_t calcCRC16(const uint8_t *data, uint32_t length);
uint32_t calcCRC32(const uint8_t* buf, uint32_t len);
uint8_t calcCRC8(const uint8_t *buf, uint32_t len);
uint16_t calcCRC16(const uint8_t *data, const char *cmd, int length, uint16_t poly, uint16_t initial, uint16_t finally, BOOL bInReverse, BOOL bOutReverse);
uint16_t calcCRC16_modbus(const uint8_t *data, uint32_t length, uint16_t crc_init);
#endif
