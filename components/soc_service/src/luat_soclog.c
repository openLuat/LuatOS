
#include "luat_base.h"
#include "luat_soc_service.h"
#include <stdarg.h>

#undef DBG
#define DBG(...)
#define DBG_LOG(X,Y...) soc_printf("%s %d:"X, __FUNCTION__,__LINE__,##Y)
#define SOC_PACK_FLAG		(0xA5)
#define SOC_PACK_CODE		(0xA6)
#define SOC_PACK_CODE_MASK	(0x03)
#define SOC_PACK_CODE_F1	(0x01)
#define SOC_PACK_CODE_F2	(0x02)
#define DUMP_DATA_BLOCK_CNT	(2)

#define JTT_PACK_FLAG		(0x7e)
#define JTT_PACK_CODE		(0x7d)
#define JTT_PACK_CODE_F1	(0x02)
#define JTT_PACK_CODE_F2	(0x01)

typedef enum SOC_LOG_TYPE
{
	SOC_LOG_TYPE_COMMON = 0,
	SOC_LOG_TYPE_BK,
	SOC_LOG_TYPE_RAMDUMP,
}SOC_LOG_TYPE_E;

#ifndef __CORE_FUNC_IN_RAM__
#define __CORE_FUNC_IN_RAM__ 
#endif

typedef struct
{
	uint64_t level:8;
	uint64_t tag0:7;
	uint64_t tag1:7;
	uint64_t tag2:7;
	uint64_t tag3:7;
	uint64_t tag4:7;
	uint64_t tag5:7;
	uint64_t tag6:7;
	uint64_t tag7:7;
}tag_param_t;

typedef struct
{
	uint64_t ms;
	tag_param_t tag;
	uint32_t cmd;
	uint16_t sn;
	uint8_t type;
	uint8_t cpu;
}soc_log_head_t;

typedef struct
{
	uint64_t ms;
	uint32_t address;
	uint32_t len;
	uint32_t cmd;
	uint16_t sn;
	uint8_t type;
	uint8_t cpu;
}soc_cmd_head_t;

static const uint16_t soc_log_crc_table[256] = {
	0x0000, 0xC0C1, 0xC181, 0x0140, 0xC301, 0x03C0, 0x0280, 0xC241,
	0xC601, 0x06C0, 0x0780, 0xC741, 0x0500, 0xC5C1, 0xC481, 0x0440,
	0xCC01, 0x0CC0, 0x0D80, 0xCD41, 0x0F00, 0xCFC1, 0xCE81, 0x0E40,
	0x0A00, 0xCAC1, 0xCB81, 0x0B40, 0xC901, 0x09C0, 0x0880, 0xC841,
	0xD801, 0x18C0, 0x1980, 0xD941, 0x1B00, 0xDBC1, 0xDA81, 0x1A40,
	0x1E00, 0xDEC1, 0xDF81, 0x1F40, 0xDD01, 0x1DC0, 0x1C80, 0xDC41,
	0x1400, 0xD4C1, 0xD581, 0x1540, 0xD701, 0x17C0, 0x1680, 0xD641,
	0xD201, 0x12C0, 0x1380, 0xD341, 0x1100, 0xD1C1, 0xD081, 0x1040,
	0xF001, 0x30C0, 0x3180, 0xF141, 0x3300, 0xF3C1, 0xF281, 0x3240,
	0x3600, 0xF6C1, 0xF781, 0x3740, 0xF501, 0x35C0, 0x3480, 0xF441,
	0x3C00, 0xFCC1, 0xFD81, 0x3D40, 0xFF01, 0x3FC0, 0x3E80, 0xFE41,
	0xFA01, 0x3AC0, 0x3B80, 0xFB41, 0x3900, 0xF9C1, 0xF881, 0x3840,
	0x2800, 0xE8C1, 0xE981, 0x2940, 0xEB01, 0x2BC0, 0x2A80, 0xEA41,
	0xEE01, 0x2EC0, 0x2F80, 0xEF41, 0x2D00, 0xEDC1, 0xEC81, 0x2C40,
	0xE401, 0x24C0, 0x2580, 0xE541, 0x2700, 0xE7C1, 0xE681, 0x2640,
	0x2200, 0xE2C1, 0xE381, 0x2340, 0xE101, 0x21C0, 0x2080, 0xE041,
	0xA001, 0x60C0, 0x6180, 0xA141, 0x6300, 0xA3C1, 0xA281, 0x6240,
	0x6600, 0xA6C1, 0xA781, 0x6740, 0xA501, 0x65C0, 0x6480, 0xA441,
	0x6C00, 0xACC1, 0xAD81, 0x6D40, 0xAF01, 0x6FC0, 0x6E80, 0xAE41,
	0xAA01, 0x6AC0, 0x6B80, 0xAB41, 0x6900, 0xA9C1, 0xA881, 0x6840,
	0x7800, 0xB8C1, 0xB981, 0x7940, 0xBB01, 0x7BC0, 0x7A80, 0xBA41,
	0xBE01, 0x7EC0, 0x7F80, 0xBF41, 0x7D00, 0xBDC1, 0xBC81, 0x7C40,
	0xB401, 0x74C0, 0x7580, 0xB541, 0x7700, 0xB7C1, 0xB681, 0x7640,
	0x7200, 0xB2C1, 0xB381, 0x7340, 0xB101, 0x71C0, 0x7080, 0xB041,
	0x5000, 0x90C1, 0x9181, 0x5140, 0x9301, 0x53C0, 0x5280, 0x9241,
	0x9601, 0x56C0, 0x5780, 0x9741, 0x5500, 0x95C1, 0x9481, 0x5440,
	0x9C01, 0x5CC0, 0x5D80, 0x9D41, 0x5F00, 0x9FC1, 0x9E81, 0x5E40,
	0x5A00, 0x9AC1, 0x9B81, 0x5B40, 0x9901, 0x59C0, 0x5880, 0x9841,
	0x8801, 0x48C0, 0x4980, 0x8941, 0x4B00, 0x8BC1, 0x8A81, 0x4A40,
	0x4E00, 0x8EC1, 0x8F81, 0x4F40, 0x8D01, 0x4DC0, 0x4C80, 0x8C41,
	0x4400, 0x84C1, 0x8581, 0x4540, 0x8701, 0x47C0, 0x4680, 0x8641,
	0x8201, 0x42C0, 0x4380, 0x8341, 0x4100, 0x81C1, 0x8081, 0x4040 };


enum {


    PRINT_HFSR_VECTBL,
    PRINT_MFSR_IACCVIOL,
    PRINT_MFSR_DACCVIOL,
    PRINT_MFSR_MUNSTKERR,
    PRINT_MFSR_MSTKERR,
    PRINT_MFSR_MLSPERR,
    PRINT_BFSR_IBUSERR,
    PRINT_BFSR_PRECISERR,
    PRINT_BFSR_IMPREISERR,
    PRINT_BFSR_UNSTKERR,
    PRINT_BFSR_STKERR,
    PRINT_BFSR_LSPERR,
    PRINT_UFSR_UNDEFINSTR,
    PRINT_UFSR_INVSTATE,
    PRINT_UFSR_INVPC,
    PRINT_UFSR_NOCP,
#if (__CORTEX_M == 33)
    PRINT_UFSR_STKOF,
#endif
    PRINT_UFSR_UNALIGNED,
    PRINT_UFSR_DIVBYZERO0,
    PRINT_DFSR_HALTED,
    PRINT_DFSR_BKPT,
    PRINT_DFSR_DWTTRAP,
    PRINT_DFSR_VCATCH,
    PRINT_DFSR_EXTERNAL,

};

// static const char * const print_info[] = {
// 	[PRINT_HFSR_VECTBL]           = "发生硬错误，原因：取中断向量时出错",
// 	[PRINT_MFSR_IACCVIOL]         = "发生存储器管理错误，原因：企图从不允许访问的区域取指令",
// 	[PRINT_MFSR_DACCVIOL]         = "发生存储器管理错误，原因：企图从不允许访问的区域读、写数据",
// 	[PRINT_MFSR_MUNSTKERR]        = "发生存储器管理错误，原因：出栈时企图访问不被允许的区域",
// 	[PRINT_MFSR_MSTKERR]          = "发生存储器管理错误，原因：入栈时企图访问不被允许的区域",
// 	[PRINT_MFSR_MLSPERR]          = "发生存储器管理错误，原因：惰性保存浮点状态时发生错误",
// 	[PRINT_BFSR_IBUSERR]          = "发生总线错误，原因：指令总线错误",
// 	[PRINT_BFSR_PRECISERR]        = "发生总线错误，原因：精确的数据总线错误",
// 	[PRINT_BFSR_IMPREISERR]       = "发生总线错误，原因：不精确的数据总线错误",
// 	[PRINT_BFSR_UNSTKERR]         = "发生总线错误，原因：出栈时发生错误",
// 	[PRINT_BFSR_STKERR]           = "发生总线错误，原因：入栈时发生错误",
// 	[PRINT_BFSR_LSPERR]           = "发生总线错误，原因：惰性保存浮点状态时发生错误",
// 	[PRINT_UFSR_UNDEFINSTR]       = "发生用法错误，原因：企图执行未定义指令",
// 	[PRINT_UFSR_INVSTATE]         = "发生用法错误，原因：试图切换到 ARM 状态",
// 	[PRINT_UFSR_INVPC]            = "发生用法错误，原因：无效的异常返回码",
// 	[PRINT_UFSR_NOCP]             = "发生用法错误，原因：企图执行协处理器指令",
// #if (__CORTEX_M == 33)
// 	[PRINT_UFSR_STKOF]        	  = "发生用法错误，原因：硬件检测到栈溢出",
// #endif
// 	[PRINT_UFSR_UNALIGNED]        = "发生用法错误，原因：企图执行非对齐访问",
// 	[PRINT_UFSR_DIVBYZERO0]       = "发生用法错误，原因：企图执行除 0 操作",
// 	[PRINT_DFSR_HALTED]           = "发生调试错误，原因：NVIC 停机请求",
// 	[PRINT_DFSR_BKPT]             = "发生调试错误，原因：执行 BKPT 指令",
// 	[PRINT_DFSR_DWTTRAP]          = "发生调试错误，原因：数据监测点匹配",
// 	[PRINT_DFSR_VCATCH]           = "发生调试错误，原因：发生向量捕获",
// 	[PRINT_DFSR_EXTERNAL]         = "发生调试错误，原因：外部调试请求",

// };

static const char *gLogNullString = "(null)";
#define SOC_ALIGN_UP(v, n) (((unsigned long)(v) + (n)-1) & ~((n)-1))

typedef struct
{
    uint32_t ptr; ///< buffer pointer
    uint32_t size; ///< buffer size
}soc_log_buf_t;

#define SOC_FMT_INT_MAY_LL(cc) (cc == 'd' || cc == 'i' || cc == 'o' || cc == 'u' || cc == 'x' || cc == 'X')
#define SOC_FMT_INT_NOT_LL(cc) (cc == 'c' || cc == 'p')
#define SOC_FMT_DOUBLE(cc) (cc == 'e' || cc == 'E' || cc == 'f' || cc == 'F' || cc == 'g' || cc == 'G' || cc == 'a' || cc == 'A')

typedef struct
{
	uint64_t cpu_ticks;
    uint64_t log_sn;
	uint8_t log_mode;
	uint8_t is_inited;
    uint8_t tx_buffer[4096];
}soc_log_ctrl_t;

static soc_log_ctrl_t prv_log;

void soc_log_init(void)
{
	if (prv_log.is_inited) return;

    prv_log.log_mode = 1;
	prv_log.is_inited = 1;
}



uint64_t soc_get_poweron_time_ms(void) {
    extern uint64_t luat_mcu_tick64_ms(void);
    return luat_mcu_tick64_ms();
}

uint8_t luat_mcu_get_cpu_id(void);
#if 0
void am_print_base_info(void)
{
	uint8_t power_on_reason = soc_get_power_on_reason();
	LTIO("soc poweron: %d %s_%s_%s 0", power_on_reason, soc_get_sdk_type(), soc_get_sdk_version(), soc_get_chip_name());
	LTIO("BASEINFO: %s %s_%s_%s", "0000000000000000", soc_get_sdk_type(), soc_get_sdk_version(), soc_get_chip_name());
}
#endif

typedef void (*log_out_func)(uint8_t *data, uint32_t len);
__CORE_FUNC_IN_RAM__ static void prv_check_param_cnt(const char *fmt, uint32_t *count, uint32_t *size)
{
	uint32_t cnt = 0;
	uint32_t len = 0;
    for (;;)
    {
        char c = *fmt++;
        if (c == '\0')
            break;
        if (c != '%')
            continue;

        for (;;)
        {
            char cc = *fmt++;
            if (SOC_FMT_INT_MAY_LL(cc))
            {
				cnt += 1;
                if (fmt[-2] == 'l' && fmt[-3] == 'l')
                	len += 8;
                else
                	len += 4;
                break;
            }
            else if (SOC_FMT_INT_NOT_LL(cc))
            {
            	cnt += 1;
                len += 4;
                break;
            }
            else if (SOC_FMT_DOUBLE(cc))
            {
            	cnt += 1;
            	len += 8;
                break;
            }
            else if (cc == 's' || cc == 'S')
            {
                if (fmt[-2] == '*')
                {
                	cnt += 2;
                	len += 8;
                }
                else
                {
                	cnt += 1;
                }
                break;
            }
            else if (cc == '%')
            {
                break;
            }
            else if (cc == '\0')
            {
                break;
            }
            else
            {
                continue;
            }
        }
    }
    *count = (cnt + 2);
    *size = len;
}

/**
 * buffer description for 32bits parameter
 */
#define PUT_PARAM32                          \
    do                                       \
    {                                        \
        uint32_t val = va_arg(ap, uint32_t); \
        bufs->ptr = (uintptr_t)bufdata;      \
        bufs->size = 4;                      \
        dlen += bufs->size;                  \
        bufs++;                              \
        *bufdata++ = val;                    \
    } while (0)

/**
 * buffer description for 64bits parameter
 */
#define PUT_PARAM64                          \
    do                                       \
    {                                        \
        uint64_t val = va_arg(ap, uint64_t); \
        bufs->ptr = (uintptr_t)bufdata;      \
        bufs->size = 8;                      \
        dlen += bufs->size;                  \
        bufs++;                              \
        *bufdata++ = val & 0xffffffff;       \
        *bufdata++ = val >> 32;              \
    } while (0)

/**
 * buffer description for string parameter
 */
#define PUT_PARAMS                                  \
    do                                              \
    {                                               \
        const char *str = va_arg(ap, const char *); \
        if (str == NULL)                            \
            str = gLogNullString;                   \
        unsigned slen = strlen(str);                \
        bufs->ptr = (uintptr_t)str;                 \
        bufs->size = SOC_ALIGN_UP(slen + 1, 4);     \
        dlen += bufs->size;                         \
        bufs++;                                     \
    } while (0)

#define PUT_PARAMM                                        \
    do                                                    \
    {                                                     \
        unsigned size = va_arg(ap, uint32_t);             \
        const char *mem = va_arg(ap, const char *); \
        if (mem == NULL)                                  \
		{												  \
            mem = gLogNullString;                         \
            size = 6;                                     \
		}                                                 \
        bufs->ptr = (uintptr_t)bufdata;                   \
        bufs->size = 8;                                   \
        dlen += bufs->size;                               \
        bufs++;                                           \
        *bufdata++ = (unsigned)mem;                       \
        *bufdata++ = size;                                \
        bufs->ptr = (uintptr_t)mem;                       \
        bufs->size = SOC_ALIGN_UP(size, 4);       		  \
        dlen += bufs->size;                               \
        bufs++;                                           \
    } while (0)

__CORE_FUNC_IN_RAM__ static unsigned prv_set_param(const char *fmt, soc_log_buf_t *bufs, uint32_t *bufdata, va_list ap)
{
    unsigned dlen = 0;
    for (;;)
    {
        char c = *fmt++;
        if (c == '\0')
            break;
        if (c != '%')
            continue;

        for (;;)
        {
            char cc = *fmt++;
            if (SOC_FMT_INT_MAY_LL(cc))
            {
                if (fmt[-2] == 'l' && fmt[-3] == 'l')
                    PUT_PARAM64;
                else
                    PUT_PARAM32;
                break;
            }
            else if (SOC_FMT_INT_NOT_LL(cc))
            {
                PUT_PARAM32;
                break;
            }
            else if (SOC_FMT_DOUBLE(cc))
            {
                PUT_PARAM64;
                break;
            }
            else if (cc == 's' || cc == 'S')
            {
                if (fmt[-2] == '*')
                    PUT_PARAMM;
                else
                    PUT_PARAMS;
                break;
            }
            else if (cc == '%')
            {
                break;
            }
            else if (cc == '\0')
            {
                break;
            }
            else
            {
                continue;
            }
        }
    }
    return dlen;
}

#if 1
__CORE_FUNC_IN_RAM__ static void prv_make_log_packet(soc_log_buf_t *bufs, uint32_t count, log_out_func cb)
{
	uint16_t crc_start = 0;
	uint8_t xor = 0;
	uint8_t crc[2];
	uint8_t *temp = prv_log.tx_buffer;
	uint8_t pos = 0;
	temp[pos] = SOC_PACK_FLAG;
	pos++;
    for (uint32_t n = 0; n < count; n++, bufs++)
    {
        const char *psdata = (const char *)bufs->ptr;
        const char *pedata = psdata + bufs->size;
        while (psdata < pedata)
        {
            uint8_t ch = *psdata++;
    		xor = ch ^ crc_start;
    		crc_start >>= 8;
    		crc_start ^= soc_log_crc_table[xor];
            if ((ch == SOC_PACK_FLAG) || (ch == SOC_PACK_CODE))
            {
            	temp[pos] = SOC_PACK_CODE;
            	temp[pos+1] = ch & SOC_PACK_CODE_MASK;
            	pos += 2;
            }
            else
            {
            	temp[pos] = ch;
            	pos += 1;
            }
            if (pos >= 120)
            {
            	cb(temp, pos);
            	pos = 0;
            }
        }
    }
    crc[0] = crc_start & 0x00ff;
    crc[1] = crc_start >> 8;
    for (int i = 0; i < 2; i++)
    {
        if ((crc[i] == SOC_PACK_FLAG) || (crc[i] == SOC_PACK_CODE))
        {
        	temp[pos] = SOC_PACK_CODE;
        	temp[pos+1] = crc[i] & SOC_PACK_CODE_MASK;
        	pos += 2;
        }
        else
        {
        	temp[pos] = crc[i];
        	pos += 1;
        }
    }
    temp[pos] = SOC_PACK_FLAG;
    pos++;
    cb(temp, pos);
}
#else
__CORE_FUNC_IN_RAM__ static void prv_make_log_packet(soc_log_buf_t *bufs, uint32_t count, log_out_func cb)
{
	uint8_t temp[256] = {0};
	uint8_t pos = 0;
	temp[pos] = JTT_PACK_FLAG;
	pos++;
    for (uint32_t n = 0; n < count; n++, bufs++)
    {
        const char *psdata = (const char *)bufs->ptr;
        const char *pedata = psdata + bufs->size;
        while (psdata < pedata)
        {
            uint8_t ch = *psdata++;
            if ((ch == JTT_PACK_FLAG) || (ch == JTT_PACK_CODE))
            {
            	temp[pos] = JTT_PACK_CODE;
            	temp[pos+1] = (ch == JTT_PACK_FLAG)?JTT_PACK_CODE_F1:JTT_PACK_CODE_F2;
            	pos += 2;
            }
            else
            {
            	temp[pos] = ch;
            	pos += 1;
            }
            if (pos >= 120)
            {
            	// OS_WriteFifo(&g_s_sys.log_fifo, temp, pos);
                cb(temp, pos);
            	pos = 0;
            }
        }
    }
    temp[pos] = JTT_PACK_FLAG;
    pos++;
    // OS_WriteFifo(&g_s_sys.log_fifo, temp, pos);
    cb(temp, pos);
}
#endif


__CORE_FUNC_IN_RAM__ void am_make_log(int level, const char *tag, const char *fmt, va_list ap, uint8_t add_end, uint32_t out_len)
{

	soc_log_head_t header = {0};
	header.ms = soc_get_poweron_time_ms();
	header.cpu = luat_mcu_get_cpu_id();
	header.tag.level = level;
	if (tag)
	{
		header.tag.tag0 = tag[0];
		header.tag.tag1 = tag[1];
		header.tag.tag2 = tag[2];
		header.tag.tag3 = tag[3];
		header.tag.tag4 = tag[4];
		header.tag.tag5 = tag[5];
		header.tag.tag6 = tag[6];
		header.tag.tag7 = tag[7];
	}
	header.type = SOC_LOG_TYPE_COMMON;
	uint32_t fmt_len_aligned;
	uint32_t dlen;
	soc_log_buf_t bufs[24];
	uint32_t count, size;
	uint32_t bufdata[32];

	if (!out_len)
	{
		uint32_t fmt_len = 0;
		if (fmt)
		{
			while(fmt[fmt_len])
			{
				fmt_len++;
				if (fmt_len > 256)
				{
			    	prv_log.log_sn++;
			    	return;
				}
			}
		}

		fmt_len_aligned = SOC_ALIGN_UP(fmt_len + 1, 4);
	    prv_check_param_cnt(fmt, &count, &size);
	    if (count > 24 || size > sizeof(bufdata))
	    {
	    	prv_log.log_sn++;
	    	return;
	    }
	    bufs[0].ptr = (uintptr_t)&header;
	    bufs[0].size = sizeof(header);
	    bufs[1].ptr = (uintptr_t)fmt;
	    bufs[1].size = fmt_len_aligned;
	    dlen = prv_set_param(fmt, &bufs[2], bufdata, ap);
	}
	else
	{
		count = 2;
		fmt_len_aligned = 0;
		dlen = SOC_ALIGN_UP(out_len + 1, 4);
	    bufs[0].ptr = (uintptr_t)&header;
	    bufs[0].size = sizeof(header);
	    bufs[1].ptr = (uintptr_t)fmt;
	    bufs[1].size = dlen;
	}

    // if (soc_log_need_cache())
    #if 0
    {
        unsigned critical = os_enter_critical();
        prv_log.log_sn++;
        header.sn = prv_log.log_sn;
        if (soc_log_cache_space() >= (sizeof(header) * 2 + fmt_len_aligned + 2 * dlen))
        {
        	prv_make_log_packet(bufs, count, soc_log_to_buffer);
        }
        os_exit_critical(critical);
        am_log_out();
    }
    else
    #endif
    {
    	prv_log.log_sn++;
    	header.sn = prv_log.log_sn;
    	prv_make_log_packet(bufs, count, soc_log_to_device);
    }
}

__CORE_FUNC_IN_RAM__ void soc_vprintf_with_tags(const char *tags, const char *fmt, va_list ap)
{
    am_make_log(0, tags, fmt, ap, 1, 0);
}

__CORE_FUNC_IN_RAM__ void soc_printf(const char *fmt, ...)
{
	va_list args;
	va_start(args, fmt);
    soc_vprintf_with_tags("CAPP", fmt, args);
	va_end(args);
}

void soc_printf_with_tags(const char * tags, const char *fmt, ...)
{
	va_list args;
	va_start(args, fmt);
    soc_vprintf_with_tags(tags, fmt, args);
	va_end(args);
}

__CORE_FUNC_IN_RAM__ void soc_vsprintf(const char *fmt, va_list ap)
{
    soc_vprintf_with_tags("LTOS", fmt, ap);
}

void soc_info(const char *fmt, ...)
{
	va_list args;
	va_start(args, fmt);
    soc_vprintf_with_tags("LTIF", fmt, args);
	va_end(args);
}

void soc_debug_out(char *string, uint32_t size)
{
	va_list args;
	am_make_log(0, "LTOS", string, args, 1, size);
}

// int	__wrap_printf (const char *fmt, ...)
// {
// 	va_list args;
// 	va_start(args, fmt);
// 	am_make_log(0, "CAPP", fmt, args, 1, 0);
// 	va_end(args);
// 	return 1;
// }

void soc_dump(void *data, uint32_t size)
{
	soc_printf("%*s", size, (char *)data);
}
