#include "luat_base.h"
#include "luat_usb.h"
#include "luat_camera.h"
#include "luat_common_api.h"
#define LUAT_LOG_TAG "camera"
#include "luat_log.h"

int32_t g_camera_log_level = LUAT_LOG_WARN;

LUAT_WEAK void luat_camera_preview_data_callback(int id, uint8_t *data, uint32_t total_byte, uint16_t w, uint16_t h, uint8_t color_bytes, void *user_data)
{

}

static const char *_ct_name[LUAT_UVC_CT_REGION_OF_INTEREST_CONTROL + 1] = 
{
    "NULL",
    "扫描模式",
    "自动曝光模式",
    "自动曝光优先级",
    "绝对曝光时间",
    "相对曝光时间",
    "绝对对焦",
    "相对对焦",
    "自动对焦开关",
    "绝对光圈",
    "相对光圈",
    "绝对变焦",
    "相对变焦",
    "绝对云台",
    "相对云台",
    "绝对旋转",
    "相对旋转",
    "隐私遮挡",
    "简易对焦",
    "数字窗口",
    "感兴趣区域",
};

static const char *_pu_name[LUAT_UVC_PU_CONTRAST_AUTO_CONTROL + 1] = 
{
    "NULL",
    "背光补偿",
    "亮度",
    "对比度",
    "增益",
    "工频抗闪烁",
    "色相",
    "饱和度",
    "锐度",
    "伽马",
    "白平衡色温",
    "自动白平衡色温",
    "白平衡分量",
    "自动白平衡分量",
    "数字倍率",
    "数字倍率上限",
    "自动色相",
    "模拟视频制式",
    "模拟信号锁定状态",
    "自动对比度",
};
static int _ctrl_plane_usb_app_id = -1;
static luat_uvc_ctrl_param_t _ct_ctrl_table[LUAT_UVC_CT_REGION_OF_INTEREST_CONTROL + 1] = {
/* 0x00 */  {0},                                       //VIDEO_CT_CONTROL_UNDEFINED 占位置
/* 0x01 */  {0, 1, 1, 1, 0, LUAT_UVC_CT_BIT_SCANNING_MODE, 1, _F_TYPE_C_, 0},     //VIDEO_CT_SCANNING_MODE_CONTROL 扫描模式：隔行采集开关，1 字节 0 隔行 / 1 逐行；def 1 = 逐行（现代 sensor 默认）；无 GET_DEF，def 仅作兜底
/* 0x02 */  {0x01, 0x0F, 0, 0x02, 0, LUAT_UVC_CT_BIT_AE_MODE, 1, _F_DEF|_F_TYPE_C_, 0},          //VIDEO_CT_AE_MODE_CONTROL 自动曝光模式：手动 1/自动模式 2/快门优先模式 曝光时间手动 4/光圈优先模式 光圈手动8 的组合位图，1 字节 
/* 0x03 */  {0, 1, 1, 0, 0, LUAT_UVC_CT_BIT_AE_PRIORITY, 1, _F_TYPE_C_, 0},   //VIDEO_CT_AE_PRIORITY_CONTROL AE 优先级：0 保帧率 / 1 允许降帧换曝光；无 GET_DEF
/* 0x04 */  {1, 10000, 1, 100, 0, LUAT_UVC_CT_BIT_EXPOSURE_ABSOLUTE, 4, _F_RANGE|_F_DEF|_F_TYPE_A_, 0},   //VIDEO_CT_EXPOSURE_TIME_ABSOLUTE_CONTROL 绝对曝光：单位 100us，上限随帧间隔变（30fps 约 333）；AE 自动/光圈优先下写会 STALL 0x02
/* 0x05 */  {-1, 1, 1, 0, 0, LUAT_UVC_CT_BIT_EXPOSURE_RELATIVE, 1, _F_SIGNED|_F_TYPE_E_, 0},   //VIDEO_CT_EXPOSURE_TIME_RELATIVE_CONTROL 相对曝光：-1/0/+1 档，写 0 = 回默认；无 GET_DEF
/* 0x06 */  {1, 65535, 1, 1000, 0, LUAT_UVC_CT_BIT_FOCUS_ABSOLUTE, 2, _F_RANGE|_F_DEF|_F_TYPE_A_, 0},   //VIDEO_CT_FOCUS_ABSOLUTE_CONTROL 绝对对焦：单位 mm，值越小越近；Focus Auto=1 时写会 STALL 0x02
/* 0x07 */  {0, 0, 0, 0, 0, LUAT_UVC_CT_BIT_FOCUS_RELATIVE, 2, _F_RANGE|_F_DEF|_F_COMPOSITE|_F_TYPE_D_, 0},   //VIDEO_CT_FOCUS_RELATIVE_CONTROL 相对对焦：{方向,速度} 2 字节，方向写 0 才停，不发会一直走到限位
/* 0x08 */  {0, 1, 1, 1, 0, LUAT_UVC_CT_BIT_FOCUS_AUTO, 1, _F_DEF|_F_TYPE_B_, 0},   //VIDEO_CT_FOCUS_AUTO_CONTROL 自动对焦开关：1 自动 / 0 手动；位序是 D17 不是 D7
/* 0x09 */  {200, 1100, 1, 280, 0, LUAT_UVC_CT_BIT_IRIS_ABSOLUTE, 2, _F_RANGE|_F_DEF|_F_TYPE_A_, 0},   //VIDEO_CT_IRIS_ABSOLUTE_CONTROL 绝对光圈：f 值 x100（f/2.8 = 280）；AE 自动/快门优先下写会 STALL 0x02；固定光圈模组不声明该位
/* 0x0A */  {-1, 1, 1, 0, 0, LUAT_UVC_CT_BIT_IRIS_RELATIVE, 1, _F_SIGNED|_F_TYPE_E_, 0},   //VIDEO_CT_IRIS_RELATIVE_CONTROL 相对光圈：-1/0/+1 档，写 0 = 回默认；无 GET_DEF
/* 0x0B */  {0, 10000, 1, 0, 0, LUAT_UVC_CT_BIT_ZOOM_ABSOLUTE, 2, _F_RANGE|_F_DEF|_F_TYPE_A_, 0},   //VIDEO_CT_ZOOM_ABSOLUTE_CONTROL 绝对变焦：单位 mm 光学焦距（不是倍率），倍率 = 当前值 / wObjectiveFocalLengthMin
/* 0x0C */  {0, 0, 0, 0, 0, LUAT_UVC_CT_BIT_ZOOM_RELATIVE, 3, _F_RANGE|_F_DEF|_F_COMPOSITE|_F_TYPE_D_, 0},   //VIDEO_CT_ZOOM_RELATIVE_CONTROL 相对变焦：{方向,数字变焦开关,速度} 3 字节，方向写 0 才停
/* 0x0D */  {0, 0, 0, 0, 0, LUAT_UVC_CT_BIT_PANTILT_ABSOLUTE, 8, _F_RANGE|_F_DEF|_F_COMPOSITE|_F_TYPE_D_, 0},   //VIDEO_CT_PANTILT_ABSOLUTE_CONTROL 绝对云台：Pan/Tilt 各 4 字节有符号，单位弧秒，范围 +-648000（+-180 度）
/* 0x0E */  {0, 0, 0, 0, 0, LUAT_UVC_CT_BIT_PANTILT_RELATIVE, 4, _F_RANGE|_F_DEF|_F_COMPOSITE|_F_TYPE_D_, 0},   //VIDEO_CT_PANTILT_RELATIVE_CONTROL 相对云台：Pan/Tilt 各 {方向,速度}，方向写 0 才停
/* 0x0F */  {-180, 180, 1, 0, 0, LUAT_UVC_CT_BIT_ROLL_ABSOLUTE, 2, _F_RANGE|_F_DEF|_F_SIGNED|_F_TYPE_A_, 0},   //VIDEO_CT_ROLL_ABSOLUTE_CONTROL 绝对旋转：单位度，+-180，正值为顺时针
/* 0x10 */  {0, 0, 0, 0, 0, LUAT_UVC_CT_BIT_ROLL_RELATIVE, 2, _F_RANGE|_F_DEF|_F_COMPOSITE|_F_TYPE_D_, 0},   //VIDEO_CT_ROLL_RELATIVE_CONTROL 相对旋转：{方向,速度}，方向写 0 才停
/* 0x11 */  {0, 1, 1, 0, 0, LUAT_UVC_CT_BIT_PRIVACY, 1, _F_TYPE_B_, 0},   //VIDEO_CT_PRIVACY_CONTROL 隐私遮挡：1 遮挡不出图 / 0 正常；无 GET_DEF，会被物理挡片反向改变，必须上报状态中断
/* 0x12 */  {0, 3, 1, 0, 0, LUAT_UVC_CT_BIT_FOCUS_SIMPLE, 1, _F_DEF|_F_TYPE_C_, 0},   //VIDEO_CT_FOCUS_SIMPLE_CONTROL 简易对焦（1.5）：0 全范围 / 1 微距 / 2 人物 / 3 风景；Linux uvcvideo 不认
/* 0x13 */  {0, 0, 0, 0, 0, LUAT_UVC_CT_BIT_WINDOW, 12, _F_NO_INFO|_F_RANGE|_F_DEF|_F_COMPOSITE|_F_TYPE_D_, 0},   //VIDEO_CT_WINDOW_CONTROL 数字窗口（1.5）：top/left/bottom/right/steps/step_units 共 12 字节；Linux 不认
/* 0x14 */  {0, 0, 0, 0, 0, LUAT_UVC_CT_BIT_REGION_OF_INTEREST, 10, _F_NO_INFO|_F_RANGE|_F_DEF|_F_COMPOSITE|_F_TYPE_D_, 0},   //VIDEO_CT_REGION_OF_INTEREST_CONTROL ROI（1.5）：矩形 + auto_controls 位掩码共 10 字节；Win10 1809+ 与 Linux 支持
};
static luat_uvc_ctrl_param_t _pu_ctrl_table[LUAT_UVC_PU_CONTRAST_AUTO_CONTROL + 1] = {
	{0},
/* 0x01 */  {0, 1, 1, 0, 0, LUAT_UVC_PU_BIT_BACKLIGHT, 2, _F_RANGE|_F_DEF|_F_TYPE_A_, 0},   //VIDEO_PU_BACKLIGHT_COMPENSATION_CONTROL 背光补偿：0 关 / 1 开，部分设备支持多档范围
/* 0x02 */  {-64, 64, 1, 0, 0, LUAT_UVC_PU_BIT_BRIGHTNESS, 2, _F_RANGE|_F_DEF|_F_SIGNED|_F_TYPE_A_, 0},   //VIDEO_PU_BRIGHTNESS_CONTROL 亮度：有符号相对值，与曝光是两条独立通路
/* 0x03 */  {0, 255, 1, 32, 0, LUAT_UVC_PU_BIT_CONTRAST, 2, _F_RANGE|_F_DEF|_F_TYPE_A_, 0},   //VIDEO_PU_CONTRAST_CONTROL 对比度：无符号相对值；Contrast Auto=1 时写会 STALL 0x02
/* 0x04 */  {0, 255, 1, 0, 0, LUAT_UVC_PU_BIT_GAIN, 2, _F_RANGE|_F_DEF|_F_TYPE_A_, 0},   //VIDEO_PU_GAIN_CONTROL 增益：无 Auto 控制，协议上始终可写，但 AE 自动下可能被设备内部覆盖，需延时回读确认
/* 0x05 */  {0, 3, 1, 1, 0, LUAT_UVC_PU_BIT_POWER_LINE_FREQ, 1, _F_DEF|_F_TYPE_C_, 0},   //VIDEO_PU_POWER_LINE_FREQUENCY_CONTROL 工频抗闪烁：0 禁用 / 1 50Hz / 2 60Hz / 3 自动；国内填 1 并把曝光对齐到 10ms 整数倍
/* 0x06 */  {-18000, 18000, 1, 0, 0, LUAT_UVC_PU_BIT_HUE, 2, _F_RANGE|_F_DEF|_F_SIGNED|_F_TYPE_A_, 0},   //VIDEO_PU_HUE_CONTROL 色相：度 x100，+-180 度；Hue Auto=1 时写会 STALL 0x02
/* 0x07 */  {0, 255, 1, 64, 0, LUAT_UVC_PU_BIT_SATURATION, 2, _F_RANGE|_F_DEF|_F_TYPE_A_, 0},   //VIDEO_PU_SATURATION_CONTROL 饱和度：无符号，过高会放大低照度彩噪
/* 0x08 */  {0, 255, 1, 16, 0, LUAT_UVC_PU_BIT_SHARPNESS, 2, _F_RANGE|_F_DEF|_F_TYPE_A_, 0},   //VIDEO_PU_SHARPNESS_CONTROL 锐度：无符号，过高出现边缘振铃并推高编码码率
/* 0x09 */  {100, 500, 1, 100, 0, LUAT_UVC_PU_BIT_GAMMA, 2, _F_RANGE|_F_DEF|_F_TYPE_A_, 0},   //VIDEO_PU_GAMMA_CONTROL 伽马：取值 = gamma x100，常见 100~300
/* 0x0A */  {2800, 6500, 10, 5000, 0, LUAT_UVC_PU_BIT_WHITE_BALANCE_TEMP, 2, _F_RANGE|_F_DEF|_F_TYPE_A_, 0},   //VIDEO_PU_WHITE_BALANCE_TEMPERATURE_CONTROL 白平衡色温：单位 K，步进常见 10 或 50；与 Component 是互斥替代关系，只声明一套
/* 0x0B */  {0, 1, 1, 1, 0, LUAT_UVC_PU_BIT_WHITE_BALANCE_TEMP_AUTO, 1, _F_DEF|_F_TYPE_B_, 0},   //VIDEO_PU_WHITE_BALANCE_TEMPERATURE_AUTO_CONTROL 自动白平衡（色温模式）：1 自动 / 0 手动；为 1 时色温不可写
/* 0x0C */  {0, 0, 0, 0, 0, LUAT_UVC_PU_BIT_WHITE_BALANCE_COMP, 4, _F_RANGE|_F_DEF|_F_COMPOSITE|_F_TYPE_D_, 0},   //VIDEO_PU_WHITE_BALANCE_COMPONENT_CONTROL 分量白平衡：Blue 在前 Red 在后各 2 字节，写反会偏成相反色调
/* 0x0D */  {0, 1, 1, 1, 0, LUAT_UVC_PU_BIT_WHITE_BALANCE_COMP_AUTO, 1, _F_DEF|_F_TYPE_B_, 0},   //VIDEO_PU_WHITE_BALANCE_COMPONENT_AUTO_CONTROL 自动白平衡（分量模式）：1 自动 / 0 手动；为 1 时分量不可写
/* 0x0E */  {100, 400, 1, 100, 0, LUAT_UVC_PU_BIT_DIGITAL_MULTIPLIER, 2, _F_RANGE|_F_DEF|_F_TYPE_A_, 0},   //VIDEO_PU_DIGITAL_MULTIPLIER_CONTROL 数字倍率：x100，已被规范标记废弃，新设备不要实现
/* 0x0F */  {100, 400, 1, 400, 0, LUAT_UVC_PU_BIT_DIGITAL_MULTIPLIER_LIMIT, 2, _F_RANGE|_F_DEF|_F_TYPE_A_, 0},   //VIDEO_PU_DIGITAL_MULTIPLIER_LIMIT_CONTROL 数字倍率上限：同样已废弃
/* 0x10 */  {0, 1, 1, 0, 0, LUAT_UVC_PU_BIT_HUE_AUTO, 1, _F_DEF|_F_TYPE_B_, 0},   //VIDEO_PU_HUE_AUTO_CONTROL 自动色度开关：1 自动 / 0 手动；为 1 时 Hue 不可写
/* 0x11 */  {0, 0, 0, 0, 0, LUAT_UVC_PU_BIT_ANALOG_VIDEO_STANDARD, 1, _F_TYPE_F_, 0},   //VIDEO_PU_ANALOG_VIDEO_STANDARD_CONTROL 模拟视频制式位图：只读，仅模拟输入设备有效
/* 0x12 */  {0, 0, 0, 0, 0, LUAT_UVC_PU_BIT_ANALOG_LOCK_STATUS, 1, _F_TYPE_F_, 0},   //VIDEO_PU_ANALOG_LOCK_STATUS_CONTROL 模拟信号锁定状态：只读
/* 0x13 */  {0, 1, 1, 0, 0, LUAT_UVC_PU_BIT_CONTRAST_AUTO, 1, _F_DEF|_F_TYPE_B_, 0},   //VIDEO_PU_CONTRAST_AUTO_CONTROL 自动对比度（1.5）：1 自动 / 0 手动；为 1 时 Contrast 不可写；Linux uvcvideo 不认
};

static int _get_v(uint32_t v, uint8_t len, uint8_t is_signed)
{
    switch(len) {
    case 1:
        if (is_signed) {
            return (int8_t)(v & 0x000000ff);
        } else {
             return (uint8_t)(v & 0x000000ff);
        }
        break;
    case 2:
        if (is_signed) {
            return (int16_t)(v & 0x0000ffff);
        } else {
            return (uint16_t)(v & 0x0000ffff);
        }
        break;
    default:
        return v;
    }
}
void luat_usb_camera_ctrl_plane_clear_all_info()
{
    _ctrl_plane_usb_app_id = -1;
}

void luat_usb_camera_ctrl_plane_get_all_info(uint8_t app_id)
{
    uint32_t ct, pu;
    luat_usb_camera_ctrl_plane_get_map(app_id, &ct, &pu);
    uint32_t temp;
    for(uint32_t i = 1; i <= LUAT_UVC_CT_REGION_OF_INTEREST_CONTROL; i++) {
        if (ct & ((uint32_t)1 << _ct_ctrl_table[i].bit)) {
            if (_ct_ctrl_table[i].flag & _F_NO_INFO) {
                _ct_ctrl_table[i].state = 0;
                continue;
            } else {
                if (luat_usb_camera_ctrl_plane_request_get(app_id, LUAT_UVC_REQUEST_GET_INFO, i, 1, &temp)) {
                    LLOGE("ct%d %s get info error", i, _ct_name[i]);
                    _ct_ctrl_table[i].state = 0;
                    continue;
                } else {
                    _ct_ctrl_table[i].state = temp;
                }
            }

            if (!(_ct_ctrl_table[i].flag & _F_COMPOSITE)) {
                if (luat_usb_camera_ctrl_plane_request_get(app_id, LUAT_UVC_REQUEST_GET_CUR, i, _ct_ctrl_table[i].len, &temp)) {
                    LLOGE("ct%d %s get cur error", i, _ct_name[i]);
                }
                _ct_ctrl_table[i].cur = _get_v(temp, _ct_ctrl_table[i].len, _ct_ctrl_table[i].flag & _F_SIGNED);
                _ct_ctrl_table[i].def = _ct_ctrl_table[i].cur;
                if (_ct_ctrl_table[i].flag & _F_DEF) {
                    if (luat_usb_camera_ctrl_plane_request_get(app_id, LUAT_UVC_REQUEST_GET_DEF, i, _ct_ctrl_table[i].len, &temp)) {
                        LLOGE("ct%d %s get def error", i, _ct_name[i]);
                    }
                    _ct_ctrl_table[i].def = _get_v(temp, _ct_ctrl_table[i].len, _ct_ctrl_table[i].flag & _F_SIGNED);
                }
                if (_ct_ctrl_table[i].flag & _F_RANGE) {
                    
                    if (luat_usb_camera_ctrl_plane_request_get(app_id, LUAT_UVC_REQUEST_GET_MIN, i, _ct_ctrl_table[i].len, &temp)) {
                        LLOGE("ct%d %s get min error", i, _ct_name[i]);
                    }
                    _ct_ctrl_table[i].min = _get_v(temp, _ct_ctrl_table[i].len, _ct_ctrl_table[i].flag & _F_SIGNED);
                    
                    if (luat_usb_camera_ctrl_plane_request_get(app_id, LUAT_UVC_REQUEST_GET_MAX, i, _ct_ctrl_table[i].len, &temp)) {
                        LLOGE("ct%d %s get max error", i, _ct_name[i]);
                    }
                    _ct_ctrl_table[i].max = _get_v(temp, _ct_ctrl_table[i].len, _ct_ctrl_table[i].flag & _F_SIGNED);
                    
                    if (luat_usb_camera_ctrl_plane_request_get(app_id, LUAT_UVC_REQUEST_GET_RES, i, _ct_ctrl_table[i].len, &temp)) {
                        LLOGE("ct%d %s get res error", i, _ct_name[i]);
                    }
                    _ct_ctrl_table[i].res = _get_v(temp, _ct_ctrl_table[i].len, _ct_ctrl_table[i].flag & _F_SIGNED);
                } else if (LUAT_UVC_CT_AE_MODE_CONTROL == i) {
                    
                    if (luat_usb_camera_ctrl_plane_request_get(app_id, LUAT_UVC_REQUEST_GET_RES, i, _ct_ctrl_table[i].len, &temp)) {
                        LLOGE("ct%d %s get res error", i, _ct_name[i]);
                    }
                    _ct_ctrl_table[i].res = _get_v(temp, _ct_ctrl_table[i].len, _ct_ctrl_table[i].flag & _F_SIGNED);
                }
            }
            LLOGI("%s state %02x, min %d max %d res %d def %d cur %d", _ct_name[i], _ct_ctrl_table[i].state, 
                _ct_ctrl_table[i].min, _ct_ctrl_table[i].max, _ct_ctrl_table[i].res, _ct_ctrl_table[i].def, _ct_ctrl_table[i].cur);
        } else {
            _ct_ctrl_table[i].state = 0;
        }
    }
    for(uint32_t i = 1; i <= LUAT_UVC_PU_CONTRAST_AUTO_CONTROL; i++) {

        if (pu & ((uint32_t)1 << _pu_ctrl_table[i].bit)) {
            if (_pu_ctrl_table[i].flag & _F_NO_INFO) {
                _pu_ctrl_table[i].state = 0;
                continue;
            } else {
                if (luat_usb_camera_ctrl_plane_request_get(app_id, LUAT_UVC_REQUEST_GET_INFO, i|LUAT_UVC_PU_MASK, 1, &temp)) {
                    LLOGE("pu%d %s get info error", i, _pu_name[i]);
                    _pu_ctrl_table[i].state = 0;
                    continue;
                } else {
                    _pu_ctrl_table[i].state = temp;
                }
            }
            
            if (!(_pu_ctrl_table[i].flag & _F_COMPOSITE)) {
                
                if (luat_usb_camera_ctrl_plane_request_get(app_id, LUAT_UVC_REQUEST_GET_CUR, i|LUAT_UVC_PU_MASK, _pu_ctrl_table[i].len, &temp)) {
                    LLOGE("pu%d %s get cur error", i, _pu_name[i]);
                }
                _pu_ctrl_table[i].cur = _get_v(temp, _pu_ctrl_table[i].len, _pu_ctrl_table[i].flag & _F_SIGNED);
                _pu_ctrl_table[i].def = _pu_ctrl_table[i].cur;
                if (_pu_ctrl_table[i].flag & _F_DEF) {
                    
                    if (luat_usb_camera_ctrl_plane_request_get(app_id, LUAT_UVC_REQUEST_GET_DEF, i|LUAT_UVC_PU_MASK, _pu_ctrl_table[i].len, &temp)) {
                        LLOGE("pu%d %s def cur error", i, _pu_name[i]);
                    }
                    _pu_ctrl_table[i].def = _get_v(temp, _pu_ctrl_table[i].len, _pu_ctrl_table[i].flag & _F_SIGNED);
                }
                if (_pu_ctrl_table[i].flag & _F_RANGE) {
                    
                    if (luat_usb_camera_ctrl_plane_request_get(app_id, LUAT_UVC_REQUEST_GET_MIN, i|LUAT_UVC_PU_MASK, _pu_ctrl_table[i].len, &temp)) {
                        LLOGE("pu%d %s min cur error", i, _pu_name[i]);
                    }
                    _pu_ctrl_table[i].min = _get_v(temp, _pu_ctrl_table[i].len, _pu_ctrl_table[i].flag & _F_SIGNED);
                    
                    if (luat_usb_camera_ctrl_plane_request_get(app_id, LUAT_UVC_REQUEST_GET_MAX, i|LUAT_UVC_PU_MASK, _pu_ctrl_table[i].len, &temp)) {
                        LLOGE("pu%d %s max cur error", i, _pu_name[i]);
                    }
                    _pu_ctrl_table[i].max = _get_v(temp, _pu_ctrl_table[i].len, _pu_ctrl_table[i].flag & _F_SIGNED);
                    
                    if (luat_usb_camera_ctrl_plane_request_get(app_id, LUAT_UVC_REQUEST_GET_RES, i|LUAT_UVC_PU_MASK, _pu_ctrl_table[i].len, &temp)) {
                        LLOGE("pu%d %s max res error", i, _pu_name[i]);
                    }
                    _pu_ctrl_table[i].res = _get_v(temp, _pu_ctrl_table[i].len, _pu_ctrl_table[i].flag & _F_SIGNED);
                }
            }
            LLOGI("%s state %02x, min %d max %d res %d def %d cur %d", _pu_name[i], _pu_ctrl_table[i].state, 
                _pu_ctrl_table[i].min, _pu_ctrl_table[i].max, _pu_ctrl_table[i].res, _pu_ctrl_table[i].def, _pu_ctrl_table[i].cur);
        } else {
            _pu_ctrl_table[i].state = 0;
        }
    }
    _ctrl_plane_usb_app_id = app_id;
}

luat_uvc_ctrl_param_t *luat_usb_camera_ctrl_plane_get(uint8_t app_id, uint8_t sn)
{
    if (_ctrl_plane_usb_app_id != app_id) return NULL;
    if (sn & LUAT_UVC_PU_MASK) {
        sn &= ~LUAT_UVC_PU_MASK;
        if (sn && sn <= LUAT_UVC_PU_CONTRAST_AUTO_CONTROL) {
            return &_pu_ctrl_table[sn];
        } else {
            return NULL;
        }
    } else {
        if (sn && sn <= LUAT_UVC_CT_REGION_OF_INTEREST_CONTROL) {
            return &_ct_ctrl_table[sn];
        } else {
            return NULL;
        }
    }
}

int luat_usb_camera_ctrl_plane_set(uint8_t app_id, uint8_t sn, int value)
{
    if (_ctrl_plane_usb_app_id != app_id) return -LUAT_ERROR_PERMISSION_DENIED;
    luat_uvc_ctrl_param_t *param = luat_usb_camera_ctrl_plane_get(app_id, sn);
    if (!param || !param->state) {
        return -LUAT_ERROR_NO_SUCH_ID;
    }
    if ((param->len > 4) || !(param->state & LUAT_UVC_CTRL_CAP_SET)) {
        return -LUAT_ERROR_CMD_NOT_SUPPORT;
    }
    int old = value;
    if (param->flag & _F_RANGE) {
        if (value <= param->min) {
            value = param->min;
        } else if (value >= param->max) {
            value = param->max;
        } else {
            value = param->min + ((value-param->min + (param->res >> 1))/param->res)*param->res;
        }
    } 
    luat_data_union_t set_data;
    switch(param->len) {
    case 1:
        if (param->flag & _F_SIGNED) {
            set_data.ii8[0] = (int8_t)value;
        } else {
            set_data.u8[0] = (uint8_t)value;
        }
        break;
    case 2:
        if (param->flag & _F_SIGNED) {
            set_data.ii16[0] = (int16_t)value;
        } else {
            set_data.u16[0] = (uint16_t)value;
        }
        break;
    default:
        if (param->flag & _F_SIGNED) {
            set_data.ii32 = (int32_t)value;
        } else {
            set_data.u32 = (uint32_t)value;
        }
        break;
    }
    if (luat_usb_camera_ctrl_plane_request_set(app_id, LUAT_UVC_REQUEST_SET_CUR, sn, param->len, &set_data.u32)) {
        return -LUAT_ERROR_OPERATION_FAILED;
    }
    param->cur = value;
    if (!luat_usb_camera_ctrl_plane_request_get(app_id, LUAT_UVC_REQUEST_GET_CUR, sn, param->len, &set_data.u32)) {
        param->cur = _get_v(set_data.u32, param->len, param->flag & _F_SIGNED);
        if (sn & LUAT_UVC_PU_MASK) {
            LLOGI("%s set %d cur %d", _pu_name[sn & ~LUAT_UVC_PU_MASK], old, param->cur);
        } else {
            LLOGI("%s set %d cur %d", _ct_name[sn], old, param->cur);
        }
    }
    return LUAT_ERROR_NONE;

}

LUAT_WEAK void luat_usb_camera_ctrl_plane_get_map(uint8_t app_id, uint32_t *ct_map, uint32_t *pu_map) {*ct_map = 0;*pu_map=0;}
LUAT_WEAK int luat_usb_camera_ctrl_plane_request_get(uint8_t app_id, uint8_t request, uint8_t sn, uint8_t len, uint32_t *v) {return -1;}
LUAT_WEAK int luat_usb_camera_ctrl_plane_request_set(uint8_t app_id, uint8_t request, uint8_t sn, uint8_t len, uint32_t *v) {return -1;}