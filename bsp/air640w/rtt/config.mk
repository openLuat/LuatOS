BSP_ROOT ?= D:/github/LuatOS/bsp/w60x
RTT_ROOT ?= D:/github/LuatOS/bsp/w60x/rt-thread

CROSS_COMPILE ?=D:\\github\\env\\tools\\gnu_gcc\\arm_gcc\\mingw\\bin\\arm-none-eabi-

CFLAGS := -mcpu=cortex-m3 -mthumb -ffunction-sections -fdata-sections -std=gnu99 -w -fno-common -fomit-frame-pointer -fno-short-enums -fsigned-char -O2
AFLAGS := -c -mcpu=cortex-m3 -mthumb -ffunction-sections -fdata-sections -x assembler-with-cpp -Wa,-mimplicit-it=thumb 
LFLAGS := -mcpu=cortex-m3 -mthumb -ffunction-sections -fdata-sections -lm -lgcc -lc -g --specs=nano.specs -nostartfiles -Wl,-Map=rtthread-w60x.map -Os -Wl,--gc-sections -Wl,--cref -Wl,--entry=Reset_Handler -Wl,--no-enum-size-warning -Wl,--no-wchar-size-warning -T drivers/linker_scripts/link.lds

CPPPATHS :=-I"D:\github\LuatOS\lua\include", \
	-I"D:\github\LuatOS\luat\inculde", \
	-I"D:\github\LuatOS\luat\packages\airkiss", \
	-I"D:\github\LuatOS\luat\packages\lfs", \
	-I"D:\github\LuatOS\luat\packages\lua-cjson", \
	-I"D:\github\LuatOS\luat\packages\vsprintf", \
	-I$(BSP_ROOT) \
	-I$(BSP_ROOT)\applications \
	-I$(BSP_ROOT)\drivers \
	-I$(BSP_ROOT)\packages\netutils-v1.1.0\ntp \
	-I$(BSP_ROOT)\packages\u8g2-c-latest \
	-I$(BSP_ROOT)\packages\u8g2-c-latest\port \
	-I$(BSP_ROOT)\packages\wm_libraries-latest \
	-I$(BSP_ROOT)\packages\wm_libraries-latest\Include \
	-I$(BSP_ROOT)\packages\wm_libraries-latest\Include\Driver \
	-I$(BSP_ROOT)\packages\wm_libraries-latest\Include\OS \
	-I$(BSP_ROOT)\packages\wm_libraries-latest\Include\Platform \
	-I$(BSP_ROOT)\packages\wm_libraries-latest\Include\WiFi \
	-I$(BSP_ROOT)\packages\wm_libraries-latest\Platform\Boot\gcc \
	-I$(BSP_ROOT)\packages\wm_libraries-latest\Platform\Common\Params \
	-I$(BSP_ROOT)\packages\wm_libraries-latest\Platform\Common\crypto \
	-I$(BSP_ROOT)\packages\wm_libraries-latest\Platform\Common\crypto\digest \
	-I$(BSP_ROOT)\packages\wm_libraries-latest\Platform\Common\crypto\math \
	-I$(BSP_ROOT)\packages\wm_libraries-latest\Platform\Common\crypto\symmetric \
	-I$(BSP_ROOT)\packages\wm_libraries-latest\Platform\Drivers\spi \
	-I$(BSP_ROOT)\packages\wm_libraries-latest\Platform\Inc \
	-I$(RTT_ROOT)\components\dfs\filesystems\devfs \
	-I$(RTT_ROOT)\components\dfs\include \
	-I$(RTT_ROOT)\components\drivers\hwcrypto \
	-I$(RTT_ROOT)\components\drivers\include \
	-I$(RTT_ROOT)\components\drivers\spi \
	-I$(RTT_ROOT)\components\drivers\wlan \
	-I$(RTT_ROOT)\components\finsh \
	-I$(RTT_ROOT)\components\libc\compilers\newlib \
	-I$(RTT_ROOT)\components\net\lwip-2.0.2\src \
	-I$(RTT_ROOT)\components\net\lwip-2.0.2\src\arch\include \
	-I$(RTT_ROOT)\components\net\lwip-2.0.2\src\include \
	-I$(RTT_ROOT)\components\net\lwip-2.0.2\src\include\ipv4 \
	-I$(RTT_ROOT)\components\net\lwip-2.0.2\src\include\netif \
	-I$(RTT_ROOT)\components\net\lwip_dhcpd \
	-I$(RTT_ROOT)\components\net\netdev\include \
	-I$(RTT_ROOT)\components\net\sal_socket\impl \
	-I$(RTT_ROOT)\components\net\sal_socket\include \
	-I$(RTT_ROOT)\components\net\sal_socket\include\dfs_net \
	-I$(RTT_ROOT)\components\net\sal_socket\include\socket \
	-I$(RTT_ROOT)\components\net\sal_socket\include\socket\sys_socket \
	-I$(RTT_ROOT)\components\utilities\ulog \
	-I$(RTT_ROOT)\components\utilities\ymodem \
	-I$(RTT_ROOT)\include \
	-I$(RTT_ROOT)\libcpu\arm\common \
	-I$(RTT_ROOT)\libcpu\arm\cortex-m3 

DEFINES := -DHAVE_CCONFIG_H -DRT_USING_NEWLIB -DWM_W600 -D_REENT_SMALL
