/******************************************************************************
 *  CAMERA设备操作抽象层
 *  @author Dozingfiretruck
 *  @since 0.0.1
 *****************************************************************************/
#ifndef Luat_CAMERA_H
#define Luat_CAMERA_H

#include "luat_base.h"
#ifdef __LUATOS__
#include "luat_lcd.h"
#endif
/**
 * @defgroup CAMERA  CAMERA设备(CAMERA)
 * @{
 */
enum
{
	LUAT_CAMERA_FRAME_START = 0,
	LUAT_CAMERA_FRAME_END,
	LUAT_CAMERA_FRAME_RX_DONE,
	LUAT_CAMERA_FRAME_ERROR,

	LUAT_CAMERA_MODE_AUTO = 0,
	LUAT_CAMERA_MODE_SCAN,

    LUAT_CAMERA_TYPE_USB = 0x20,
};

typedef struct luat_camera_conf
{
    uint8_t id;
    uint8_t zbar_scan;
    uint8_t draw_lcd;
    uint8_t i2c_id;
    uint8_t i2c_addr;
    uint8_t pwm_id;
    size_t pwm_period;
    uint8_t pwm_pulse;
    uint16_t sensor_width;
    uint16_t sensor_height;
    uint16_t pid;
    uint16_t vid;
    uint8_t color_bit;
    uint8_t id_reg;
	uint8_t id_value;
    size_t init_cmd_size;
    uint8_t *init_cmd;
#ifdef __LUATOS__
    luat_lcd_conf_t* lcd_conf;
#else
    void *lcd_conf;
#endif
} luat_camera_conf_t;

typedef struct
{
	size_t  camera_speed;			//提供给camera时钟频率
	uint16_t sensor_width;			//camera的最大宽度
    uint16_t sensor_height;			//camera的最大高度
    uint8_t only_y;
	uint8_t rowScaleRatio;
	uint8_t colScaleRatio;
	uint8_t scaleBytes;
	uint8_t spi_mode;
	uint8_t is_msb;	//0 or 1;
	uint8_t is_two_line_rx; //0 or 1;
	uint8_t seq_type;	//0 or 1
	uint8_t plat_param[4];
#ifdef __LUATOS__
    luat_lcd_conf_t* lcd_conf;
#else
    void *lcd_conf;
#endif
} luat_spi_camera_t;
#ifdef __LUATOS__
int l_camera_handler(lua_State *L, void* ptr);
#endif
/**
 * @brief 配置spi camera并且初始化camera
 * @param id camera接收数据总线ID，ec618上有2条，0和1
 * @param conf camera相关配置
 * @param callback camera接收中断回调，注意这是在中断里的回调
 * @param param 中断回调时用户的参数
 * @return >=0成功，其他失败
 */
int luat_camera_setup(int id, luat_spi_camera_t *conf, void* callback, void *param);

/**
 * @brief 配置图像大小
 * @param id camera接收数据总线ID
 * @param w 图像宽
 * @param h 图像高
 * @return >=0成功，其他失败
 */
int luat_camera_set_image_w_h(int id, uint16_t w, uint16_t h);

/**
 * @brief 配置camera并且初始化camera，spi camera不要使用这个
 * @param conf camera相关配置
 * @return 0成功，其他失败
 */
int luat_camera_init(luat_camera_conf_t *conf);

/**
 * @brief 关闭camera并且释放资源
 * @param id camera接收数据总线ID
 * @return 0成功，其他失败
 */
int luat_camera_close(int id);

/**
 * @brief 摄像头启动开始接收数据，csdk专用
 * @param id camera接收数据总线ID
 * @param buf 用户区地址，如果为NULL，则表示不存放到用户区
 * @return 0成功，其他失败
 */
int luat_camera_start_with_buffer(int id, void *buf);
/**
 * @brief 摄像头切换接收数据缓冲区，csdk专用
 * @param id camera接收数据总线ID
 * @param buf 用户区地址，如果为NULL，则表示不存放到用户区
 * @return 0成功，其他失败
 */
void luat_camera_continue_with_buffer(int id, void *buf);
/**
 * @brief 暂停接收camera数据
 * @param id camera接收数据总线ID
 * @param is_pause 非0暂停，0恢复
 * @return 0成功，其他失败
 */
int luat_camera_pause(int id, uint8_t is_pause);
/*
 * @brief 扫码库初始化
 * @param type 扫码库型号，目前只支持0
 * @param stack 扫码库任务的堆栈地址
 * @param stack_length 扫码库任务的堆栈深度，type=0时需要至少220KB
 * @param priority 扫码库任务优先级
 * @return 0成功，其他失败
 */
int luat_camera_image_decode_init(uint8_t type, void *stack, uint32_t stack_length, uint32_t priority);
/*
 * @brief 扫码库进行一次解码
 * @param data 缓冲区
 * @param image_w 图像宽
 * @param image_h 图像高
 * @param timeout 超时
 * @param callback 回调函数
 * @param param 回调参数
 * @return 0成功，其他失败
 */
int luat_camera_image_decode_once(uint8_t *data, uint16_t image_w, uint16_t image_h, uint32_t timeout, void *callback, void *param);

/*
 * @brief 扫码库反初始化
 */
void luat_camera_image_decode_deinit(void);
/*
 * @brief 获取解码结果
 * @param buf 缓冲区
 * @return 1成功，其他失败
 */
int luat_camera_image_decode_get_result(uint8_t *buf);

/**********以下是luatos使用，csdk不要使用***********/
/**
 * @brief 开始接收camera数据
 * @param id camera接收数据总线ID
 * @return 0成功，其他失败
 */
int luat_camera_start(int id);
/**
 * @brief 停止接收camera数据
 * @param id camera接收数据总线ID
 * @return 0成功，其他失败
 */
int luat_camera_stop(int id);

int luat_camera_preview(int id, uint8_t on_off);

int luat_camera_work_mode(int id, int mode);

int luat_camera_capture(int id, uint8_t quality, const char *path);

int luat_camera_capture_in_ram(int id, uint8_t quality, void *buffer);
/** @}*/
#endif
