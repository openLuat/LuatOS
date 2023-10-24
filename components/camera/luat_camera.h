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
    uint16_t one_buf_height;		//1个接收缓存的高度，接收缓存大小=sensor_width * one_buf_height * (1 or 2，only_y=1), 底层根据实际情况会做调整，从而修改这个值
    uint8_t only_y;
	uint8_t rowScaleRatio;
	uint8_t colScaleRatio;
	uint8_t scaleBytes;
	uint8_t spi_mode;
	uint8_t is_msb;	//0 or 1;
	uint8_t is_two_line_rx; //0 or 1;
	uint8_t seq_type;	//0 or 1
    uint8_t image_scan;
    uint8_t draw_lcd;
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
 * @return 0成功，其他失败
 */
int luat_camera_setup(int id, luat_spi_camera_t *conf, void* callback, void *param);
/**
 * @brief 配置camera并且初始化camera
 * @param conf camera相关配置
 * @return 0成功，其他失败
 */
int luat_camera_init(luat_camera_conf_t *conf);
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
/**
 * @brief 关闭camera并且释放资源
 * @param id camera接收数据总线ID
 * @return 0成功，其他失败
 */
int luat_camera_close(int id);
int luat_camera_capture(int id, uint8_t quality, const char *path);

#endif
