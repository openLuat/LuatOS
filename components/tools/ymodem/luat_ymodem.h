#ifndef __LUAT_YMODEM_H__
#define __LUAT_YMODEM_H__

#include "luat_base.h"

//save_path为保存文件夹路径
//force_save_path强制保存文件路径，优先于save_path
void *luat_ymodem_create_handler(const char *save_path, const char *force_save_path);
//收文件
//握手阶段，data为NULL,ack='c'
//数据阶段，如果收完一整个包，根据解析结果ack返回成功或者失败符号，如果不完整，则ack=0
//调用完后，如果ack不为0，则需要将ack发送出去
//调用完后，如果flag不为0，则需要将flag发送出去
//如果return不为0，有NAK发生
//文件接收完成后file_ok=1
//接收到停止帧或者取消帧后all_done=1
int luat_ymodem_receive(void *handler, uint8_t *data, uint32_t len, uint8_t *ack, uint8_t *flag, uint8_t *file_ok, uint8_t *all_done);

void luat_ymodem_reset(void *handler);
//ymodem传输完成后，调用一下保存文件并且释放资源
void luat_ymodem_release(void *handler);
#endif
