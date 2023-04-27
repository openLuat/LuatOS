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

#include "radio.h"
#include "sx126x.h"
#include "sx126x-board.h"

uint8_t SX126xGetIrqFired2( lora_device_t* lora_device ){
    return luat_gpio_get(lora_device->lora_pin_dio1);
}

void SX126xDelayMs2(uint32_t ms){
	luat_timer_mdelay(ms);
}

void SX126xReset2( lora_device_t* lora_device ){
    SX126xDelayMs2(10);
    luat_gpio_set( lora_device->lora_pin_rst, 0 );
    SX126xDelayMs2(20);
    luat_gpio_set( lora_device->lora_pin_rst, 1 );
    SX126xDelayMs2(10);
}

void SX126xWaitOnBusy2( lora_device_t* lora_device ){
    while(luat_gpio_get(lora_device->lora_pin_busy)==1){
        SX126xDelayMs2(1);
    }
}

void SX126xSetNss2(lora_device_t* lora_device,uint8_t lev ){
    luat_gpio_set( lora_device->lora_pin_cs, lev);
}

void lora_spi_transfer(lora_device_t* lora_device, const char* send_buf, size_t send_length, char* recv_buf, size_t recv_length){
    if (lora_device->lora_spi_id == 255){
        luat_spi_device_transfer(lora_device->lora_spi_device, send_buf, send_length, recv_buf, recv_length);
    }else{
        SX126xSetNss2(lora_device,0);
        // luat_spi_transfer(lora_device->lora_spi_id, send_buf, send_length, recv_buf, recv_length);
        if (send_length){
            luat_spi_send(lora_device->lora_spi_id, send_buf, send_length);
        }
        if (recv_length){
            luat_spi_recv(lora_device->lora_spi_id, recv_buf, recv_length);
        }
        SX126xSetNss2(lora_device,1);
    }
}

void SX126xWakeup2( lora_device_t* lora_device){
    uint8_t cmd[2] = {RADIO_GET_STATUS,0x00};
    lora_spi_transfer(lora_device, cmd, 2,NULL,0);
    // Wait for chip to be ready.
    SX126xWaitOnBusy2(lora_device );
}

void SX126xWriteCommand2( lora_device_t* lora_device,RadioCommands_t command, uint8_t *buffer, uint16_t size ){
    uint16_t i = 0;
    SX126xCheckDeviceReady2( lora_device );
    uint8_t cmd[1+size];
    cmd[0] = (uint8_t)command;
    memcpy(cmd+1,buffer,size);
    lora_spi_transfer(lora_device, cmd, 1+size,NULL,0);
    if( command != RADIO_SET_SLEEP ){
        SX126xWaitOnBusy2(lora_device );
    }
}

void SX126xReadCommand2( lora_device_t* lora_device,RadioCommands_t command, uint8_t *buffer, uint16_t size ){
    uint16_t i = 0;
    SX126xCheckDeviceReady2( lora_device);
    uint8_t cmd[2] = {(uint8_t)command,0x00};
    lora_spi_transfer(lora_device, cmd, 2,buffer,size);
    SX126xWaitOnBusy2(lora_device );
}

void SX126xWriteRegister2s2(lora_device_t* lora_device, uint16_t address, uint8_t *buffer, uint16_t size ){
    uint16_t i = 0;
    SX126xCheckDeviceReady2( lora_device );
    uint8_t cmd[3+size];
    cmd[0] = RADIO_WRITE_REGISTER;
    cmd[1] = (address & 0xFF00 ) >> 8;
    cmd[2] = address & 0x00FF;
    memcpy(cmd+3,buffer,size);
    lora_spi_transfer(lora_device, cmd, 3+size,NULL,0);
    SX126xWaitOnBusy2( lora_device);
}

void SX126xWriteRegister2( lora_device_t* lora_device,uint16_t address, uint8_t value ){
    SX126xWriteRegister2s2( lora_device,address, &value, 1 );
}

void SX126xReadRegister2s2( lora_device_t* lora_device,uint16_t address, uint8_t *buffer, uint16_t size ){
    uint16_t i = 0;
    SX126xCheckDeviceReady2(lora_device );
    uint8_t cmd[4] = {RADIO_READ_REGISTER,( address & 0xFF00 ) >> 8,address & 0x00FF,0x00};
    lora_spi_transfer(lora_device, cmd, 4,buffer,size);
    SX126xWaitOnBusy2( lora_device);
}

uint8_t SX126xReadRegister2( lora_device_t* lora_device,uint16_t address ){
    uint8_t data;
    SX126xReadRegister2s2( lora_device,address, &data, 1 );
    return data;
}

void SX126xWriteBuffer2( lora_device_t* lora_device,uint8_t offset, uint8_t *buffer, uint8_t size ){
    uint16_t i = 0;
    SX126xCheckDeviceReady2( lora_device);
    uint8_t cmd[2+size];
    cmd[0] = RADIO_WRITE_BUFFER;
    cmd[1] = offset;
    memcpy(cmd+2,buffer,size);
    luat_spi_send(lora_device->lora_spi_id, cmd, 2+size);
    lora_spi_transfer(lora_device, cmd, 2+size,NULL,0);
    SX126xWaitOnBusy2(lora_device );
}

void SX126xReadBuffer2(lora_device_t* lora_device, uint8_t offset, uint8_t *buffer, uint8_t size ){
    uint16_t i = 0;
    SX126xCheckDeviceReady2(lora_device);
    uint8_t cmd[3] = {RADIO_READ_BUFFER,offset,0x00};
    lora_spi_transfer(lora_device, cmd, 3,buffer,size);
    SX126xWaitOnBusy2(lora_device );
}

void SX126xSetRfTxPower2(lora_device_t* lora_device, int8_t power ){
    SX126xSetTx2Params2( lora_device,power, RADIO_RAMP_40_US );
}

uint8_t SX126xGetPaSelect2(lora_device_t* lora_device, uint32_t channel ){
    return SX1262;
}

void SX126xAntSwOn2( lora_device_t* lora_device ){

}

void SX126xAntSwOff2( lora_device_t* lora_device ){

}

bool SX126xCheckRfFrequency2( lora_device_t* lora_device,uint32_t frequency ){
    // Implement check. Currently all frequencies are supported
    return true;
}
