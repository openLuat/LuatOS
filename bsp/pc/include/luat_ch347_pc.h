#ifndef __LUAT_CH347_PC_H__
#define __LUAT_CH347_PC_H__

#include <stdint.h>
#include <stdbool.h>
#include <stddef.h>

#include "luat_base.h"
#include "luat_gpio.h"

#ifdef _WIN32
#include <windows.h>
#endif

#include "CH347DLL.H"

#ifdef _WIN32
#define CH347_DLL_NAME "CH347DLL.DLL"
#else
#define CH347_DLL_NAME "CH347DLL.DLL"  // 其他平台暂不支持
#endif

#ifdef _WIN32
extern uint16_t g_ch3470_DevIsOpened;                           // 设备是否已打开标志
extern uint16_t g_ch3470_SpiIsCfg;                              // SPI是否已配置标志
extern uint16_t g_ch3470_I2CIsCfg;                              // I2C是否已配置标志
extern uint32_t g_ch3470_SpiI2cGpioDevIndex;                    // 当前选中的SPI/I2C/GPIO设备索引号
extern mDeviceInforS g_ch3470_SpiI2cDevInfor[16];       // SPI/I2C设备信息数组，最多支持16个设备
extern uint16_t g_ch3470_EnablePnPAutoOpen;                     // 启用插拔后设备自动打开关闭功能

typedef struct _USB_DEVICE_DESCRIPTOR {
    uint8_t bLength;
    uint8_t bDescriptorType;
    uint16_t bcdUSB;
    uint8_t bDeviceClass;
    uint8_t bDeviceSubClass;
    uint8_t bDeviceProtocol;
    uint8_t bMaxPacketSize0;
    uint16_t idVendor;
    uint16_t idProduct;
    uint16_t bcdDevice;
    uint8_t iManufacturer;
    uint8_t iProduct;
    uint8_t iSerialNumber;
    uint8_t bNumConfigurations;
} USB_DEVICE_DESCRIPTOR, * PUSB_DEVICE_DESCRIPTOR;
#pragma pack()

// CH347函数指针类型定义
typedef HANDLE (WINAPI *PFN_CH347OpenDevice)(ULONG DevI);
typedef BOOL (WINAPI *PFN_CH347CloseDevice)(ULONG iIndex);
typedef BOOL (WINAPI *PFN_CH347GetDeviceInfor)(ULONG iIndex, mDeviceInforS *mDeviceInfor);
typedef BOOL (WINAPI *PFN_CH347GetVersion)(ULONG iIndex, PUCHAR iDriverVer, PUCHAR iDLLVer, PUCHAR ibcdDevice, PUCHAR iChipType);
typedef BOOL (WINAPI *PFN_CH347SetTimeout)(ULONG iIndex, ULONG iWriteTimeout, ULONG iReadTimeout);

typedef BOOL (WINAPI *PFN_CH347I2C_Set)(ULONG iIndex, ULONG iMode );
typedef BOOL (WINAPI *PFN_CH347StreamI2C)(ULONG iIndex, ULONG iWriteLength, PVOID iWriteBuffer, ULONG iReadLength, PVOID oReadBuffer );

typedef BOOL (WINAPI *PFN_CH347SPI_Init)(ULONG iIndex, mSpiCfgS *SpiCfg);
typedef BOOL (WINAPI *PFN_CH347SPI_SetFrequency)(ULONG iIndex, ULONG iSpiSpeedHz);
typedef BOOL (WINAPI *PFN_CH347SPI_SetDataBits)(ULONG iIndex, UCHAR iDataBits);
typedef BOOL (WINAPI *PFN_CH347SPI_WriteRead)(ULONG iIndex, ULONG iChipSelect, ULONG iLength, PVOID ioBuffer);
typedef BOOL (WINAPI *PFN_CH347SPI_Read)(ULONG iIndex, ULONG iChipSelect, ULONG oLength, PULONG iLength, PVOID ioBuffer);
typedef BOOL (WINAPI *PFN_CH347SPI_Write)(ULONG iIndex, ULONG iChipSelect, ULONG iLength, ULONG oLength, PVOID iBuffer);
typedef BOOL (WINAPI *PFN_CH347StreamSPI4)(ULONG iIndex, ULONG iChipSelect, ULONG iLength, PVOID ioBuffer);

typedef BOOL (WINAPI *PFN_CH347GPIO_Get)(ULONG iIndex, UCHAR *iDir, UCHAR *iData);
typedef BOOL (WINAPI *PFN_CH347GPIO_Set)(ULONG iIndex, UCHAR iEnable, UCHAR iSetDirOut, UCHAR iSetDataOut);


#endif

// 动态加载函数
int luat_load_ch347(int flag);

uint64_t luat_ch347Device();
uint16_t Luat_OpenDevice();

int luat_ch347_i2c_setup(int id, int speed);
int luat_ch347_i2c_send(int id, int addr, void* buff, size_t len, uint8_t stop);
int luat_ch347_i2c_recv(int id, int addr, void* buff, size_t len);
int luat_ch347_i2c_transfer(int id, int addr, uint8_t *reg, size_t reg_len, uint8_t *buff, size_t len);
int luat_ch347_i2c_no_block_transfer(int id, int addr, uint8_t is_read, uint8_t *reg, size_t reg_len, uint8_t *buff, size_t len, uint16_t Toms, void *CB, void *pParam);
int luat_ch347_i2c_close(int id);

int luat_ch347_spi_setup(int id, int CPHA, int CPOL, int dataw, int bit_dict, int banrate, int cs, int mode);
int luat_ch347_spi_transfer(int spi_id, const char* send_buf, size_t send_length, char* recv_buf, size_t recv_length);
int luat_ch347_spi_recv(int spi_id, char* recv_buf, size_t length);
int luat_ch347_spi_send(int spi_id, const char* send_buf, size_t length);
int luat_ch347_spi_change_speed(int spi_id, uint32_t speed);

int luat_ch347_gpio_setup(int pin, int mode, int pull, int irq);
int luat_ch347_gpio_set(int pin, int level);
int luat_ch347_gpio_get(int pin);

#endif // __LUAT_CH347_PC_H__
