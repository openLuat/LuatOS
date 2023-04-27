/*
  ______                              _
 / _____)             _              | |
( (____  _____ ____ _| |_ _____  ____| |__
 \____ \| ___ |    (_   _) ___ |/ ___)  _ \
 _____) ) ____| | | || |_| ____( (___| | | |
(______/|_____)_|_|_| \__)_____)\____)_| |_|
    (C)2013 Semtech

Description: SX126x driver specific target board functions implementation

License: Revised BSD License, see LICENSE.TXT file include in the project

Maintainer: Miguel Luis and Gregory Cristian
*/
#ifndef __SX126x_ARCH_H__
#define __SX126x_ARCH_H__

#include "luat_base.h"
#include "luat_gpio.h"
#include "luat_spi.h"
#include "luat_timer.h"
#include "luat_rtos.h"

#define LUAT_LOG_TAG "lora"
#include "luat_log.h"

typedef struct lora_device
{
  uint8_t lora_spi_id;
  uint8_t lora_pin_cs;
  uint8_t lora_pin_rst;
  uint8_t lora_pin_busy;
  uint8_t lora_pin_dio1;
  bool lora_init;
  bool RxContinuous;
  bool ImageCalibrated;
  uint8_t MaxPayloadLength;
  volatile uint32_t FrequencyError;
  RadioOperatingModes_t OperatingMode;    // Holds the internal operating mode of the radio
  RadioPacketTypes_t PacketType;          // Stores the current packet type set in the radio
  PacketStatus_t RadioPktStatus;
  uint8_t RadioRxPayload[255];
  RadioEvents_t RadioEvents;
  SX126x_t SX126x;
  int lora_ref;				// 强制引用自身避免被GC
  int lora_cb;
  luat_spi_device_t* lora_spi_device;
  luat_rtos_timer_t timer;
  void* user_data;
} lora_device_t;

/*!
 * \brief Initializes the radio I/Os pins interface
 */
// void SX126xIoInit( void );

/*!
 * \brief Initializes DIO IRQ handlers
 *
 * \param [IN] irqHandlers Array containing the IRQ callback functions
 */
// void SX126xIoIrqInit( DioIrqHandler dioIrq );

/*!
 * \brief De-initializes the radio I/Os pins interface.
 *
 * \remark Useful when going in MCU low power modes
 */
// void SX126xIoDeInit( void );

/*!
 * \brief HW Reset of the radio
 */
void SX126xReset2( lora_device_t* lora_device );

/*!
 * \brief Blocking loop to wait while the Busy pin in high
 */
void SX126xWaitOnBusy2( lora_device_t* lora_device );

/*!
 * \brief Wakes up the radio
 */
void SX126xWakeup2( lora_device_t* lora_device );

/*!
 * \brief Send a command that write data to the radio
 *
 * \param [in]  opcode        Opcode of the command
 * \param [in]  buffer        Buffer to be send to the radio
 * \param [in]  size          Size of the buffer to send
 */
void SX126xWriteCommand2( lora_device_t* lora_device,RadioCommands_t opcode, uint8_t *buffer, uint16_t size );

/*!
 * \brief Send a command that read data from the radio
 *
 * \param [in]  opcode        Opcode of the command
 * \param [out] buffer        Buffer holding data from the radio
 * \param [in]  size          Size of the buffer
 */
void SX126xReadCommand2( lora_device_t* lora_device,RadioCommands_t opcode, uint8_t *buffer, uint16_t size );

/*!
 * \brief Write a single byte of data to the radio memory
 *
 * \param [in]  address       The address of the first byte to write in the radio
 * \param [in]  value         The data to be written in radio's memory
 */
void SX126xWriteRegister2( lora_device_t* lora_device,uint16_t address, uint8_t value );

/*!
 * \brief Read a single byte of data from the radio memory
 *
 * \param [in]  address       The address of the first byte to write in the radio
 *
 * \retval      value         The value of the byte at the given address in radio's memory
 */
uint8_t SX126xReadRegister2( lora_device_t* lora_device,uint16_t address );

/*!
 * \brief Sets the radio output power.
 *
 * \param [IN] power Sets the RF output power
 */
void SX126xSetRfTxPower2( lora_device_t* lora_device,int8_t power );

/*!
 * \brief Gets the board PA selection configuration
 *
 * \param [IN] channel Channel frequency in Hz
 * \retval PaSelect RegPaConfig PaSelect value
 */
uint8_t SX126xGetPaSelect2( lora_device_t* lora_device,uint32_t channel );

/*!
 * \brief Initializes the RF Switch I/Os pins interface
 */
void SX126xAntSwOn2( lora_device_t* lora_device );

/*!
 * \brief De-initializes the RF Switch I/Os pins interface
 *
 * \remark Needed to decrease the power consumption in MCU low power modes
 */
void SX126xAntSwOff2( lora_device_t* lora_device );

/*!
 * \brief Checks if the given RF frequency is supported by the hardware
 *
 * \param [IN] frequency RF frequency to be checked
 * \retval isSupported [true: supported, false: unsupported]
 */
bool SX126xCheckRfFrequency2( lora_device_t* lora_device,uint32_t frequency );

void SX126xDelayMs2(uint32_t ms);
uint8_t SX126xGetIrqFired2( lora_device_t* lora_device );
/*!
 * Radio hardware and global parameters
 */
// extern SX126x_t SX126x;

#endif // __SX126x_ARCH_H__
