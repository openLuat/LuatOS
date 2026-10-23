#ifndef LUAT_USB_H
#define LUAT_USB_H

#include "luat_base.h"

#define MAX_USB_BUS_COUNT 2
enum
{
	LUAT_USB_MODE_DEVICE,
	LUAT_USB_MODE_HOST,
	LUAT_USB_MODE_OTG,
	LUAT_USB_CLASS_HUB = 0,
	LUAT_USB_CLASS_CAMERA,
	LUAT_USB_CLASS_CDC_ACM,
	LUAT_USB_CLASS_MSC,
	LUAT_USB_CLASS_CDC_ECM,
	LUAT_USB_CLASS_RNDIS,
	LUAT_USB_CLASS_AUDIO,
	LUAT_USB_CLASS_HID_CUSTOMER,
	LUAT_USB_CLASS_HID_KEYBOARD,
//	LUAT_USB_CLASS_WINUSB,
	LUAT_USB_CLASS_QTY,
	LUAT_USB_EVENT_NEW_RX	= 0,
	LUAT_USB_EVENT_TX_DONE,
	LUAT_USB_EVENT_CONNECT,
	LUAT_USB_EVENT_DISCONNECT,
	LUAT_USB_EVENT_RX_ERROR,
	LUAT_USB_EVENT_TX_ERROR,
	LUAT_USB_EVENT_SUSPEND,
	LUAT_USB_EVENT_RESUME,
	LUAT_USB_EVENT_ERROR_STOP,
};

typedef union
{
	struct
	{
		union {
			uint8_t usb_id;
			uint8_t frame_id;
			uint8_t port_id;
		};
		uint8_t class;
		uint8_t app_id;
		uint8_t event;
	};
	uint32_t u32;
}usb_event_u;

typedef union
{
	struct
	{
		uint8_t hub_address;
		uint8_t hub_port;
		uint8_t device_address;
		uint8_t unuse;
	};
	uint32_t u32;
}usb_info_u;

typedef void (*usb_app_callback_t)(uint8_t usb_id, uint8_t class_type, uint8_t app_id, uint8_t event, uint8_t *data, uint32_t len);

int luat_usb_set_vid(int id, uint16_t vid);
int luat_usb_get_vid(int id, uint16_t *vid);

int luat_usb_set_pid(int id, uint16_t pid);
int luat_usb_get_pid(int id, uint16_t *pid);

int luat_usb_set_dev_id(int id, uint16_t dev_id);
int luat_usb_get_dev_id(int id, uint16_t *dev_id);

int luat_usb_set_mode(int id, uint8_t mode);

int luat_usb_add_class(int id, uint8_t class, uint8_t num);
int luat_usb_get_free_ep_num(int id);
int luat_usb_clear_class(int id);

int luat_usb_set_callback(int id, usb_app_callback_t callback);

int luat_usb_tx(int id, uint8_t app_id, const void *data, uint32_t len);
int luat_usb_hid_tx(int id, const char *string, uint32_t len, uint8_t is_keyboard);
int luat_usb_rx(int id, uint8_t app_id, void *data, uint32_t len);

int luat_usb_power_on_off(int id, uint8_t on_off);

int luat_usb_debug(int id, uint8_t on_off);

int luat_usb_host_reset_device(int id, uint8_t app_id);

/********************** uvc ***********************/
/* 控制项属性位 */
#define _F_RANGE   (1u << 0)   /* 支持 GET_MIN/GET_MAX/GET_RES */
#define _F_DEF     (1u << 1)   /* 支持 GET_DEF */
#define _F_SIGNED  (1u << 2)   /* 参数按有符号解释 */
#define _F_COMPOSITE (1u << 3) /* 复合结构，枚举时不展开 min/max/cur */
#define _F_NO_INFO  (1u << 4)   /*没有get info */

#define _F_TYPE_A_ID_   1
#define _F_TYPE_B_ID_   2
#define _F_TYPE_C_ID_   3
#define _F_TYPE_D_ID_   4
#define _F_TYPE_E_ID_   5
#define _F_TYPE_F_ID_   6

#define _F_TYPE_A_  (_F_TYPE_A_ID_ << 5)
#define _F_TYPE_B_  (_F_TYPE_B_ID_ << 5)
#define _F_TYPE_C_  (_F_TYPE_C_ID_ << 5)
#define _F_TYPE_D_  (_F_TYPE_D_ID_ << 5)
#define _F_TYPE_E_  (_F_TYPE_E_ID_ << 5)
#define _F_TYPE_F_  (_F_TYPE_F_ID_ << 5)

/*! @brief Video device class-specific Camera Terminal control selector */
#define LUAT_UVC_CT_CONTROL_UNDEFINED              0x00U           /* 未定义，保留值，主机不应下发 */
#define LUAT_UVC_CT_SCANNING_MODE_CONTROL          0x01U           /* 扫描模式：隔行采集开关(1=开)，1 字节 */
#define LUAT_UVC_CT_AE_MODE_CONTROL                0x02U           /* AE 模式：手动/自动光圈/自动曝光/快门优先组合位图，1 字节 */
#define LUAT_UVC_CT_AE_PRIORITY_CONTROL            0x03U           /* AE 优先级：优先保快门速度还是优先保光圈，1 字节 */
#define LUAT_UVC_CT_EXPOSURE_TIME_ABSOLUTE_CONTROL 0x04U           /* 绝对曝光时间：直接写曝光时长(单位 100us)，4 字节 */
#define LUAT_UVC_CT_EXPOSURE_TIME_RELATIVE_CONTROL 0x05U           /* 相对曝光时间：在当前值上 ±步进，1 字节有符号 */
#define LUAT_UVC_CT_FOCUS_ABSOLUTE_CONTROL         0x06U           /* 绝对对焦：镜头焦点位置，2 字节 */
#define LUAT_UVC_CT_FOCUS_RELATIVE_CONTROL         0x07U           /* 相对对焦：方向+步数+速度，仅定焦(非变焦)镜头可用 */
#define LUAT_UVC_CT_FOCUS_AUTO_CONTROL             0x08U           /* 自动对焦开关(1=开)，1 字节；bmControls 对应 D17(D15/D16 保留) */
#define LUAT_UVC_CT_IRIS_ABSOLUTE_CONTROL          0x09U           /* 绝对光圈：光圈位置/步进值，2 字节 */
#define LUAT_UVC_CT_IRIS_RELATIVE_CONTROL          0x0AU           /* 相对光圈：在当前值上 ±步进，1 字节有符号 */
#define LUAT_UVC_CT_ZOOM_ABSOLUTE_CONTROL          0x0BU           /* 绝对变焦：变焦位置(物方焦距，单位 mm)，2 字节 */
#define LUAT_UVC_CT_ZOOM_RELATIVE_CONTROL          0x0CU           /* 相对变焦：方向+步数+速度，3 字节 */
#define LUAT_UVC_CT_PANTILT_ABSOLUTE_CONTROL       0x0DU           /* 绝对云台：Pan/Tilt 绝对角度，各 4 字节共 8 字节 */
#define LUAT_UVC_CT_PANTILT_RELATIVE_CONTROL       0x0EU           /* 相对云台：Pan/Tilt 方向+步数+速度，8 字节 */
#define LUAT_UVC_CT_ROLL_ABSOLUTE_CONTROL          0x0FU           /* 绝对旋转：绕光轴角度的绝对值，2 字节 */
#define LUAT_UVC_CT_ROLL_RELATIVE_CONTROL          0x10U           /* 相对旋转：绕光轴方向+步数，2 字节 */
#define LUAT_UVC_CT_PRIVACY_CONTROL                0x11U           /* 隐私遮挡开关(1=遮挡、不出画面)，1 字节 */
#define LUAT_UVC_CT_FOCUS_SIMPLE_CONTROL           0x12U           /* 简易对焦：0=释放 1=锁定，UVC 1.5 新增 */
#define LUAT_UVC_CT_WINDOW_CONTROL                 0x13U           /* 窗口控制：AE/AF 作用的窗口位置与尺寸，UVC 1.5 新增 */
#define LUAT_UVC_CT_REGION_OF_INTEREST_CONTROL     0x14U           /* 感兴趣区域(ROI)：AE/AF 生效的矩形区域，UVC 1.5 新增 */

/* Camera Terminal bmControls 位序（UVC 1.1 Table 3-6 / 1.5 Table 3-6） */
#define LUAT_UVC_CT_BIT_SCANNING_MODE          0
#define LUAT_UVC_CT_BIT_AE_MODE                1
#define LUAT_UVC_CT_BIT_AE_PRIORITY            2
#define LUAT_UVC_CT_BIT_EXPOSURE_ABSOLUTE      3
#define LUAT_UVC_CT_BIT_EXPOSURE_RELATIVE      4
#define LUAT_UVC_CT_BIT_FOCUS_ABSOLUTE         5
#define LUAT_UVC_CT_BIT_FOCUS_RELATIVE         6
#define LUAT_UVC_CT_BIT_IRIS_ABSOLUTE          7
#define LUAT_UVC_CT_BIT_IRIS_RELATIVE          8
#define LUAT_UVC_CT_BIT_ZOOM_ABSOLUTE          9
#define LUAT_UVC_CT_BIT_ZOOM_RELATIVE          10
#define LUAT_UVC_CT_BIT_PANTILT_ABSOLUTE       11
#define LUAT_UVC_CT_BIT_PANTILT_RELATIVE       12
#define LUAT_UVC_CT_BIT_ROLL_ABSOLUTE          13
#define LUAT_UVC_CT_BIT_ROLL_RELATIVE          14
/* 15/16 保留 */
#define LUAT_UVC_CT_BIT_FOCUS_AUTO             17   /* <- 不是 7 */
#define LUAT_UVC_CT_BIT_PRIVACY                18
#define LUAT_UVC_CT_BIT_FOCUS_SIMPLE           19   /* 1.5 */
#define LUAT_UVC_CT_BIT_WINDOW                 20   /* 1.5 */
#define LUAT_UVC_CT_BIT_REGION_OF_INTEREST     21   /* 1.5 */

/*! @brief Video device class-specific Processing Unit control selector */
#define LUAT_UVC_PU_CONTROL_UNDEFINED                      0x00U   /* 未定义，保留值，主机不应下发 */
#define LUAT_UVC_PU_BACKLIGHT_COMPENSATION_CONTROL         0x01U   /* 背光补偿：逆光下提升暗部亮度，2 字节有符号 */
#define LUAT_UVC_PU_BRIGHTNESS_CONTROL                     0x02U   /* 亮度：画面整体明暗，2 字节有符号 */
#define LUAT_UVC_PU_CONTRAST_CONTROL                       0x03U   /* 对比度：明暗反差，2 字节无符号 */
#define LUAT_UVC_PU_GAIN_CONTROL                           0x04U   /* 增益：图像信号放大倍数，2 字节无符号 */
#define LUAT_UVC_PU_POWER_LINE_FREQUENCY_CONTROL           0x05U   /* 工频防闪烁：0=禁用 1=50Hz 2=60Hz 3=自动 */
#define LUAT_UVC_PU_HUE_CONTROL                            0x06U   /* 色相：色调偏移，2 字节有符号 */
#define LUAT_UVC_PU_SATURATION_CONTROL                     0x07U   /* 饱和度：色彩浓淡，2 字节无符号 */
#define LUAT_UVC_PU_SHARPNESS_CONTROL                      0x08U   /* 锐度：边缘增强强度，2 字节无符号 */
#define LUAT_UVC_PU_GAMMA_CONTROL                          0x09U   /* 伽马校正：取值 = gamma×100，2 字节 */
#define LUAT_UVC_PU_WHITE_BALANCE_TEMPERATURE_CONTROL      0x0AU   /* 白平衡色温：直接写色温(单位 K)，2 字节 */
#define LUAT_UVC_PU_WHITE_BALANCE_TEMPERATURE_AUTO_CONTROL 0x0BU   /* 白平衡自动(色温模式)开关，1=自动，1 字节 */
#define LUAT_UVC_PU_WHITE_BALANCE_COMPONENT_CONTROL        0x0CU   /* 分量白平衡：蓝/红增益各 2 字节，共 4 字节 */
#define LUAT_UVC_PU_WHITE_BALANCE_COMPONENT_AUTO_CONTROL   0x0DU   /* 分量白平衡自动开关，1=自动，1 字节 */
#define LUAT_UVC_PU_DIGITAL_MULTIPLIER_CONTROL             0x0EU   /* 数字倍率：数码变焦/数字增益倍数，2 字节 */
#define LUAT_UVC_PU_DIGITAL_MULTIPLIER_LIMIT_CONTROL       0x0FU   /* 数字倍率上限：约束 digital multiplier 最大值 */
#define LUAT_UVC_PU_HUE_AUTO_CONTROL                       0x10U   /* 色相自动校正开关，1=自动 */
#define LUAT_UVC_PU_ANALOG_VIDEO_STANDARD_CONTROL          0x11U   /* 模拟视频制式：NTSC/PAL/SECAM，仅模拟输入设备有效 */
#define LUAT_UVC_PU_ANALOG_LOCK_STATUS_CONTROL             0x12U   /* 模拟信号锁定状态：只读，指示是否锁定到有效信号 */
#define LUAT_UVC_PU_CONTRAST_AUTO_CONTROL                  0x13U   /* 对比度自动开关，UVC 1.5 新增 */

/* Processing Unit bmControls 位序（UVC 1.1 Table 3-8 / 1.5 Table 3-8） */
#define LUAT_UVC_PU_BIT_BRIGHTNESS             0
#define LUAT_UVC_PU_BIT_CONTRAST               1
#define LUAT_UVC_PU_BIT_HUE                    2
#define LUAT_UVC_PU_BIT_SATURATION             3
#define LUAT_UVC_PU_BIT_SHARPNESS              4
#define LUAT_UVC_PU_BIT_GAMMA                  5
#define LUAT_UVC_PU_BIT_WHITE_BALANCE_TEMP     6
#define LUAT_UVC_PU_BIT_WHITE_BALANCE_COMP     7
#define LUAT_UVC_PU_BIT_BACKLIGHT              8
#define LUAT_UVC_PU_BIT_GAIN                   9
#define LUAT_UVC_PU_BIT_POWER_LINE_FREQ        10
#define LUAT_UVC_PU_BIT_HUE_AUTO               11
#define LUAT_UVC_PU_BIT_WHITE_BALANCE_TEMP_AUTO 12
#define LUAT_UVC_PU_BIT_WHITE_BALANCE_COMP_AUTO 13
#define LUAT_UVC_PU_BIT_DIGITAL_MULTIPLIER     14
#define LUAT_UVC_PU_BIT_DIGITAL_MULTIPLIER_LIMIT 15
#define LUAT_UVC_PU_BIT_ANALOG_VIDEO_STANDARD  16
#define LUAT_UVC_PU_BIT_ANALOG_LOCK_STATUS     17
#define LUAT_UVC_PU_BIT_CONTRAST_AUTO          18   /* 1.5 */

/*! @brief Video device class-specific Encoding Unit control selector */
#define LUAT_UVC_EU_CONTROL_UNDEFINED           0x00U
#define LUAT_UVC_EU_SELECT_LAYER_CONTROL        0x01U
#define LUAT_UVC_EU_PROFILE_TOOLSET_CONTROL     0x02U
#define LUAT_UVC_EU_VIDEO_RESOLUTION_CONTROL    0x03U
#define LUAT_UVC_EU_MIN_FRAME_INTERVAL_CONTROL  0x04U
#define LUAT_UVC_EU_SLICE_MODE_CONTROL          0x05U
#define LUAT_UVC_EU_RATE_CONTROL_MODE_CONTROL   0x06U
#define LUAT_UVC_EU_AVERAGE_BITRATE_CONTROL     0x07U
#define LUAT_UVC_EU_CPB_SIZE_CONTROL            0x08U
#define LUAT_UVC_EU_PEAK_BIT_RATE_CONTROL       0x09U
#define LUAT_UVC_EU_QUANTIZATION_PARAMS_CONTROL 0x0AU
#define LUAT_UVC_EU_SYNC_REF_FRAME_CONTROL      0x0BU
#define LUAT_UVC_EU_LTR_BUFFER_CONTROL          0x0CU
#define LUAT_UVC_EU_LTR_PICTURE_CONTROL         0x0DU
#define LUAT_UVC_EU_LTR_VALIDATION_CONTROL      0x0EU
#define LUAT_UVC_EU_LEVEL_IDC_LIMIT_CONTROL     0x0FU
#define LUAT_UVC_EU_SEI_PAYLOADTYPE_CONTROL     0x10U
#define LUAT_UVC_EU_QP_RANGE_CONTROL            0x11U
#define LUAT_UVC_EU_PRIORITY_CONTROL            0x12U
#define LUAT_UVC_EU_START_OR_STOP_LAYER_CONTROL 0x13U
#define LUAT_UVC_EU_ERROR_RESILIENCY_CONTROL    0x14U


#define LUAT_UVC_REQUEST_UNDEFINED   0x00U
#define LUAT_UVC_REQUEST_SET_CUR     0x01U
#define LUAT_UVC_REQUEST_SET_CUR_ALL 0x11U
#define LUAT_UVC_REQUEST_GET_CUR     0x81U
#define LUAT_UVC_REQUEST_GET_MIN     0x82U
#define LUAT_UVC_REQUEST_GET_MAX     0x83U
#define LUAT_UVC_REQUEST_GET_RES     0x84U
#define LUAT_UVC_REQUEST_GET_LEN     0x85U
#define LUAT_UVC_REQUEST_GET_INFO    0x86U
#define LUAT_UVC_REQUEST_GET_DEF     0x87U
#define LUAT_UVC_REQUEST_GET_CUR_ALL 0x91U
#define LUAT_UVC_REQUEST_GET_MIN_ALL 0x92U
#define LUAT_UVC_REQUEST_GET_MAX_ALL 0x93U
#define LUAT_UVC_REQUEST_GET_RES_ALL 0x94U
#define LUAT_UVC_REQUEST_GET_DEF_ALL 0x97U

#define LUAT_UVC_CTRL_CAP_GET            (1u << 0)  /* D0 */
#define LUAT_UVC_CTRL_CAP_SET            (1u << 1)  /* D1 */
#define LUAT_UVC_CTRL_CAP_DISABLED_AUTO  (1u << 2)  /* D2 状态位 */
#define LUAT_UVC_CTRL_CAP_AUTOUPDATE     (1u << 3)  /* D3 */
#define LUAT_UVC_CTRL_CAP_ASYNC          (1u << 4)  /* D4 */
#define LUAT_UVC_CTRL_CAP_DISABLED_COMMIT (1u << 5) /* D5 状态位 */

#define LUAT_UVC_PU_MASK                        0x80U
/********************** usb eth ***********************/
enum
{
	LUAT_USB_ETH_ID_0 = 0,

	LUAT_USB_ETH_EVENT_TX_DONE = 0,
	LUAT_USB_ETH_EVENT_NEW_RX,
	LUAT_USB_ETH_EVENT_LINK_STATE,
	LUAT_USB_ETH_EVENT_DOWNSTREAM_BPS,
	LUAT_USB_ETH_EVENT_UPSTREAM_BPS,
	LUAT_USB_ETH_EVENT_MSS,
	LUAT_USB_ETH_EVENT_MAC,
	LUAT_USB_ETH_EVENT_CONNECT,
	LUAT_USB_ETH_EVENT_DISCONNECT,
	LUAT_USB_ETH_EVENT_DATA_FORMAT,
};

enum
{
	LUAT_USB_ETH_DATA_FORMAT_ETHERNET = 0,
	LUAT_USB_ETH_DATA_FORMAT_RNDIS,
};

typedef void(*luat_usb_event_callback_fun_t)(uint32_t event, void *data_or_p_param, uint32_t size_or_u32_param, void *user_param);
void *luat_usb_bind_eth(int id, luat_usb_event_callback_fun_t callback, void *user_param);
int luat_usb_eth_start_tx(int id, const uint32_t *data, uint32_t len);
int luat_usb_eth_continue_tx(int id, const uint32_t *data, uint32_t len);
#endif
