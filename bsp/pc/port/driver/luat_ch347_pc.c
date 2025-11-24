#include "luat_base.h"
#ifdef LUAT_USE_WINDOWS
#include "luat_ch347_pc.h"

#include <stdio.h>
#include <string.h>
#include <stdlib.h>

#ifdef _WIN32
#include <windows.h>
#endif

#define LUAT_LOG_TAG "luat.ch347"
#include "luat_log.h"

#include "luat_gpio.h"
#include "luat_irq.h"

#ifdef _WIN32
uint16_t g_ch3470_DevIsOpened;                           // 设备是否已打开标志
uint16_t g_ch3470_SpiIsCfg;                              // SPI是否已配置标志
uint16_t g_ch3470_I2CIsCfg;                              // I2C是否已配置标志
uint32_t g_ch3470_SpiI2cGpioDevIndex;                    // 当前选中的SPI/I2C/GPIO设备索引号
mDeviceInforS g_ch3470_SpiI2cDevInfor[16] = { 0 };       // SPI/I2C设备信息数组，最多支持16个设备
uint16_t g_ch3470_EnablePnPAutoOpen;                     // 启用插拔后设备自动打开关闭功能
static uint16_t s_IntIsEnable = FALSE;                   // 中断使能标志
static uint16_t s_Gpiostatus = 0;                       // GPIO状态
static uint16_t s_Gpiovalues = 0;                        // GPIO值
static uint8_t s_Gpioflag = 0;                          // GPIO标志
static uint8_t s_SPIMode = 1;                          // SPI模式，1全双工，0半双工

// CH347函数指针
static PFN_CH347OpenDevice pfn_CH347OpenDevice = NULL;
static PFN_CH347CloseDevice pfn_CH347CloseDevice = NULL;
static PFN_CH347GetDeviceInfor pfn_CH347GetDeviceInfor = NULL;
static PFN_CH347GetVersion pfn_CH347GetVersion = NULL;
static PFN_CH347SetTimeout pfn_CH347SetTimeout = NULL;
static PFN_CH347I2C_Set pfn_CH347I2C_Set = NULL;
static PFN_CH347StreamI2C pfn_CH347StreamI2C = NULL;
static PFN_CH347SPI_Init pfn_CH347SPI_Init = NULL;
static PFN_CH347SPI_SetFrequency pfn_CH347SPI_SetFrequency = NULL;
static PFN_CH347SPI_SetDataBits pfn_CH347SPI_SetDataBits = NULL;
static PFN_CH347SPI_WriteRead pfn_CH347SPI_WriteRead = NULL;
static PFN_CH347SPI_Read pfn_CH347SPI_Read = NULL;
static PFN_CH347SPI_Write pfn_CH347SPI_Write = NULL;
static PFN_CH347StreamSPI4 pfn_CH347StreamSPI4 = NULL;
static PFN_CH347GPIO_Set pfn_CH347GPIO_Set = NULL;
static PFN_CH347GPIO_Get pfn_CH347GPIO_Get = NULL;

static HMODULE hCH347DLL = NULL;
#endif

int luat_load_ch347(int flag) {
#ifdef _WIN32
    hCH347DLL = LoadLibraryA(CH347_DLL_NAME);
    if(hCH347DLL == NULL) {
        LLOGD("not be load %s", CH347_DLL_NAME);
        return 0;
    }
    LLOGD("loaded %s", CH347_DLL_NAME);

    // 动态加载函数指针
    pfn_CH347OpenDevice = (PFN_CH347OpenDevice)GetProcAddress(hCH347DLL, "CH347OpenDevice");
    pfn_CH347CloseDevice = (PFN_CH347CloseDevice)GetProcAddress(hCH347DLL, "CH347CloseDevice");
    pfn_CH347GetDeviceInfor = (PFN_CH347GetDeviceInfor)GetProcAddress(hCH347DLL, "CH347GetDeviceInfor");
    pfn_CH347GetVersion = (PFN_CH347GetVersion)GetProcAddress(hCH347DLL, "CH347GetVersion");
    pfn_CH347SetTimeout = (PFN_CH347SetTimeout)GetProcAddress(hCH347DLL, "CH347SetTimeout");
    pfn_CH347I2C_Set = (PFN_CH347I2C_Set)GetProcAddress(hCH347DLL, "CH347I2C_Set");
    pfn_CH347StreamI2C = (PFN_CH347StreamI2C)GetProcAddress(hCH347DLL, "CH347StreamI2C");
    pfn_CH347SPI_Init = (PFN_CH347SPI_Init)GetProcAddress(hCH347DLL, "CH347SPI_Init");
    pfn_CH347SPI_SetFrequency = (PFN_CH347SPI_SetFrequency)GetProcAddress(hCH347DLL, "CH347SPI_SetFrequency");
    pfn_CH347SPI_SetDataBits = (PFN_CH347SPI_SetDataBits)GetProcAddress(hCH347DLL, "CH347SPI_SetDataBits");
    pfn_CH347SPI_WriteRead = (PFN_CH347SPI_WriteRead)GetProcAddress(hCH347DLL, "CH347SPI_WriteRead");
    pfn_CH347SPI_Read = (PFN_CH347SPI_Read)GetProcAddress(hCH347DLL, "CH347SPI_Read");
    pfn_CH347SPI_Write = (PFN_CH347SPI_Write)GetProcAddress(hCH347DLL, "CH347SPI_Write");
    pfn_CH347StreamSPI4 = (PFN_CH347StreamSPI4)GetProcAddress(hCH347DLL, "CH347StreamSPI4");
	pfn_CH347GPIO_Set = (PFN_CH347GPIO_Set)GetProcAddress(hCH347DLL, "CH347GPIO_Set");
	pfn_CH347GPIO_Get = (PFN_CH347GPIO_Get)GetProcAddress(hCH347DLL, "CH347GPIO_Get");

    if (luat_ch347Device() == 0) {
        LLOGD("no device found");
        return 0;
    }

    if (Luat_OpenDevice() == 0) {
        LLOGD("open device failed");
        return 0;
    }

    return 1;
#else
    LLOGD("not support non-windows platform");
    return 0;
#endif
}

uint64_t luat_ch347Device() {
#ifdef _WIN32
	uint64_t i, oLen, DevCnt = 0;
	int8_t tem[256] = "";
	mDeviceInforS DevInfor = { 0 };

	uint8_t iDriverVer = 0;
	uint8_t iDLLVer = 0;
	uint8_t ibcdDevice = 0;
	uint8_t iChipType = 0;

	for (i = 0; i < 16; i++)
	{
		if (pfn_CH347OpenDevice(i) != INVALID_HANDLE_VALUE)
		{
			oLen = sizeof(USB_DEVICE_DESCRIPTOR);
			pfn_CH347GetDeviceInfor(i, &DevInfor);

			LLOGD("M:%sP:%s", DevInfor.ManufacturerString, DevInfor.ProductString);//SN:%s\n

			sprintf_s(tem, sizeof(tem), "%llu# %s", (unsigned long long)i, DevInfor.FuncDescStr);
			memcpy(&g_ch3470_SpiI2cDevInfor[DevCnt], &DevInfor, sizeof(DevInfor));

			// 设置第一个找到的设备为默认设备
			if (DevCnt == 0) {
				g_ch3470_SpiI2cGpioDevIndex = (uint32_t)i;
			}
			DevCnt++;
			pfn_CH347GetVersion(i, &iDriverVer, &iDLLVer, &ibcdDevice, &iChipType);
			LLOGD("DV:%02x  DLLV:%02x BCD:%02x CT:%02x.", iDriverVer, iDLLVer, ibcdDevice, iChipType);
		}
		pfn_CH347CloseDevice(i);
	}
	return DevCnt;
#else
    LLOGD("not support non-windows platform");
    return 0;
#endif
}

uint16_t Luat_OpenDevice() {
#ifdef _WIN32
	g_ch3470_DevIsOpened = 0;	// 默认没有打开成功
	if (g_ch3470_SpiI2cGpioDevIndex == CB_ERR)
	{
		return 0;
	}

	g_ch3470_DevIsOpened = (pfn_CH347OpenDevice((ULONG)g_ch3470_SpiI2cGpioDevIndex) != INVALID_HANDLE_VALUE);
	if (g_ch3470_DevIsOpened) {
		pfn_CH347SetTimeout((ULONG)g_ch3470_SpiI2cGpioDevIndex, 500, 500);
		LLOGD("Open the device %s", g_ch3470_DevIsOpened ? "Success" : "Failed");
	} else {
		LLOGD("Open the device Failed");
	}

	return g_ch3470_DevIsOpened;
#else
    LLOGD("not support non-windows platform");
    return 0;
#endif
}

// ============== IIC ==============

int luat_ch347_i2c_setup(int id, int speed) {
#ifdef _WIN32
	if (id == 0) {
		int RetVal = 0;
		uint64_t iMode;	// I2C模式

		switch (speed) {
			case 20000 :
				iMode = 0; break; // 20KHz
			case 100000 :
				iMode = 1; break; // 100KHz
			case 400000 :
				iMode = 2; break; // 400KHz
			case 750000 :
				iMode = 3; break; // 750KHz
		}

		RetVal = pfn_CH347I2C_Set(g_ch3470_SpiI2cGpioDevIndex, iMode);
		return RetVal;
	}
	return 0;
#else
    LLOGD("not support non-windows platform");
    return 0;
#endif
}

int luat_ch347_i2c_send(int id, int addr, void* buff, size_t len, uint8_t stop) {
	(void)stop; // 避免未使用参数警告
#ifdef _WIN32
	if (id == 0) {
		int RetVal = 0;

		if (buff == NULL || len == 0) {
			return 0;
		}

		uint8_t* send_buffer = malloc(len + 1);
		if (send_buffer == NULL) {
			return 0;
		}

		send_buffer[0] = (addr << 1) | 0x00;
		memcpy(&send_buffer[1], buff, len);
		// 执行I2C读写操作
		RetVal = pfn_CH347StreamI2C(g_ch3470_SpiI2cGpioDevIndex, len + 1, send_buffer, 0, NULL);

		free(send_buffer);

		return RetVal;
	}
	return 0;
#else
    LLOGD("not support non-windows platform");
    return 0;
#endif
}

int luat_ch347_i2c_recv(int id, int addr, void* buff, size_t len) {
#ifdef _WIN32
	if (id == 0) {
		int RetVal = 0;
		if (buff == NULL || len == 0) {
			return 0;
		}
		uint8_t* recv_buffer = malloc(len + 1);
		if (recv_buffer == NULL) {
			return 0;
		}
		recv_buffer[0] = (addr << 1) | 0x01;
		// 执行I2C读写操作
		RetVal = pfn_CH347StreamI2C(g_ch3470_SpiI2cGpioDevIndex, 1, recv_buffer, len, &recv_buffer[1]);
		if (RetVal) {
			memcpy(buff, &recv_buffer[1], len);
		}
		free(recv_buffer);
		return RetVal;
	}
	return 0;
#else
    LLOGD("not support non-windows platform");
    return 0;
#endif
}

int luat_ch347_i2c_transfer(int id, int addr, uint8_t *reg, size_t reg_len, uint8_t *buff, size_t len) {
#ifdef _WIN32
	if (id == 0) {
		int RetVal = 0;
		if (reg == NULL || reg_len == 0 || buff == NULL || len == 0) {
			return 0;
		}
		uint8_t* transfer_buffer = malloc(reg_len + len + 2);
		if (transfer_buffer == NULL) {
			return 0;
		}
		transfer_buffer[0] = (addr << 1) | 0x00;
		memcpy(&transfer_buffer[1], reg, reg_len);
		transfer_buffer[reg_len + 1] = (addr << 1) | 0x01;
		memcpy(&transfer_buffer[reg_len + 2], buff, len);
		// 执行I2C读写操作
		RetVal = pfn_CH347StreamI2C(g_ch3470_SpiI2cGpioDevIndex, reg_len + len + 2, transfer_buffer, len, &transfer_buffer[reg_len + 1]);
		if (RetVal) {
			memcpy(buff, &transfer_buffer[reg_len + 1], len);
		}
		free(transfer_buffer);
		return RetVal;
	}
	return 0;
#else
    LLOGD("not support non-windows platform");
    return 0;
#endif
}

int luat_ch347_i2c_no_block_transfer(int id, int addr, uint8_t is_read, uint8_t *reg, size_t reg_len, uint8_t *buff, size_t len, uint16_t Toms, void *CB, void *pParam) {
	// 避免未使用参数警告
	(void)id; (void)addr; (void)is_read; (void)reg; (void)reg_len; (void)buff; (void)len; (void)Toms; (void)CB; (void)pParam;
	// 不支持非阻塞访问
	return 1;
}

int luat_ch347_i2c_close(int id) {
	(void)id; // 避免未使用参数警告
#ifdef _WIN32
	// CH347不需要关闭IIC
	return 1;
#else
	LLOGD("not support non-windows platform");
	return 0;
#endif
}

// ============== SPI ==============

int luat_ch347_spi_setup(int id, int CPHA, int CPOL, int dataw, int bit_dict, int banrate, int cs, int mode) {
	(void)bit_dict; (void)cs; // 避免未使用参数警告
#ifdef _WIN32
	if (id == 0) {
		int RetVal = 0;
		mSpiCfgS SpiCfg = { 0 };
		uint8_t HwVer = 1;
		int8_t  Frequency[32] = "";
		(void)HwVer; (void)Frequency; // 避免未使用变量警告
		uint64_t SpiFrequency = 0;
		uint8_t SpiDatabits = 0;

		s_SPIMode = mode;

		SpiCfg.iMode = 3;
		SpiCfg.iClock = 1;
		SpiCfg.iByteOrder = 1;
		SpiCfg.iChipSelect = 0x80;	// 80-CS0/81-CS1
		SpiCfg.iSpiWriteReadInterval = 0;
		SpiCfg.iSpiOutDefaultData = 0xFF;
		SpiCfg.CS1Polarity = 0;
		SpiCfg.CS2Polarity = 0;
		SpiCfg.iIsAutoDeativeCS = 0;
		SpiCfg.iActiveDelay = 0;
		SpiCfg.iDelayDeactive = 0;

		if (CPHA == 0 && CPOL == 0) SpiCfg.iMode = 0;
		else if (CPHA == 0 && CPOL == 1) SpiCfg.iMode = 1;
		else if (CPHA == 1 && CPOL == 0) SpiCfg.iMode = 2;
		else if (CPHA == 1 && CPOL == 1) SpiCfg.iMode = 3;

		if (bit_dict == 0) SpiCfg.iByteOrder = 0;

		SpiFrequency = banrate;
		SpiDatabits = 0;
		if(dataw == 16) SpiDatabits = 1;

		RetVal = pfn_CH347SPI_SetFrequency(g_ch3470_SpiI2cGpioDevIndex, SpiFrequency);

		RetVal = pfn_CH347SPI_SetDataBits(g_ch3470_SpiI2cGpioDevIndex, SpiDatabits);

		RetVal = pfn_CH347SPI_Init(g_ch3470_SpiI2cGpioDevIndex, &SpiCfg);
		if (RetVal == 0) {
			return 0;
		}
		return RetVal;
	}
	else {
		return 0;
	}
#else
    LLOGD("not support non-windows platform");
    return 0;
#endif
}

int luat_ch347_spi_transfer(int spi_id, const char* send_buf, size_t send_length, char* recv_buf, size_t recv_length) {
#ifdef _WIN32
	if(spi_id == 0) {
		BOOL RetVal = FALSE;
		UCHAR ChipSelect = 0x80;

		if (send_length > 0 && recv_length > 0) {
			if(s_SPIMode) {
				// 全双工
				memcpy(recv_buf, send_buf, send_length);
				RetVal = pfn_CH347StreamSPI4(g_ch3470_SpiI2cGpioDevIndex, ChipSelect, send_length, recv_buf);
				return RetVal ? (int)recv_length : 0;
			} else {
				// 半双工
				if (send_length > 0) {
					RetVal = pfn_CH347SPI_Write(g_ch3470_SpiI2cGpioDevIndex, ChipSelect, send_length, 512, (PVOID)send_buf);
				}
				if (recv_length > 0) {
					ULONG actual_length = recv_length;
					RetVal = pfn_CH347SPI_Read(g_ch3470_SpiI2cGpioDevIndex, ChipSelect, 0, &actual_length, recv_buf);
					return RetVal ? (int)actual_length : 0;
				}
			}
		} else if (send_length > 0) {
			RetVal = pfn_CH347SPI_Write(g_ch3470_SpiI2cGpioDevIndex, ChipSelect, send_length, 512, (PVOID)send_buf);
			return RetVal ? (int)send_length : 0;
		} else if (recv_length > 0) {
			ULONG actual_length = recv_length;
			RetVal = pfn_CH347SPI_Read(g_ch3470_SpiI2cGpioDevIndex, ChipSelect, 0, &actual_length, recv_buf);
			return RetVal ? (int)actual_length : 0;
		}
		return 0;
	}
	return 0;
#else
    return 0;
#endif
}

int luat_ch347_spi_recv(int spi_id, char* recv_buf, size_t length) {
#ifdef _WIN32
	if(spi_id == 0) {
		BOOL RetVal = FALSE;
		UCHAR ChipSelect = 0x80;
		ULONG actual_length = length;

		RetVal = pfn_CH347SPI_Read(g_ch3470_SpiI2cGpioDevIndex, ChipSelect, 0, &actual_length, recv_buf);
		return RetVal ? (int)actual_length : 0;
	}
	return 0;
#else
    return 0;
#endif
}

int luat_ch347_spi_send(int spi_id, const char* send_buf, size_t length) {
#ifdef _WIN32
	if(spi_id == 0) {
		BOOL RetVal = FALSE;
		UCHAR ChipSelect = 0x80;

		RetVal = pfn_CH347SPI_Write(g_ch3470_SpiI2cGpioDevIndex, ChipSelect, length, 0, (PVOID)send_buf);
		return RetVal ? (int)length : 0;
	}
	return 0;
#else
    return 0;
#endif
}

int luat_ch347_spi_change_speed(int spi_id, uint32_t speed) {
#ifdef _WIN32
	if(spi_id == 0) {
		BOOL RetVal = FALSE;

		RetVal = pfn_CH347SPI_SetFrequency(g_ch3470_SpiI2cGpioDevIndex, speed);
		return RetVal ? 1 : 0;
	}
	return 0;
#else
    return 0;
#endif
}

// ============== GPIO ==============

int luat_ch347_gpio_setup(int pin, int mode, int pull, int irq) {
#ifdef _WIN32
	if(pin >=0 && pin <= 7) {
		if(((s_Gpiostatus & 0x8000) == 0) || ((s_Gpiovalues & 0x8000) == 0)) { // 最高位为0，表示未初始化
			luat_ch347_gpio_get(-1);
		}
		s_Gpioflag |= (1 << pin);

		// 设置GPIO模式
		if(mode == 0)  // 输出模式
			s_Gpiostatus |= (1 << pin);
		else           // 输入模式
			s_Gpiostatus &= ~(1 << pin);

		pfn_CH347GPIO_Set(g_ch3470_SpiI2cGpioDevIndex, s_Gpioflag,  (uint8_t)(s_Gpiostatus & 0x00FF), (uint8_t)(s_Gpiovalues & 0x00FF));
	} else {
		LLOGD("only support GPIO0~7");
		return 0;
	}
#else
	LLOGD("not support non-windows platform");
	return 0;
#endif
}

int luat_ch347_gpio_set(int pin, int level) {
#ifdef _WIN32
	if(pin >=0 && pin <= 7) {
		if(((s_Gpiostatus & 0x8000) == 0) || ((s_Gpiovalues & 0x8000) == 0)) { // 最高位为0，表示未初始化
			luat_ch347_gpio_get(-1);
		}
		if(level)
			s_Gpiovalues |= (1 << pin);
		else
			s_Gpiovalues &= ~(1 << pin);
		pfn_CH347GPIO_Set(g_ch3470_SpiI2cGpioDevIndex, s_Gpioflag,  (uint8_t)(s_Gpiostatus & 0x00FF), (uint8_t)(s_Gpiovalues & 0x00FF));
	} else {
		LLOGD("only support GPIO0~7");
		return 0;
	}
#else
	LLOGD("not support non-windows platform");
	return 0;
#endif
}

int luat_ch347_gpio_get(int pin) {
#ifdef _WIN32
	uint8_t i = 0, iDir = 0, iData = 0;
	pfn_CH347GPIO_Get(g_ch3470_SpiI2cGpioDevIndex, &iDir, &iData);
	s_Gpiostatus |= 0x8000 | (uint16_t)iDir;
	s_Gpiovalues |= 0x8000 | (uint16_t)iData;

	if(pin >=0 && pin <= 7) {
		return (iData >> pin) & 0x01;
	} else
		return 1;

#else
	LLOGD("not support non-windows platform");
	return 0;
#endif
}

void luat_ch347_gpio_close(int pin) {
#ifdef _WIN32
	if(pin >=0 && pin <= 7)
		s_Gpioflag &= !(1 << pin);
#else
	LLOGD("not support non-windows platform");
	return 0;
#endif
}

#endif
