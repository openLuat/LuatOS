#ifndef RT_CONFIG_H__
#define RT_CONFIG_H__

/* Automatically generated file; DO NOT EDIT. */
/* RT-Thread Configuration */

/* RT-Thread Kernel */

#define RT_NAME_MAX 8
#define RT_ALIGN_SIZE 4
#define RT_THREAD_PRIORITY_32
#define RT_THREAD_PRIORITY_MAX 32
#define RT_TICK_PER_SECOND 1000
#define RT_USING_OVERFLOW_CHECK
#define RT_USING_HOOK
#define RT_USING_IDLE_HOOK
#define RT_IDLE_HOOK_LIST_SIZE 4
#define IDLE_THREAD_STACK_SIZE 512
#define RT_USING_TIMER_SOFT
#define RT_TIMER_THREAD_PRIO 4
#define RT_TIMER_THREAD_STACK_SIZE 512

/* kservice optimization */

#define RT_PRINTF_LONGLONG
#define RT_DEBUG

/* Inter-Thread communication */

#define RT_USING_SEMAPHORE
#define RT_USING_MUTEX
#define RT_USING_EVENT
#define RT_USING_MAILBOX
#define RT_USING_MESSAGEQUEUE
#define RT_USING_SIGNALS

/* Memory Management */

#define RT_USING_MEMPOOL
#define RT_USING_SMALL_MEM
#define RT_USING_HEAP

/* Kernel Device Object */

#define RT_USING_DEVICE
#define RT_USING_INTERRUPT_INFO
#define RT_USING_CONSOLE
#define RT_CONSOLEBUF_SIZE 512
#define RT_CONSOLE_DEVICE_NAME "uart0"
#define RT_VER_NUM 0x40100

/* RT-Thread Components */

#define RT_USING_COMPONENTS_INIT
#define RT_USING_USER_MAIN
#define RT_MAIN_THREAD_STACK_SIZE 4096
#define RT_MAIN_THREAD_PRIORITY 10

/* C++ features */


/* Command shell */

#define RT_USING_FINSH
#define RT_USING_MSH
#define FINSH_USING_MSH
#define FINSH_THREAD_NAME "tshell"
#define FINSH_THREAD_PRIORITY 20
#define FINSH_THREAD_STACK_SIZE 8192
#define FINSH_USING_HISTORY
#define FINSH_HISTORY_LINES 5
#define FINSH_USING_SYMTAB
#define FINSH_CMD_SIZE 80
#define MSH_USING_BUILT_IN_COMMANDS
#define FINSH_USING_DESCRIPTION
#define FINSH_ARG_MAX 10

/* Device virtual file system */

#define RT_USING_DFS
#define DFS_USING_POSIX
#define DFS_USING_WORKDIR
#define DFS_FILESYSTEMS_MAX 4
#define DFS_FILESYSTEM_TYPES_MAX 4
#define DFS_FD_MAX 16
#define RT_USING_DFS_DEVFS

/* Device Drivers */

#define RT_USING_DEVICE_IPC
#define RT_PIPE_BUFSZ 512
#define RT_USING_SYSTEM_WORKQUEUE
#define RT_SYSTEM_WORKQUEUE_STACKSIZE 2048
#define RT_SYSTEM_WORKQUEUE_PRIORITY 23
#define RT_USING_SERIAL
#define RT_USING_SERIAL_V1
#define RT_SERIAL_USING_DMA
#define RT_SERIAL_RB_BUFSZ 512
#define RT_USING_HWTIMER
#define RT_USING_I2C
#define RT_USING_I2C_BITOPS
#define RT_USING_PIN
#define RT_USING_PWM
#define RT_USING_RTC
#define RT_USING_SOFT_RTC
#define RT_USING_SPI
#define RT_USING_WDT
#define RT_USING_HWCRYPTO
#define RT_HWCRYPTO_DEFAULT_NAME "hwcryto"
#define RT_HWCRYPTO_IV_MAX_SIZE 16
#define RT_HWCRYPTO_KEYBIT_MAX_SIZE 256
#define RT_HWCRYPTO_USING_AES
#define RT_HWCRYPTO_USING_AES_ECB
#define RT_HWCRYPTO_USING_AES_CBC
#define RT_HWCRYPTO_USING_AES_CTR
#define RT_HWCRYPTO_USING_DES
#define RT_HWCRYPTO_USING_DES_ECB
#define RT_HWCRYPTO_USING_3DES
#define RT_HWCRYPTO_USING_3DES_ECB
#define RT_HWCRYPTO_USING_RC4
#define RT_HWCRYPTO_USING_MD5
#define RT_HWCRYPTO_USING_SHA1
#define RT_HWCRYPTO_USING_RNG
#define RT_HWCRYPTO_USING_CRC
#define RT_HWCRYPTO_USING_CRC_07
#define RT_HWCRYPTO_USING_CRC_8005
#define RT_HWCRYPTO_USING_CRC_1021
#define RT_HWCRYPTO_USING_CRC_04C11DB7
#define RT_HWCRYPTO_USING_BIGNUM
#define RT_HWCRYPTO_USING_BIGNUM_EXPTMOD
#define RT_HWCRYPTO_USING_BIGNUM_MULMOD
#define RT_USING_WIFI
#define RT_WLAN_DEVICE_STA_NAME "wlan0"
#define RT_WLAN_DEVICE_AP_NAME "wlan1"
#define RT_WLAN_SSID_MAX_LENGTH 32
#define RT_WLAN_PASSWORD_MAX_LENGTH 32
#define RT_WLAN_DEV_EVENT_NUM 2
#define RT_WLAN_MANAGE_ENABLE
#define RT_WLAN_SCAN_WAIT_MS 10000
#define RT_WLAN_CONNECT_WAIT_MS 10000
#define RT_WLAN_SCAN_SORT
#define RT_WLAN_MSH_CMD_ENABLE
#define RT_WLAN_AUTO_CONNECT_ENABLE
#define AUTO_CONNECTION_PERIOD_MS 2000
#define RT_WLAN_CFG_ENABLE
#define RT_WLAN_CFG_INFO_MAX 3
#define RT_WLAN_PROT_ENABLE
#define RT_WLAN_PROT_NAME_LEN 8
#define RT_WLAN_PROT_MAX 2
#define RT_WLAN_DEFAULT_PROT "lwip"
#define RT_WLAN_PROT_LWIP_ENABLE
#define RT_WLAN_PROT_LWIP_NAME "lwip"
#define RT_WLAN_WORK_THREAD_ENABLE
#define RT_WLAN_WORKQUEUE_THREAD_NAME "wlan_job"
#define RT_WLAN_WORKQUEUE_THREAD_SIZE 2048
#define RT_WLAN_WORKQUEUE_THREAD_PRIO 22

/* Using USB */


/* POSIX layer and C standard library */

#define RT_USING_LIBC
#define RT_LIBC_USING_TIME
#define RT_LIBC_DEFAULT_TIMEZONE 8

/* POSIX (Portable Operating System Interface) layer */

#define RT_USING_POSIX_FS
#define RT_USING_POSIX_POLL
#define RT_USING_POSIX_SELECT

/* Network */

/* Socket abstraction layer */

#define RT_USING_SAL
#define SAL_INTERNET_CHECK

/* protocol stack implement */

#define SAL_USING_LWIP
#define SAL_USING_POSIX

/* Network interface device */

#define RT_USING_NETDEV
#define NETDEV_USING_AUTO_DEFAULT
#define NETDEV_IPV4 1
#define NETDEV_IPV6 0

/* light weight TCP/IP stack */

#define RT_USING_LWIP
#define RT_USING_LWIP202
#define RT_LWIP_MEM_ALIGNMENT 4
#define RT_LWIP_IGMP
#define RT_LWIP_ICMP
#define RT_LWIP_DNS
#define RT_LWIP_DHCP
#define IP_SOF_BROADCAST 1
#define IP_SOF_BROADCAST_RECV 1

/* Static IPv4 Address */

#define RT_LWIP_IPADDR "192.168.1.30"
#define RT_LWIP_GWADDR "192.168.1.1"
#define RT_LWIP_MSKADDR "255.255.255.0"
#define RT_LWIP_UDP
#define RT_LWIP_TCP
#define RT_LWIP_RAW
#define RT_MEMP_NUM_NETCONN 8
#define RT_LWIP_PBUF_NUM 16
#define RT_LWIP_RAW_PCB_NUM 4
#define RT_LWIP_UDP_PCB_NUM 4
#define RT_LWIP_TCP_PCB_NUM 4
#define RT_LWIP_TCP_SEG_NUM 40
#define RT_LWIP_TCP_SND_BUF 8196
#define RT_LWIP_TCP_WND 8196
#define RT_LWIP_TCPTHREAD_PRIORITY 10
#define RT_LWIP_TCPTHREAD_MBOX_SIZE 8
#define RT_LWIP_TCPTHREAD_STACKSIZE 2048
#define LWIP_NO_RX_THREAD
#define LWIP_NO_TX_THREAD
#define RT_LWIP_ETHTHREAD_PRIORITY 12
#define RT_LWIP_ETHTHREAD_STACKSIZE 1024
#define RT_LWIP_ETHTHREAD_MBOX_SIZE 8
#define LWIP_NETIF_STATUS_CALLBACK 1
#define LWIP_NETIF_LINK_CALLBACK 1
#define SO_REUSE 1
#define LWIP_SO_RCVTIMEO 1
#define LWIP_SO_SNDTIMEO 1
#define LWIP_SO_RCVBUF 1
#define LWIP_SO_LINGER 0
#define LWIP_NETIF_LOOPBACK 0

/* AT commands */


/* VBUS(Virtual Software BUS) */


/* Utilities */

#define RT_USING_RYM
#define YMODEM_USING_CRC_TABLE
#define YMODEM_USING_FILE_TRANSFER
#define RT_USING_ULOG
#define ULOG_OUTPUT_LVL_D
#define ULOG_OUTPUT_LVL 7
#define ULOG_USING_ISR_LOG
#define ULOG_ASSERT_ENABLE
#define ULOG_LINE_BUF_SIZE 256

/* log format */

#define ULOG_OUTPUT_LEVEL
#define ULOG_OUTPUT_TAG
#define ULOG_BACKEND_USING_CONSOLE

/* RT-Thread Utestcases */


/* RT-Thread online packages */

/* IoT - internet of things */


/* Wi-Fi */

/* Marvell WiFi */


/* Wiced WiFi */

#define PKG_USING_NETUTILS
#define PKG_NETUTILS_NTP
#define NTP_USING_AUTO_SYNC
#define NTP_AUTO_SYNC_FIRST_DELAY 30
#define NTP_AUTO_SYNC_PERIOD 3600
#define NETUTILS_NTP_HOSTNAME "cn.ntp.org.cn"
#define NETUTILS_NTP_HOSTNAME2 "ntp.rt-thread.org"
#define NETUTILS_NTP_HOSTNAME3 "edu.ntp.org.cn"
#define PKG_USING_NETUTILS_V131
#define PKG_NETUTILS_VER_NUM 0x10301

/* IoT Cloud */


/* security packages */


/* language packages */


/* multimedia packages */

/* LVGL: powerful and easy-to-use embedded GUI library */


/* u8g2: a monochrome graphic library */


/* tools packages */


/* system packages */

/* acceleration: Assembly language or algorithmic acceleration packages */


/* Micrium: Micrium software products porting for RT-Thread */


/* peripheral libraries and drivers */

#define PKG_USING_WM_LIBRARIES
#define PKG_USING_WM_LIBRARIES_LATEST_VERSION

/* AI packages */


/* miscellaneous packages */

/* samples: kernel and components samples */


/* entertainment: terminal games and other interesting software packages */


/* Env config */

#define SYS_AUTO_UPDATE_PKGS
#define SYS_PKGS_DOWNLOAD_ACCELERATE
#define BSP_USING_WM_LIBRARIES

/* W60x Device config */

#define SOC_W600_A8xx
#define W600_EV_BOARD

/* On-chip Peripheral Drivers */

#define BSP_USING_UART
#define BSP_USING_UART0
#define BSP_USING_UART1
#define WM_UART1_BAUDRATE 115200
#define BSP_USING_PIN
#define BSP_USING_WIFI
#define BSP_USING_HWTIMER
#define BSP_USING_PWM
#define USING_PWM_CH1
#define WM_PWM_CH1_PIN -1
#define USING_PWM_CH2
#define WM_PWM_CH2_PIN -1
#define USING_PWM_CH3
#define WM_PWM_CH3_PIN -1
#define USING_PWM_CH4
#define WM_PWM_CH4_PIN -1
#define USING_PWM_CH5
#define WM_PWM_CH5_PIN -1
#define BSP_USING_I2C
#define WM_HW_I2C_FREQ 200000
#define BSP_USING_SPI
#define WM_SPI_BUS_NAME "spi0"
#define BSP_USING_WDT
#define BSP_USING_CRYPTO
#define BSP_USING_STANDBY

/* External Libraries */

#define SOC_W60X

#endif
