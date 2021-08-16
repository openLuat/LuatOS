/*
 * This file is part of the CmBacktrace Library.
 *
 * Copyright (c) 2016-2018, zylx, <1346773219@qq.com>
 *
 * Permission is hereby granted, free of charge, to any person obtaining
 * a copy of this software and associated documentation files (the
 * 'Software'), to deal in the Software without restriction, including
 * without limitation the rights to use, copy, modify, merge, publish,
 * distribute, sublicense, and/or sell copies of the Software, and to
 * permit persons to whom the Software is furnished to do so, subject to
 * the following conditions:
 *
 * The above copyright notice and this permission notice shall be
 * included in all copies or substantial portions of the Software.
 *
 * THE SOFTWARE IS PROVIDED 'AS IS', WITHOUT WARRANTY OF ANY KIND,
 * EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
 * MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT.
 * IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY
 * CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT,
 * TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE
 * SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
 *
 * Function: Initialize function and other general function.
 * Created on: 2016-12-15
 */
#include <rtthread.h>
#include <rthw.h>
#include <cm_backtrace.h>
#include <string.h>

#if defined(__CC_ARM)
    #pragma O1
#elif defined(__ICCARM__)
    #pragma optimize=none
#elif defined(__GNUC__)
    #pragma GCC optimize ("O0")
#endif

#if defined(__CC_ARM)
    static __inline __asm void cmb_set_psp(uint32_t psp) {
        msr psp, r0
        bx lr
    }
#elif defined(__ICCARM__)
/* IAR iccarm specific functions */
/* Close Raw Asm Code Warning */
#pragma diag_suppress=Pe940
    static void cmb_set_psp(uint32_t psp)
    {
      __asm("msr psp, r0");
      __asm("bx lr");
    }
#pragma diag_default=Pe940
#elif defined(__GNUC__)
    __attribute__( ( always_inline ) ) static inline void cmb_set_psp(uint32_t psp) {
        __asm volatile ("MSR psp, %0\n\t" :: "r" (psp) );
    }
#else
    #error "not supported compiler"
#endif

RT_WEAK rt_err_t exception_hook(void *context) {
    volatile uint8_t _continue = 1;
    uint8_t lr_offset = 0;
    uint32_t lr;

#define CMB_LR_WORD_OFFSET_START       6
#define CMB_LR_WORD_OFFSET_END         20
#define CMB_SP_WORD_OFFSET             (lr_offset + 1)

#if (CMB_CPU_PLATFORM_TYPE == CMB_CPU_ARM_CORTEX_M0) || (CMB_CPU_PLATFORM_TYPE == CMB_CPU_ARM_CORTEX_M3)
#define EXC_RETURN_MASK                0x0000000F // Bits[31:4]
#else
#define EXC_RETURN_MASK                0x0000000F // Bits[31:5]
#endif
        
    rt_enter_critical();

#ifdef RT_USING_FINSH
    extern long list_thread(void);
    list_thread();
#endif

    /* the PSP is changed by RT-Thread HardFault_Handler, so restore it to HardFault context */
#if (defined (__VFP_FP__) && !defined(__SOFTFP__)) || (defined (__ARMVFP__)) || (defined(__ARM_PCS_VFP) || defined(__TARGET_FPU_VFP))
    cmb_set_psp(cmb_get_psp() + 4 * 10);
#else
    cmb_set_psp(cmb_get_psp() + 4 * 9);
#endif

    /* auto calculate the LR offset */
    for (lr_offset = CMB_LR_WORD_OFFSET_START; lr_offset <= CMB_LR_WORD_OFFSET_END; lr_offset ++)
    {
        lr = *((uint32_t *)(cmb_get_sp() + sizeof(uint32_t) * lr_offset));
        /*
         * Cortex-M0: http://infocenter.arm.com/help/index.jsp?topic=/com.arm.doc.dui0497a/Babefdjc.html
         * Cortex-M3: http://infocenter.arm.com/help/index.jsp?topic=/com.arm.doc.dui0552a/Babefdjc.html
         * Cortex-M4: http://infocenter.arm.com/help/topic/com.arm.doc.dui0553b/DUI0553.pdf P41
         * Cortex-M7: http://infocenter.arm.com/help/index.jsp?topic=/com.arm.doc.dui0646c/Babefdjc.html
         */
        if ((lr == 0xFFFFFFF1) || (lr == 0xFFFFFFF9) || (lr == 0xFFFFFFFD)
#if (CMB_CPU_PLATFORM_TYPE == CMB_CPU_ARM_CORTEX_M4) || (CMB_CPU_PLATFORM_TYPE == CMB_CPU_ARM_CORTEX_M3)
            || (lr == 0xFFFFFFE1) || (lr == 0xFFFFFFE9) || (lr == 0xFFFFFFED)
#endif
           )
        {
            break;
        }
    }

    cm_backtrace_fault(lr, cmb_get_sp() + sizeof(uint32_t) * CMB_SP_WORD_OFFSET);

    cmb_println("Current system tick: %ld", rt_tick_get());

    while (_continue == 1);

    return RT_EOK;
}

RT_WEAK void assert_hook(const char* ex, const char* func, rt_size_t line) {
    volatile uint8_t _continue = 1;

    rt_enter_critical();

#ifdef RT_USING_FINSH
    extern long list_thread(void);
    list_thread();
#endif

    cmb_println("");
    cmb_println("(%s) has assert failed at %s:%ld.", ex, func, line);

    cm_backtrace_assert(cmb_get_sp());

    cmb_println("Current system tick: %ld", rt_tick_get());

    while (_continue == 1);
}

int rt_cm_backtrace_init(void) {
    cm_backtrace_init("luatos","1.0","V0007");
    
    rt_hw_exception_install(exception_hook);

    rt_assert_set_hook(assert_hook);
    
    return 0;
}
INIT_DEVICE_EXPORT(rt_cm_backtrace_init);

long cmb_test(int argc, char **argv) {
    volatile int * SCB_CCR = (volatile int *) 0xE000ED14; // SCB->CCR
    int x, y, z;
    
    if (argc < 2)
    {
        rt_kprintf("Please input 'cmb_test <DIVBYZERO|UNALIGNED>' \n");
        return 0;
    }

    if (!strcmp(argv[1], "DIVBYZERO"))
    {
        *SCB_CCR |= (1 << 4); /* bit4: DIV_0_TRP. */
        x = 10;
        y = rt_strlen("");
        z = x / y;
        rt_kprintf("z:%d\n", z);
        
        return 0;
    }
    else if (!strcmp(argv[1], "UNALIGNED"))
    {
        volatile int * p;
        volatile int value;
        *SCB_CCR |= (1 << 3); /* bit3: UNALIGN_TRP. */

        p = (int *) 0x00;
        value = *p;
        rt_kprintf("addr:0x%02X value:0x%08X\r\n", (int) p, value);

        p = (int *) 0x04;
        value = *p;
        rt_kprintf("addr:0x%02X value:0x%08X\r\n", (int) p, value);

        p = (int *) 0x03;
        value = *p;
        rt_kprintf("addr:0x%02X value:0x%08X\r\n", (int) p, value);
        
        return 0;
    }
    return 0;
}
MSH_CMD_EXPORT(cmb_test, cm_backtrace_test: cmb_test <DIVBYZERO|UNALIGNED> );
