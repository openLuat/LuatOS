/*!
 * \file      sx126x.c
 *
 * \brief     SX126x driver implementation
 *
 * \copyright Revised BSD License, see section \ref LICENSE.
 *
 * \code
 *                ______                              _
 *               / _____)             _              | |
 *              ( (____  _____ ____ _| |_ _____  ____| |__
 *               \____ \| ___ |    (_   _) ___ |/ ___)  _ \
 *               _____) ) ____| | | || |_| ____( (___| | | |
 *              (______/|_____)_|_|_| \__)_____)\____)_| |_|
 *              (C)2013-2017 Semtech
 *
 * \endcode
 *
 * \author    Miguel Luis ( Semtech )
 *
 * \author    Gregory Cristian ( Semtech )
 */
#include <math.h>
#include <string.h>
#include "radio.h"
#include "sx126x.h"
#include "sx126x-board.h"

//#define USE_TCXO
/*!
 * \brief Radio registers definition
 */
typedef struct
{
    uint16_t      Addr;                             //!< The address of the register
    uint8_t       Value;                            //!< The value of the register
}RadioRegisters_t;

/*!
 * \brief Holds the internal operating mode of the radio
 */
// static RadioOperatingModes_t OperatingMode;

/*!
 * \brief Stores the current packet type set in the radio
 */
// static RadioPacketTypes_t PacketType;

/*!
 * \brief Stores the last frequency error measured on LoRa received packet
 */
// volatile uint32_t FrequencyError = 0;

/*!
 * \brief Hold the status of the Image calibration
 */
// static bool ImageCalibrated = false;

/*
 * SX126x DIO IRQ callback functions prototype
 */

/*!
 * \brief DIO 0 IRQ callback
 */
void SX126xOnDioIrq( lora_device_t* lora_device );

/*!
 * \brief DIO 0 IRQ callback
 */
void SX126xSetPollingMode( lora_device_t* lora_device );

/*!
 * \brief DIO 0 IRQ callback
 */
void SX126xSetInterruptMode( lora_device_t* lora_device );

/*
 * \brief Process the IRQ if handled by the driver
 */
void SX126xProcessIrqs( lora_device_t* lora_device );


void SX126xInit2( lora_device_t* lora_device,DioIrqHandler dioIrq )
{
    SX126xReset2( lora_device);
    SX126xWakeup2( lora_device );
    SX126xSetStandby2( lora_device,STDBY_RC );
#ifdef USE_TCXO
    CalibrationParams_t calibParam;

    SX126xSetDio3AsTcxoCtrl2( lora_device,TCXO_CTRL_1_7V, RADIO_TCXO_SETUP_TIME << 6 ); // convert from ms to SX126x time base
    calibParam.Value = 0x7F;    
    SX126xCalibrate2( lora_device,calibParam );

#endif
    SX126xSetDio2AsRfSwitchCtrl2( lora_device,true );
    lora_device->OperatingMode = MODE_STDBY_RC;
}

RadioOperatingModes_t SX126xGetOperatingMode2( lora_device_t* lora_device )
{
    return lora_device->OperatingMode;
}

void SX126xCheckDeviceReady2( lora_device_t* lora_device )
{
    if( ( SX126xGetOperatingMode2( lora_device) == MODE_SLEEP ) || ( SX126xGetOperatingMode2( lora_device) == MODE_RX_DC ) )
    {
        SX126xWakeup2( lora_device);
        // Switch is turned off when device is in sleep mode and turned on is all other modes
        SX126xAntSwOn2( lora_device );
    }
    SX126xWaitOnBusy2( lora_device );
}

void SX126xSetPayload2( lora_device_t* lora_device,uint8_t *payload, uint8_t size )
{
    SX126xWriteBuffer2( lora_device,0x00, payload, size );
}

uint8_t SX126xGetPayload2( lora_device_t* lora_device,uint8_t *buffer, uint8_t *size,  uint8_t maxSize )
{
    uint8_t offset = 0;

    SX126xGetRxBufferStatus2( lora_device,size, &offset );
    if( *size > maxSize )
    {
        return 1;
    }
    SX126xReadBuffer2( lora_device, offset, buffer, *size );
    return 0;
}

void SX126xSendPayload2(lora_device_t* lora_device, uint8_t *payload, uint8_t size, uint32_t timeout )
{
    SX126xSetPayload2(lora_device,payload, size );
    SX126xSetTx2( lora_device,timeout );
}

uint8_t SX126xSetSyncWord2( lora_device_t* lora_device,uint8_t *syncWord )
{
    SX126xWriteRegister2s2(lora_device,REG_LR_SYNCWORDBASEADDRESS, syncWord, 8 );
    return 0;
}

void SX126xSetCrcSeed2( lora_device_t* lora_device,uint16_t seed )
{
    uint8_t buf[2];

    buf[0] = ( uint8_t )( ( seed >> 8 ) & 0xFF );
    buf[1] = ( uint8_t )( seed & 0xFF );

    switch( SX126xGetPacketType2( lora_device) )
    {
        case PACKET_TYPE_GFSK:
            SX126xWriteRegister2s2(lora_device, REG_LR_CRCSEEDBASEADDR, buf, 2 );
            break;

        default:
            break;
    }
}

void SX126xSetCrcPolynomial2( lora_device_t* lora_device,uint16_t polynomial )
{
    uint8_t buf[2];

    buf[0] = ( uint8_t )( ( polynomial >> 8 ) & 0xFF );
    buf[1] = ( uint8_t )( polynomial & 0xFF );

    switch( SX126xGetPacketType2( lora_device) )
    {
        case PACKET_TYPE_GFSK:
            SX126xWriteRegister2s2( lora_device,REG_LR_CRCPOLYBASEADDR, buf, 2 );
            break;

        default:
            break;
    }
}

void SX126xSetWhiteningSeed2( lora_device_t* lora_device,uint16_t seed )
{
    uint8_t regValue = 0;
    
    switch( SX126xGetPacketType2( lora_device ) )
    {
        case PACKET_TYPE_GFSK:
            regValue = SX126xReadRegister2( lora_device,REG_LR_WHITSEEDBASEADDR_MSB ) & 0xFE;
            regValue = ( ( seed >> 8 ) & 0x01 ) | regValue;
            SX126xWriteRegister2( lora_device,REG_LR_WHITSEEDBASEADDR_MSB, regValue ); // only 1 bit.
            SX126xWriteRegister2( lora_device,REG_LR_WHITSEEDBASEADDR_LSB, ( uint8_t )seed );
            break;

        default:
            break;
    }
}

uint32_t SX126xGetRandom2( lora_device_t* lora_device )
{
    uint8_t buf[] = { 0, 0, 0, 0 };

    // Set radio in continuous reception
    SX126xSetRx2( lora_device,0 );

    SX126xDelayMs2( 1 );

    SX126xReadRegister2s2(  lora_device,RANDOM_NUMBER_GENERATORBASEADDR, buf, 4 );

    SX126xSetStandby2(lora_device, STDBY_RC );

    return ( buf[0] << 24 ) | ( buf[1] << 16 ) | ( buf[2] << 8 ) | buf[3];
}

void SX126xSetSleep2( lora_device_t* lora_device,SleepParams_t sleepConfig )
{
    SX126xAntSwOff2(lora_device );

    SX126xWriteCommand2(  lora_device,RADIO_SET_SLEEP, &sleepConfig.Value, 1 );
    lora_device->OperatingMode = MODE_SLEEP;
}

void SX126xSetStandby2( lora_device_t* lora_device,RadioStandbyModes_t standbyConfig )
{
    SX126xWriteCommand2( lora_device,RADIO_SET_STANDBY, ( uint8_t* )&standbyConfig, 1 );
    if( standbyConfig == STDBY_RC )
    {
        lora_device->OperatingMode = MODE_STDBY_RC;
    }
    else
    {
        lora_device->OperatingMode = MODE_STDBY_XOSC;
    }
}

void SX126xSetFs2(lora_device_t* lora_device )
{
    SX126xWriteCommand2(lora_device,RADIO_SET_FS, 0, 0 );
    lora_device->OperatingMode = MODE_FS;
}

void SX126xSetTx2( lora_device_t* lora_device,uint32_t timeout )
{
    uint8_t buf[3];

    lora_device->OperatingMode = MODE_TX;

    buf[0] = ( uint8_t )( ( timeout >> 16 ) & 0xFF );
    buf[1] = ( uint8_t )( ( timeout >> 8 ) & 0xFF );
    buf[2] = ( uint8_t )( timeout & 0xFF );
    SX126xWriteCommand2( lora_device,RADIO_SET_TX, buf, 3 );
}

void SX126xSetRx2( lora_device_t* lora_device,uint32_t timeout )
{
    uint8_t buf[3];

    lora_device->OperatingMode = MODE_RX;

    buf[0] = ( uint8_t )( ( timeout >> 16 ) & 0xFF );
    buf[1] = ( uint8_t )( ( timeout >> 8 ) & 0xFF );
    buf[2] = ( uint8_t )( timeout & 0xFF );
    SX126xWriteCommand2( lora_device,RADIO_SET_RX, buf, 3 );
}

void SX126xSetRxBoosted2( lora_device_t* lora_device,uint32_t timeout )
{
    uint8_t buf[3];

    lora_device->OperatingMode = MODE_RX;

    SX126xWriteRegister2(lora_device,REG_RX_GAIN, 0x96 ); // max LNA gain, increase current by ~2mA for around ~3dB in sensivity

    buf[0] = ( uint8_t )( ( timeout >> 16 ) & 0xFF );
    buf[1] = ( uint8_t )( ( timeout >> 8 ) & 0xFF );
    buf[2] = ( uint8_t )( timeout & 0xFF );
    SX126xWriteCommand2(  lora_device,RADIO_SET_RX, buf, 3 );
}

void SX126xSetRxDutyCycle2( lora_device_t* lora_device,uint32_t rxTime, uint32_t sleepTime )
{
    uint8_t buf[6];

    buf[0] = ( uint8_t )( ( rxTime >> 16 ) & 0xFF );
    buf[1] = ( uint8_t )( ( rxTime >> 8 ) & 0xFF );
    buf[2] = ( uint8_t )( rxTime & 0xFF );
    buf[3] = ( uint8_t )( ( sleepTime >> 16 ) & 0xFF );
    buf[4] = ( uint8_t )( ( sleepTime >> 8 ) & 0xFF );
    buf[5] = ( uint8_t )( sleepTime & 0xFF );
    SX126xWriteCommand2( lora_device,RADIO_SET_RXDUTYCYCLE, buf, 6 );
    lora_device->OperatingMode = MODE_RX_DC;
}

void SX126xSetCad2( lora_device_t* lora_device )
{
    SX126xWriteCommand2( lora_device,RADIO_SET_CAD, 0, 0 );
    lora_device->OperatingMode = MODE_CAD;
}

void SX126xSetTx2ContinuousWave2( lora_device_t* lora_device )
{
    SX126xWriteCommand2( lora_device,RADIO_SET_TXCONTINUOUSWAVE, 0, 0 );
}

void SX126xSetTx2InfinitePreamble2( lora_device_t* lora_device )
{
    SX126xWriteCommand2( lora_device,RADIO_SET_TXCONTINUOUSPREAMBLE, 0, 0 );
}

void SX126xSetStopRxTimerOnPreambleDetect2( lora_device_t* lora_device,bool enable )
{
    SX126xWriteCommand2( lora_device,RADIO_SET_STOPRXTIMERONPREAMBLE, ( uint8_t* )&enable, 1 );
}

void SX126xSetLoRaSymbNumTimeout2( lora_device_t* lora_device,uint8_t SymbNum )
{
    SX126xWriteCommand2( lora_device, RADIO_SET_LORASYMBTIMEOUT, &SymbNum, 1 );
}

void SX126xSetRegulatorMode2( lora_device_t* lora_device,RadioRegulatorMode_t mode )
{
    SX126xWriteCommand2(  lora_device,RADIO_SET_REGULATORMODE, ( uint8_t* )&mode, 1 );
}

void SX126xCalibrate2( lora_device_t* lora_device,CalibrationParams_t calibParam )
{
    SX126xWriteCommand2( lora_device, RADIO_CALIBRATE, ( uint8_t* )&calibParam, 1 );
}

void SX126xCalibrateImage2( lora_device_t* lora_device,uint32_t freq )
{
    uint8_t calFreq[2];

    if( freq > 900000000 )
    {
        calFreq[0] = 0xE1;
        calFreq[1] = 0xE9;
    }
    else if( freq > 850000000 )
    {
        calFreq[0] = 0xD7;
        calFreq[1] = 0xD8;
    }
    else if( freq > 770000000 )
    {
        calFreq[0] = 0xC1;
        calFreq[1] = 0xC5;
    }
    else if( freq > 460000000 )
    {
        calFreq[0] = 0x75;
        calFreq[1] = 0x81;
    }
    else if( freq > 425000000 )
    {
        calFreq[0] = 0x6B;
        calFreq[1] = 0x6F;
    }
    SX126xWriteCommand2(lora_device,RADIO_CALIBRATEIMAGE, calFreq, 2 );
}

void SX126xSetPaConfig2( lora_device_t* lora_device,uint8_t paDutyCycle, uint8_t hpMax, uint8_t deviceSel, uint8_t paLut )
{
    uint8_t buf[4];

    buf[0] = paDutyCycle;
    buf[1] = hpMax;
    buf[2] = deviceSel;
    buf[3] = paLut;
    SX126xWriteCommand2( lora_device,RADIO_SET_PACONFIG, buf, 4 );
}

void SX126xSetRx2TxFallbackMode2( lora_device_t* lora_device,uint8_t fallbackMode )
{
    SX126xWriteCommand2( lora_device,RADIO_SET_TXFALLBACKMODE, &fallbackMode, 1 );
}

void SX126xSetDioIrqParams2( lora_device_t* lora_device,uint16_t irqMask, uint16_t dio1Mask, uint16_t dio2Mask, uint16_t dio3Mask )
{
    uint8_t buf[8];

    buf[0] = ( uint8_t )( ( irqMask >> 8 ) & 0x00FF );
    buf[1] = ( uint8_t )( irqMask & 0x00FF );
    buf[2] = ( uint8_t )( ( dio1Mask >> 8 ) & 0x00FF );
    buf[3] = ( uint8_t )( dio1Mask & 0x00FF );
    buf[4] = ( uint8_t )( ( dio2Mask >> 8 ) & 0x00FF );
    buf[5] = ( uint8_t )( dio2Mask & 0x00FF );
    buf[6] = ( uint8_t )( ( dio3Mask >> 8 ) & 0x00FF );
    buf[7] = ( uint8_t )( dio3Mask & 0x00FF );
    SX126xWriteCommand2( lora_device,RADIO_CFG_DIOIRQ, buf, 8 );
}

uint16_t SX126xGetIrqStatus2( lora_device_t* lora_device )
{
    uint8_t irqStatus[2];

    SX126xReadCommand2( lora_device,RADIO_GET_IRQSTATUS, irqStatus, 2 );
    return ( irqStatus[0] << 8 ) | irqStatus[1];
}

void SX126xSetDio2AsRfSwitchCtrl2( lora_device_t* lora_device,uint8_t enable )
{
    SX126xWriteCommand2(lora_device,RADIO_SET_RFSWITCHMODE, &enable, 1 );
}

void SX126xSetDio3AsTcxoCtrl2( lora_device_t* lora_device,RadioTcxoCtrlVoltage_t tcxoVoltage, uint32_t timeout )
{
    uint8_t buf[4];

    buf[0] = tcxoVoltage & 0x07;
    buf[1] = ( uint8_t )( ( timeout >> 16 ) & 0xFF );
    buf[2] = ( uint8_t )( ( timeout >> 8 ) & 0xFF );
    buf[3] = ( uint8_t )( timeout & 0xFF );

    SX126xWriteCommand2( lora_device,RADIO_SET_TCXOMODE, buf, 4 );
}

void SX126xSetRfFrequency2( lora_device_t* lora_device,uint32_t frequency )
{
    uint8_t buf[4];
    uint32_t freq = 0;

    if( lora_device->ImageCalibrated == false )
    {
        SX126xCalibrateImage2( lora_device,frequency );
        lora_device->ImageCalibrated = true;
    }

    freq = ( uint32_t )( ( double )frequency / ( double )FREQ_STEP );
    buf[0] = ( uint8_t )( ( freq >> 24 ) & 0xFF );
    buf[1] = ( uint8_t )( ( freq >> 16 ) & 0xFF );
    buf[2] = ( uint8_t )( ( freq >> 8 ) & 0xFF );
    buf[3] = ( uint8_t )( freq & 0xFF );
    SX126xWriteCommand2( lora_device,RADIO_SET_RFFREQUENCY, buf, 4 );
}

void SX126xSetPacketType2( lora_device_t* lora_device,RadioPacketTypes_t packetType )
{
    // Save packet type internally to avoid questioning the radio
    lora_device->PacketType = packetType;
    SX126xWriteCommand2( lora_device,RADIO_SET_PACKETTYPE, ( uint8_t* )&packetType, 1 );
}

RadioPacketTypes_t SX126xGetPacketType2( lora_device_t* lora_device )
{
    return lora_device->PacketType;
}

void SX126xSetTx2Params2( lora_device_t* lora_device,int8_t power, RadioRampTimes_t rampTime )
{
    uint8_t buf[2];

    if( SX126xGetPaSelect2( lora_device,0 ) == SX1261 )
    {
        if( power == 15 )
        {
            SX126xSetPaConfig2( lora_device,0x06, 0x00, 0x01, 0x01 );
        }
        else
        {
            SX126xSetPaConfig2( lora_device,0x04, 0x00, 0x01, 0x01 );
        }
        if( power >= 14 )
        {
            power = 14;
        }
        else if( power < -3 )
        {
            power = -3;
        }
        SX126xWriteRegister2( lora_device,REG_OCP, 0x18 ); // current max is 80 mA for the whole device
    }
    else // sx1262
    {
        SX126xSetPaConfig2( lora_device,0x04, 0x07, 0x00, 0x01 );
        if( power > 22 )
        {
            power = 22;
        }
        else if( power < -3 )
        {
            power = -3;
        }
        SX126xWriteRegister2(lora_device,REG_OCP, 0x38 ); // current max 160mA for the whole device
    }
    buf[0] = power;
    buf[1] = ( uint8_t )rampTime;
    SX126xWriteCommand2( lora_device,RADIO_SET_TXPARAMS, buf, 2 );
}

void SX126xSetModulationParams2( lora_device_t* lora_device,ModulationParams_t *modulationParams )
{
    uint8_t n;
    uint32_t tempVal = 0;
    uint8_t buf[8] = { 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00 };

    // Check if required configuration corresponds to the stored packet type
    // If not, silently update radio packet type
    if( lora_device->PacketType != modulationParams->PacketType )
    {
        SX126xSetPacketType2( lora_device,modulationParams->PacketType );
    }

    switch( modulationParams->PacketType )
    {
    case PACKET_TYPE_GFSK:
        n = 8;
        tempVal = ( uint32_t )( 32 * ( ( double )XTAL_FREQ / ( double )modulationParams->Params.Gfsk.BitRate ) );
        buf[0] = ( tempVal >> 16 ) & 0xFF;
        buf[1] = ( tempVal >> 8 ) & 0xFF;
        buf[2] = tempVal & 0xFF;
        buf[3] = modulationParams->Params.Gfsk.ModulationShaping;
        buf[4] = modulationParams->Params.Gfsk.Bandwidth;
        tempVal = ( uint32_t )( ( double )modulationParams->Params.Gfsk.Fdev / ( double )FREQ_STEP );
        buf[5] = ( tempVal >> 16 ) & 0xFF;
        buf[6] = ( tempVal >> 8 ) & 0xFF;
        buf[7] = ( tempVal& 0xFF );
        SX126xWriteCommand2( lora_device,RADIO_SET_MODULATIONPARAMS, buf, n );
        break;
    case PACKET_TYPE_LORA:
        n = 4;
        buf[0] = modulationParams->Params.LoRa.SpreadingFactor;
        buf[1] = modulationParams->Params.LoRa.Bandwidth;
        buf[2] = modulationParams->Params.LoRa.CodingRate;
        buf[3] = modulationParams->Params.LoRa.LowDatarateOptimize;

        SX126xWriteCommand2(lora_device,RADIO_SET_MODULATIONPARAMS, buf, n );

        break;
    default:
    case PACKET_TYPE_NONE:
        return;
    }
}

void SX126xSetPacketParams2( lora_device_t* lora_device,PacketParams_t *packetParams )
{
    uint8_t n;
    uint8_t crcVal = 0;
    uint8_t buf[9] = { 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00 };

    // Check if required configuration corresponds to the stored packet type
    // If not, silently update radio packet type
    if( lora_device->PacketType != packetParams->PacketType )
    {
        SX126xSetPacketType2( lora_device,packetParams->PacketType );
    }

    switch( packetParams->PacketType )
    {
    case PACKET_TYPE_GFSK:
        if( packetParams->Params.Gfsk.CrcLength == RADIO_CRC_2_BYTES_IBM )
        {
            SX126xSetCrcSeed2(lora_device,CRC_IBM_SEED );
            SX126xSetCrcPolynomial2(lora_device, CRC_POLYNOMIAL_IBM );
            crcVal = RADIO_CRC_2_BYTES;
        }
        else if( packetParams->Params.Gfsk.CrcLength == RADIO_CRC_2_BYTES_CCIT )
        {
            SX126xSetCrcSeed2(lora_device, CRC_CCITT_SEED );
            SX126xSetCrcPolynomial2(lora_device,CRC_POLYNOMIAL_CCITT );
            crcVal = RADIO_CRC_2_BYTES_INV;
        }
        else
        {
            crcVal = packetParams->Params.Gfsk.CrcLength;
        }
        n = 9;
        buf[0] = ( packetParams->Params.Gfsk.PreambleLength >> 8 ) & 0xFF;
        buf[1] = packetParams->Params.Gfsk.PreambleLength;
        buf[2] = packetParams->Params.Gfsk.PreambleMinDetect;
        buf[3] = ( packetParams->Params.Gfsk.SyncWordLength /*<< 3*/ ); // convert from byte to bit
        buf[4] = packetParams->Params.Gfsk.AddrComp;
        buf[5] = packetParams->Params.Gfsk.HeaderType;
        buf[6] = packetParams->Params.Gfsk.PayloadLength;
        buf[7] = crcVal;
        buf[8] = packetParams->Params.Gfsk.DcFree;
        break;
    case PACKET_TYPE_LORA:
        n = 6;
        buf[0] = ( packetParams->Params.LoRa.PreambleLength >> 8 ) & 0xFF;
        buf[1] = packetParams->Params.LoRa.PreambleLength;
        buf[2] = packetParams->Params.LoRa.HeaderType;
        buf[3] = packetParams->Params.LoRa.PayloadLength;
        buf[4] = packetParams->Params.LoRa.CrcMode;
        buf[5] = packetParams->Params.LoRa.InvertIQ;
        break;
    default:
    case PACKET_TYPE_NONE:
        return;
    }
    SX126xWriteCommand2(lora_device,RADIO_SET_PACKETPARAMS, buf, n );
}

void SX126xSetCad2Params2( lora_device_t* lora_device,RadioLoRaCadSymbols_t cadSymbolNum, uint8_t cadDetPeak, uint8_t cadDetMin, RadioCadExitModes_t cadExitMode, uint32_t cadTimeout )
{
    uint8_t buf[7];

    buf[0] = ( uint8_t )cadSymbolNum;
    buf[1] = cadDetPeak;
    buf[2] = cadDetMin;
    buf[3] = ( uint8_t )cadExitMode;
    buf[4] = ( uint8_t )( ( cadTimeout >> 16 ) & 0xFF );
    buf[5] = ( uint8_t )( ( cadTimeout >> 8 ) & 0xFF );
    buf[6] = ( uint8_t )( cadTimeout & 0xFF );
    SX126xWriteCommand2( lora_device,RADIO_SET_CADPARAMS, buf, 5 );
    lora_device->OperatingMode = MODE_CAD;
}

void SX126xSetBufferBaseAddress2(lora_device_t* lora_device,uint8_t txBaseAddress, uint8_t rxBaseAddress )
{
    uint8_t buf[2];

    buf[0] = txBaseAddress;
    buf[1] = rxBaseAddress;
    SX126xWriteCommand2(lora_device,RADIO_SET_BUFFERBASEADDRESS, buf, 2 );
}

RadioStatus_t SX126xGetStatus2( lora_device_t* lora_device )
{
    uint8_t stat = 0;
    RadioStatus_t status;

    SX126xReadCommand2(lora_device,RADIO_GET_STATUS, ( uint8_t * )&stat, 1 );
    status.Value = stat;
    return status;
}

int8_t SX126xGetRssiInst2( lora_device_t* lora_device )
{
    uint8_t buf[1];
    int8_t rssi = 0;

    SX126xReadCommand2(lora_device,RADIO_GET_RSSIINST, buf, 1 );
    rssi = -buf[0] >> 1;
    return rssi;
}

void SX126xGetRxBufferStatus2( lora_device_t* lora_device,uint8_t *payloadLength, uint8_t *rxStartBufferPointer )
{
    uint8_t status[2];

    SX126xReadCommand2( lora_device,RADIO_GET_RXBUFFERSTATUS, status, 2 );

    // In case of LORA fixed header, the payloadLength is obtained by reading
    // the register REG_LR_PAYLOADLENGTH
    if( ( SX126xGetPacketType2(lora_device ) == PACKET_TYPE_LORA ) && ( SX126xReadRegister2( lora_device,REG_LR_PACKETPARAMS ) >> 7 == 1 ) )
    {
        *payloadLength = SX126xReadRegister2( lora_device,REG_LR_PAYLOADLENGTH );
    }
    else
    {
        *payloadLength = status[0];
    }
    *rxStartBufferPointer = status[1];
}

void SX126xGetPacketStatus2( lora_device_t* lora_device,PacketStatus_t *pktStatus )
{
    uint8_t status[3];

    SX126xReadCommand2(lora_device,RADIO_GET_PACKETSTATUS, status, 3 );

    pktStatus->packetType = SX126xGetPacketType2(lora_device );
    switch( pktStatus->packetType )
    {
        case PACKET_TYPE_GFSK:
            pktStatus->Params.Gfsk.RxStatus = status[0];
            pktStatus->Params.Gfsk.RssiSync = -status[1] >> 1;
            pktStatus->Params.Gfsk.RssiAvg = -status[2] >> 1;
            pktStatus->Params.Gfsk.FreqError = 0;
            break;

        case PACKET_TYPE_LORA:
            pktStatus->Params.LoRa.RssiPkt = -status[0] >> 1;
            ( status[1] < 128 ) ? ( pktStatus->Params.LoRa.SnrPkt = status[1] >> 2 ) : ( pktStatus->Params.LoRa.SnrPkt = ( ( status[1] - 256 ) >> 2 ) );
            pktStatus->Params.LoRa.SignalRssiPkt = -status[2] >> 1;
            pktStatus->Params.LoRa.FreqError = lora_device->FrequencyError;
            break;

        default:
        case PACKET_TYPE_NONE:
            // In that specific case, we set everything in the pktStatus to zeros
            // and reset the packet type accordingly
            memset( pktStatus, 0, sizeof( PacketStatus_t ) );
            pktStatus->packetType = PACKET_TYPE_NONE;
            break;
    }
}

RadioError_t SX126xGetDeviceErrors2( lora_device_t* lora_device )
{
    RadioError_t error;

    SX126xReadCommand2( lora_device,RADIO_GET_ERROR, ( uint8_t * )&error, 2 );
    return error;
}

void SX126xClearDeviceErrors2( lora_device_t* lora_device )
{
    uint8_t buf[2] = { 0x00, 0x00 };
    SX126xWriteCommand2(lora_device,RADIO_CLR_ERROR, buf, 2 );
}

void SX126xClearIrqStatus2(lora_device_t* lora_device, uint16_t irq )
{
    uint8_t buf[2];

    buf[0] = ( uint8_t )( ( ( uint16_t )irq >> 8 ) & 0x00FF );
    buf[1] = ( uint8_t )( ( uint16_t )irq & 0x00FF );
    SX126xWriteCommand2(lora_device,RADIO_CLR_IRQSTATUS, buf, 2 );
}
