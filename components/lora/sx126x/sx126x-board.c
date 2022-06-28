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

#include "luat_base.h"
#include "luat_gpio.h"
#include "luat_spi.h"
#include "luat_timer.h"
#include "radio.h"
#include "sx126x.h"
#include "sx126x-board.h"

uint8_t SX126xSpi;
uint8_t SX126xCsPin;
uint8_t SX126xResetPin;
uint8_t SX126xBusyPin;
uint8_t SX126xDio1Pin;

uint8_t SX126xGetIrqFired( void ){
    return luat_gpio_get(SX126xDio1Pin);
}

void SX126xDelayMs(uint32_t ms){
	luat_timer_mdelay(ms);
}

void SX126xReset( void ){
    SX126xDelayMs( 10 );
    luat_gpio_set( SX126xResetPin, 0 );
    SX126xDelayMs( 20 );
    luat_gpio_set( SX126xResetPin, 1 );
    SX126xDelayMs( 10 );
}

void SX126xWaitOnBusy( void ){
    while(luat_gpio_get(SX126xBusyPin)==1){
        SX126xDelayMs(1);
    }
}

uint8_t SX126xSpiIn(void){
    char data;
    luat_spi_recv(SX126xSpi, &data, 1);
	return (uint8_t)data;
}

void SX126xSpiOut(const char data){
    luat_spi_send(SX126xSpi, &data, 1);
}

void SX126xSetNss(uint8_t lev ){
    luat_gpio_set( SX126xCsPin, lev);
}

void SX126xWakeup( void ){
    SX126xSetNss(0);
    SX126xSpiOut(RADIO_GET_STATUS);
    SX126xSpiOut(0x00);
    SX126xSetNss(1);
    // Wait for chip to be ready.
    SX126xWaitOnBusy( );
}

void SX126xWriteCommand( RadioCommands_t command, uint8_t *buffer, uint16_t size ){
    uint16_t i = 0;
    SX126xCheckDeviceReady( );
    SX126xSetNss(0);
    SX126xSpiOut((uint8_t)command);
    for( i = 0; i < size; i++ ){
		SX126xSpiOut(buffer[i]);
	}

    SX126xSetNss(1);
    if( command != RADIO_SET_SLEEP ){
        SX126xWaitOnBusy( );
    }
}

void SX126xReadCommand( RadioCommands_t command, uint8_t *buffer, uint16_t size ){
    uint16_t i = 0;
    SX126xCheckDeviceReady( );
    SX126xSetNss(0);
    SX126xSpiOut((uint8_t)command);
    SX126xSpiOut(0x00);
    for( i = 0; i < size; i++ ){
		buffer[i] = SX126xSpiIn();
	}

    SX126xSetNss(1);
    SX126xWaitOnBusy( );
}

void SX126xWriteRegisters( uint16_t address, uint8_t *buffer, uint16_t size ){
    uint16_t i = 0;
    SX126xCheckDeviceReady( );
    SX126xSetNss(0);
    SX126xSpiOut(RADIO_WRITE_REGISTER);
    SX126xSpiOut(( address & 0xFF00 ) >> 8);
    SX126xSpiOut(address & 0x00FF);
    for( i = 0; i < size; i++ ){
		SX126xSpiOut(buffer[i]);
	}
    SX126xSetNss(1);
    SX126xWaitOnBusy( );
}

void SX126xWriteRegister( uint16_t address, uint8_t value ){
    SX126xWriteRegisters( address, &value, 1 );
}

void SX126xReadRegisters( uint16_t address, uint8_t *buffer, uint16_t size ){
    uint16_t i = 0;
    SX126xCheckDeviceReady( );
    SX126xSetNss(0);
    SX126xSpiOut((uint8_t)RADIO_READ_REGISTER);
    SX126xSpiOut(( address & 0xFF00 ) >> 8);
    SX126xSpiOut(address & 0x00FF);
    SX126xSpiOut(0x00);
    for( i = 0; i < size; i++ ){
		buffer[i] = SX126xSpiIn();
	}
    SX126xSetNss(1);
    SX126xWaitOnBusy( );
}

uint8_t SX126xReadRegister( uint16_t address ){
    uint8_t data;
    SX126xReadRegisters( address, &data, 1 );
    return data;
}

void SX126xWriteBuffer( uint8_t offset, uint8_t *buffer, uint8_t size ){
    uint16_t i = 0;
    SX126xCheckDeviceReady( );
    SX126xSetNss(0);
    SX126xSpiOut(RADIO_WRITE_BUFFER);
    SX126xSpiOut(offset);

    for( i = 0; i < size; i++ ){
		SX126xSpiOut(buffer[i]);
	}
    SX126xSetNss(1);
    SX126xWaitOnBusy( );
}

void SX126xReadBuffer( uint8_t offset, uint8_t *buffer, uint8_t size ){
    uint16_t i = 0;
    SX126xCheckDeviceReady( );
    SX126xSetNss(0);
    SX126xSpiOut((uint8_t)RADIO_READ_BUFFER);
    SX126xSpiOut(offset);
    SX126xSpiOut(0x00);
    for( i = 0; i < size; i++ ){
		buffer[i] = SX126xSpiIn();
	}
    SX126xSetNss(1);
    SX126xWaitOnBusy( );
}

void SX126xSetRfTxPower( int8_t power ){
    SX126xSetTxParams( power, RADIO_RAMP_40_US );
}

uint8_t SX126xGetPaSelect( uint32_t channel ){
    return SX1262;
}

void SX126xAntSwOn( void ){

}

void SX126xAntSwOff( void ){

}

bool SX126xCheckRfFrequency( uint32_t frequency ){
    // Implement check. Currently all frequencies are supported
    return true;
}
