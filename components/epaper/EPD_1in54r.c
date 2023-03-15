#include "EPD_1in54r.h"
#include "Debug.h"

const unsigned char EPD_1IN54R_lut_vcom0[] = {0x0E, 0x14, 0x01, 0x0A, 0x06, 0x04, 0x0A, 0x0A, 0x0F, 0x03, 0x03, 0x0C, 0x06, 0x0A, 0x00};
const unsigned char EPD_1IN54R_lut_w[] = {0x0E, 0x14, 0x01, 0x0A, 0x46, 0x04, 0x8A, 0x4A, 0x0F, 0x83, 0x43, 0x0C, 0x86, 0x0A, 0x04};
const unsigned char EPD_1IN54R_lut_b[] = {0x0E, 0x14, 0x01, 0x8A, 0x06, 0x04, 0x8A, 0x4A, 0x0F, 0x83, 0x43, 0x0C, 0x06, 0x4A, 0x04};
const unsigned char EPD_1IN54R_lut_g1[] = {0x8E, 0x94, 0x01, 0x8A, 0x06, 0x04, 0x8A, 0x4A, 0x0F, 0x83, 0x43, 0x0C, 0x06, 0x0A, 0x04};
const unsigned char EPD_1IN54R_lut_g2[] = {0x8E, 0x94, 0x01, 0x8A, 0x06, 0x04, 0x8A, 0x4A, 0x0F, 0x83, 0x43, 0x0C, 0x06, 0x0A, 0x04};
const unsigned char EPD_1IN54R_lut_vcom1[] = {0x03, 0x1D, 0x01, 0x01, 0x08, 0x23, 0x37, 0x37, 0x01, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00};
const unsigned char EPD_1IN54R_lut_red0[] = {0x83, 0x5D, 0x01, 0x81, 0x48, 0x23, 0x77, 0x77, 0x01, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00};
const unsigned char EPD_1IN54R_lut_red1[] = {0x03, 0x1D, 0x01, 0x01, 0x08, 0x23, 0x37, 0x37, 0x01, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00};

/******************************************************************************
function :	Software reset
parameter:
******************************************************************************/
static void EPD_1IN54R_Reset(void)
{
    DEV_Digital_Write(EPD_RST_PIN, 1);
    DEV_Delay_ms(100);
    DEV_Digital_Write(EPD_RST_PIN, 0);
    DEV_Delay_ms(2);
    DEV_Digital_Write(EPD_RST_PIN, 1);
    DEV_Delay_ms(100);
}

/******************************************************************************
function :	send command
parameter:
     Reg : Command register
******************************************************************************/
static void EPD_1IN54R_SendCommand(UBYTE Reg)
{
    DEV_Digital_Write(EPD_DC_PIN, 0);
    DEV_Digital_Write(EPD_CS_PIN, 0);
    DEV_SPI_WriteByte(Reg);
    DEV_Digital_Write(EPD_CS_PIN, 1);
}

/******************************************************************************
function :	send data
parameter:
    Data : Write data
******************************************************************************/
static void EPD_1IN54R_SendData(UBYTE Data)
{
    DEV_Digital_Write(EPD_DC_PIN, 1);
    DEV_Digital_Write(EPD_CS_PIN, 0);
    DEV_SPI_WriteByte(Data);
    DEV_Digital_Write(EPD_CS_PIN, 1);
}

/******************************************************************************
function :	Wait until the busy_pin goes LOW
parameter:
******************************************************************************/
static void EPD_1IN54R_ReadBusy(void)
{
    EPD_Busy_WaitUntil(1,0);
}

/******************************************************************************
function :	Set the look-up black and white tables
parameter:
******************************************************************************/
static void EPD_1IN54R_SetLutBw(void)
{
    UWORD count;
    EPD_1IN54R_SendCommand(0x20);// g vcom
    for(count = 0; count < 15; count++) {
        EPD_1IN54R_SendData(EPD_1IN54R_lut_vcom0[count]);
    }
    EPD_1IN54R_SendCommand(0x21);// g ww --
    for(count = 0; count < 15; count++) {
        EPD_1IN54R_SendData(EPD_1IN54R_lut_w[count]);
    }
    EPD_1IN54R_SendCommand(0x22);// g bw r
    for(count = 0; count < 15; count++) {
        EPD_1IN54R_SendData(EPD_1IN54R_lut_b[count]);
    }
    EPD_1IN54R_SendCommand(0x23);// g wb w
    for(count = 0; count < 15; count++) {
        EPD_1IN54R_SendData(EPD_1IN54R_lut_g1[count]);
    }
    EPD_1IN54R_SendCommand(0x24);// g bb b
    for(count = 0; count < 15; count++) {
        EPD_1IN54R_SendData(EPD_1IN54R_lut_g2[count]);
    }
}

/******************************************************************************
function :	Set the look-up red tables
parameter:
******************************************************************************/
static void EPD_1IN54R_SetLutRed(void)
{
    UWORD count;
    EPD_1IN54R_SendCommand(0x25);
    for(count = 0; count < 15; count++) {
        EPD_1IN54R_SendData(EPD_1IN54R_lut_vcom1[count]);
    }
    EPD_1IN54R_SendCommand(0x26);
    for(count = 0; count < 15; count++) {
        EPD_1IN54R_SendData(EPD_1IN54R_lut_red0[count]);
    }
    EPD_1IN54R_SendCommand(0x27);
    for(count = 0; count < 15; count++) {
        EPD_1IN54R_SendData(EPD_1IN54R_lut_red1[count]);
    }
}

/******************************************************************************
function :	Initialize the e-Paper register
parameter:
******************************************************************************/
void EPD_1IN54R_Init(UBYTE mode)
{
    EPD_1IN54R_Reset();

    EPD_1IN54R_SendCommand(0x01);// POWER_SETTING
    EPD_1IN54R_SendData(0x07);
    EPD_1IN54R_SendData(0x00);
    EPD_1IN54R_SendData(0x08);
    EPD_1IN54R_SendData(0x00);
    EPD_1IN54R_SendCommand(0x06);// BOOSTER_SOFT_START
    EPD_1IN54R_SendData(0x07);
    EPD_1IN54R_SendData(0x07);
    EPD_1IN54R_SendData(0x07);
    EPD_1IN54R_SendCommand(0x04);// POWER_ON

    EPD_1IN54R_ReadBusy();

    EPD_1IN54R_SendCommand(0X00);// PANEL_SETTING
    EPD_1IN54R_SendData(0xcf);
    EPD_1IN54R_SendCommand(0X50);// VCOM_AND_DATA_INTERVAL_SETTING
    EPD_1IN54R_SendData(0x37);// 0xF0
    EPD_1IN54R_SendCommand(0x30);// PLL_CONTROL
    EPD_1IN54R_SendData(0x39);
    EPD_1IN54R_SendCommand(0x61);// TCON_RESOLUTION set x and y
    EPD_1IN54R_SendData(0x98);// 152
    EPD_1IN54R_SendData(0x00);// y High eight: 0
    EPD_1IN54R_SendData(0x98);// y Low eight: 152
    EPD_1IN54R_SendCommand(0x82);// VCM_DC_SETTING_REGISTER
    EPD_1IN54R_SendData(0x0E);

    EPD_1IN54R_SetLutBw();
    EPD_1IN54R_SetLutRed();
}

/******************************************************************************
function :	Clear screen
parameter:
******************************************************************************/
void EPD_1IN54R_Clear(void)
{
    UWORD Width, Height;
    Width = (EPD_1IN54R_WIDTH % 8 == 0)? (EPD_1IN54R_WIDTH / 8 ): (EPD_1IN54R_WIDTH / 8 + 1);
    Height = EPD_1IN54R_HEIGHT;

    //send black data
    EPD_1IN54R_SendCommand(0x10);// DATA_START_TRANSMISSION_1
    DEV_Delay_ms(2);
    for(UWORD i = 0; i < Height; i++) {
        for(UWORD i = 0; i < Width; i++) {
            EPD_1IN54R_SendData(0xFF);
            EPD_1IN54R_SendData(0xFF);
        }
    }
    DEV_Delay_ms(2);

    //send red data
    EPD_1IN54R_SendCommand(0x13);// DATA_START_TRANSMISSION_2
    DEV_Delay_ms(2);
    for(UWORD i = 0; i < Height; i++) {
        for(UWORD i = 0; i < Width; i++) {
            EPD_1IN54R_SendData(0xFF);
        }
    }
    DEV_Delay_ms(2);

    EPD_1IN54R_SendCommand(0x12);// DISPLAY_REFRESH
    EPD_1IN54R_ReadBusy();
}

/******************************************************************************
function :	Sends the image buffer in RAM to e-Paper and displays
parameter:
******************************************************************************/
void EPD_1IN54R_Display(const UBYTE *blackimage, const UBYTE *redimage)
{
    UBYTE Temp = 0x00;
    UWORD Width, Height;
    Width = (EPD_1IN54R_WIDTH % 8 == 0)? (EPD_1IN54R_WIDTH / 8 ): (EPD_1IN54R_WIDTH / 8 + 1);
    Height = EPD_1IN54R_HEIGHT;

    EPD_1IN54R_SendCommand(0x10);// DATA_START_TRANSMISSION_1
    for (UWORD j = 0; j < Height; j++) {
        for (UWORD i = 0; i < Width; i++) {
            EPD_1IN54R_SendData(blackimage[i + j * Width]);
        }
    }
    DEV_Delay_ms(2);

    EPD_1IN54R_SendCommand(0x13);// DATA_START_TRANSMISSION_2
    for (UWORD j = 0; j < Height; j++) {
        for (UWORD i = 0; i < Width; i++) {
            EPD_1IN54R_SendData(redimage[i + j * Width]);
        }
    }
    DEV_Delay_ms(2);

    //Display refresh
    EPD_1IN54R_SendCommand(0x12);// DISPLAY_REFRESH
    EPD_1IN54R_ReadBusy();
}

/******************************************************************************
function :	Enter sleep mode
parameter:
******************************************************************************/
void EPD_1IN54R_Sleep(void)
{
	EPD_1IN54R_SendCommand(0x02);
	EPD_1IN54R_ReadBusy();  
    EPD_1IN54R_SendCommand(0x07); 
    EPD_1IN54R_SendData(0xa5);
}
