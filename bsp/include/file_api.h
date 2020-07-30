/**
 * @file file_api.h
 * @author lisiqi (alienwalker@sina.com)
 * @brief 文件操作相关API
 * @version 0.1
 * @date 2020-07-30
 * 
 * @copyright Copyright (c) 2020
 * 
 */
#ifndef __FILE_API_H__
#define __FILE_API_H__
#include "api_config.h"

#ifdef LUATOS_NO_STD_FILE
#define	LUATOS_FOPEN		(-1)	/* from sys/file.h, kernel use only */
#define	LUATOS_FREAD		0x0001	/* read enabled */
#define	LUATOS_FWRITE		0x0002	/* write enabled */
#define	LUATOS_FAPPEND	0x0008	/* append (writes guaranteed at the end) */
#define	LUATOS_FMARK		0x0010	/* internal; mark during gc() */
#define	LUATOS_FDEFER		0x0020	/* internal; defer for next gc pass */
#define	LUATOS_FASYNC		0x0040	/* signal pgrp when data ready */
#define	LUATOS_FSHLOCK	0x0080	/* BSD flock() shared lock present */
#define	LUATOS_FEXLOCK	0x0100	/* BSD flock() exclusive lock present */
#define	LUATOS_FCREAT		0x0200	/* open with file create */
#define	LUATOS_FTRUNC		0x0400	/* open with truncation */
#define	LUATOS_FEXCL		0x0800	/* error on open if file exists */
#define	LUATOS_FNBIO		0x1000	/* non blocking I/O (sys5 style) */
#define	LUATOS_FSYNC		0x2000	/* do all writes synchronously */
#define	LUATOS_FNONBLOCK	0x4000	/* non blocking I/O (POSIX style) */
#define	LUATOS_FNDELAY	_FNONBLOCK	/* non blocking I/O (4.2 style) */
#define	LUATOS_FNOCTTY	0x8000	/* don't assign a ctty on this open */



/*
 * Flag values for open(2) and fcntl(2)
 * The kernel adds 1 to the open modes to turn it into some
 * combination of FREAD and FWRITE.
 */
#define	FS_RDONLY	0		/* +1 == FREAD */
#define	FS_WRONLY	1		/* +1 == FWRITE */
#define	FS_RDWR		2		/* +1 == FREAD|FWRITE */
#define	FS_APPEND	LUATOS_FAPPEND
#define	FS_CREAT	LUATOS_FCREAT
#define	FS_TRUNC	LUATOS_FTRUNC
#define	FS_EXCL		LUATOS_FEXCL
#define FS_SYNC		LUATOS_FSYNC
/*	O_NDELAY	_FNDELAY 	set in include/fcntl.h */
/*	O_NDELAY	_FNBIO 		set in include/fcntl.h */
#define	FS_NONBLOCK	LUATOS_FNONBLOCK
#define	FS_NOCTTY	LUATOS_FNOCTTY
#define	FS_ACCMODE	(FS_RDONLY|FS_WRONLY|FS_RDWR)

#ifndef SEEK_SET
#define	SEEK_SET	0	/* set file offset to offset */
#endif
#ifndef SEEK_CUR
#define	SEEK_CUR	1	/* set file offset to current plus offset */
#endif
#ifndef SEEK_END
#define	SEEK_END	2	/* set file offset to EOF plus offset */
#endif
#endif

/**
 * @brief file在luatos中的适配相关初始化工作，真正的初始化工作应该在启动luatos前就完成了。
 *          主要完成当前目录切换到根目录
 * 
 */
void luatos_file_init(void);

/**
 * @brief 打开一个文件
 * 
 * @note 优先根据flags_string确定打开方式，flags_string为空时，选择flags，SDK
 * @param path 文件路径和名称
 * @param flags_string 文件打开标志，字符串型 (read/write/etc)
 *              单一可选项：
 *              @arg @ref "r" or "rb"   只读
 *              @arg @ref "w"           只写
 *              @arg @ref "r+" or "rb+" 可读可写
 *              @arg @ref "wb"          只写+创建
 *              @arg @ref "wb+"         可读可写+创建
 *              @arg @ref "a" or "ab"   追加
 *              @arg @ref "a+" or "ab+" 追加+创建
 * @param flags 文件打开标志，十六进制
 *              必选单一可选项：
 *              @arg @ref FS_RDONLY     只读
 *              @arg @ref FS_WRONLY     只写
 *              @arg @ref FS_RDWR       可读可写
 *              可附加的选项
 *              @arg @ref FS_APPEND     追加模式
 *              @arg @ref FS_CREAT      文件不存在时创建文件
 *              @arg @ref FS_TRUNC      打开一个文件并截断它的长度为零
 *              @arg @ref FS_EXCL       文件不存在时返回错误
 *              @arg @ref FS_SYNC       同步写入
 *              @arg @ref FS_NONBLOCK   非阻塞打开
 * @param error [OUT]打开失败时的错误码
 * @return LUATOS_HANDLE 成功返回 > 0 的句柄，失败返回NULL，并写error
 */
LUATOS_HANDLE luatos_file_open(const char *path, const char *flags_string, uint32_t flags, int *error);

/**
 * @brief 关闭一个已经打开的文件
 * 
 * @param file_hanle 文件句柄
 * @return LUATOS_STATUS 
 */
LUATOS_STATUS luatos_file_close(LUATOS_HANDLE file_hanle);

/**
 * @brief 将文件的修改立刻写入存储器，如果SDK中close具有同样功能，可以直接返回成功
 * 
 * @param file_hanle 文件句柄
 * @return LUATOS_STATUS 
 */
LUATOS_STATUS luatos_file_flush(LUATOS_HANDLE file_hanle);

/**
 * @brief 从文件中读取数据到缓冲区
 * 
 * @param [OUT]buf 缓冲区
 * @param size 单块数据大小
 * @param nmemb 多少块数据
 * @param file_hanle 文件句柄
 * @param [OUT]error 错误码
 * @return uint32_t 成功返回实际读取字节，失败返回0，并写error
 */
uint32_t luatos_file_read(void *buf, uint32_t size, uint32_t nmemb, LUATOS_HANDLE file_hanle, int *error);

/**
 * @brief 写数据到文件
 * 
 * @param buf 需要写入的数据
 * @param size 需要写入的数据一个块的大小
 * @param nmemb 需要写入的数据多少块
 * @param file_hanle 文件句柄
 * @param [OUT]error 错误码 
 * @return uint32_t 成功返回实际读取字节，失败返回0，并写error
 */
uint32_t luatos_file_write(const void *buf, uint32_t size, uint32_t nmemb, LUATOS_HANDLE file_hanle, int *error);

/**
 * @brief 修改文件数据指针位置
 * 
 * @param file_hanle 文件句柄
 * @param offset 偏移量
 * @param origin 偏移基准位置
 *              可选单一项
 *              @arg @ref SEEK_SET 文件头，往文件尾偏移
 *              @arg @ref SEEK_CUR 当前打开的位置，往文件尾偏移
 *              @arg @ref SEEK_END 文件尾，往文件头偏移
 * @return LUATOS_STATUS 
 */
LUATOS_STATUS luatos_file_seek(LUATOS_HANDLE file_hanle, int32_t offset, uint8_t origin);

/**
 * @brief 返回文件数据指针距离文件头的偏移量
 * 
 * @param file_hanle 文件句柄
 * @param [OUT]error 错误码 
 * @return uint32_t 成功返回偏移量，失败返回0，并写error
 */
uint32_t luatos_file_tell(LUATOS_HANDLE file_hanle, int *error);

/**
 * @brief 返回文件大小
 * 
 * @param file_hanle 文件句柄
 * @param [OUT]error 错误码
 * @return uint32_t 成功返回文件大小，失败返回0，并写error
 */
uint32_t luatos_file_size(LUATOS_HANDLE file_hanle, int *error);

/**
 * @brief 删除文件
 * 
 * @param path 文件路径和名称
 * @return LUATOS_STATUS 
 */
LUATOS_STATUS luatos_file_remove(const char *path);

/**
 * @brief 修改文件名称
 * 
 * @param old_name 旧文件名称
 * @param new_name 新文件名称
 * @return LUATOS_STATUS 
 */
LUATOS_STATUS luatos_file_rename(const char *old_name, const char *new_name);

/**
 * @brief 创建一个文件夹
 * 
 * @param dir 文件夹路径和名称
 * @return LUATOS_STATUS 
 */
LUATOS_STATUS luatos_file_mkdir(const char *dir);

/**
 * @brief 删除一个文件夹，同时删除递归删除文件夹内所有内容
 * 
 * @param dir 文件夹路径和名称
 * @return LUATOS_STATUS 
 */
LUATOS_STATUS luatos_file_rmdir(const char *dir);

/**
 * @brief 切换到指定文件夹目录
 * 
 * @param dir 文件夹路径和名称
 * @return LUATOS_STATUS 
 */
LUATOS_STATUS luatos_file_chdir(const char *dir);

/**
 * @brief 获取当前工作目录
 * 
 * @param [OUT]buf 存放工作目录的数据区
 * @param size 数据区长度
 * @return LUATOS_STATUS 
 */
LUATOS_STATUS luatos_file_getcwd(char *buf, uint32_t size);
#endif