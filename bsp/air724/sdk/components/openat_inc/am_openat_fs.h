/*********************************************************
  Copyright (C), AirM2M Tech. Co., Ltd.
  Author: lifei
  Description: AMOPENAT 开放平台
  Others:
  History: 
    Version： Date:       Author:   Modification:
    V0.1      2012.12.14  lifei     创建文件
*********************************************************/
#ifndef AM_OPENAT_FS_H
#define AM_OPENAT_FS_H

#include "am_openat_common.h"


//--------------------------------------------------------------------------------------------------
// Length or number define.
//--------------------------------------------------------------------------------------------------

// Folder or File name size in byts, to support fat long file name.
#define FS_FILE_NAME_LEN                     255 

// Max path length,to support fat long file name.
#define FS_PATH_LEN                               260 

// Max number of  open file
#define FS_NR_OPEN_FILES_MAX             32

// Max number of directory layer.
#define FS_NR_DIR_LAYERS_MAX             16
/*+\NEW\WJ\2018.10.10\去掉USES_NOR_FLASH宏*/
// Max folder or File name size in byts for uincode.
#define FS_FILE_NAME_UNICODE_LEN    (2*FS_FILE_NAME_LEN) 

// Max path size for unicode.
#define FS_PATH_UNICODE_LEN              (2*FS_PATH_LEN) 


// Size of terminated character('\0' for Unicode).
#define LEN_FOR_UNICODE_NULL_CHAR   2
/*-\NEW\WJ\2018.10.10\去掉USES_NOR_FLASH宏*/
// Length of terminated character('\0' for OEM).
#define LEN_FOR_NULL_CHAR                   1


/****************************** FILE SYSTEM ******************************/
typedef enum E_AMOPENAT_FILE_OPEN_FLAG_TAG
{
#if 1
    FS_O_RDONLY     = 0x00, /* Read only. */
    FS_O_WRONLY	    = 0x01, /* Write only. */
    FS_O_RDWR       = 0x02, /* Read and Write. */
    FS_O_ACCMODE    = 0x03, /* Access. */

    // If the file exists, this flag has no effect except as noted under FS_O_EXCL below. Otherwise, the file shall be created.
    FS_O_CREAT      = 0x0100,

    // If FS_O_CREAT and FS_O_EXCL are set, the function shall fail if the file exists.
    FS_O_EXCL       = 0x00200,

    // If the file exists, and is a regular file, and the file is successfully opened FS_O_WRONLY or FS_O_RDWR, its length shall be truncated to 0.
    FS_O_TRUNC      = 0x01000,

    // If set, the file offset shall be set to the end of the file prior to each write.
    FS_O_APPEND     = 0x02000,
    //set share
    FS_O_SHARE      = 0x04000,
#endif
/*+\NEW\WJ\2018.10.10\去掉USES_NOR_FLASH宏*/
#if 0
    FS_O_APPEND = (8),  //0x100
    FS_O_TRUNC  = 0x400,
    FS_O_CREAT =  0x200,
    FS_O_RDONLY = (0),
    FS_O_WRONLY = (1),
    FS_O_RDWR = (2),  //0x10
    FS_O_EXCL  = 0x800
#endif
/*-\NEW\WJ\2018.10.10\去掉USES_NOR_FLASH宏*/
}E_AMOPENAT_FILE_OPEN_FLAG;

typedef enum E_AMOPENAT_FILE_SEEK_FLAG_TAG
{
    // Seek from beginning of file.
    FS_SEEK_SET = 0,

    // Seek from current position.
    FS_SEEK_CUR = 1,

    // Set file pointer to EOF plus "offset"
    FS_SEEK_END = 2,
}E_AMOPENAT_FILE_SEEK_FLAG;

#define OPENAT_VALIDATE_FILE_HANDLE_START 0

//--------------------------------------------------------------------------------------------------
// File attribute define.
//--------------------------------------------------------------------------------------------------
typedef enum E_AMOPENAT_FILE_ATTR_TAG
{
    E_FS_ATTR_DEFAULT     = 0x0,
    // read-only 
    E_FS_ATTR_RO          = 0x00000001,
    // hidden 
    E_FS_ATTR_HIDDEN      = 0x00000002,
    // system 
    E_FS_ATTR_SYSTEM      = 0x00000004, 
    // volume label 
    E_FS_ATTR_VOLUME      = 0x00000008,
    // directory 
    E_FS_ATTR_DIR         = 0x00000010,
    // archived 
    E_FS_ATTR_ARCHIVE     = 0x00000020,
}E_AMOPENAT_FILE_ATTR;

//--------------------------------------------------------------------------------------------------
// Find file information.
//--------------------------------------------------------------------------------------------------
typedef struct T_AMOPENAT_FS_FIND_DATA_TAG
{
    UINT32  st_mode;     // Mode of file  (1: file 0: dir  )
    UINT32  st_size;       // For regular files, the file size in bytes
    UINT32  atime;    // Time of last access to the file
    UINT32  mtime;   // Time of last data modification
    UINT32  ctime;    // Time of last status(or inode) change
    /*+\NEW\WJ\2018.10.10\去掉USES_NOR_FLASH宏*/
    UINT8   st_name[ FS_FILE_NAME_UNICODE_LEN + LEN_FOR_UNICODE_NULL_CHAR ]; // The name of file. 
}AMOPENAT_FS_FIND_DATA,*PAMOPENAT_FS_FIND_DATA;

typedef enum E_AMOPENAT_FS_ERR_CODE_TAG
{
    ERR_FS_IS_DIRECTORY                 = -4200001,
    ERR_FS_NOT_DIRECTORY                = -4200002,
    ERR_FS_NO_DIR_ENTRY                 = -4200003,
    ERR_FS_OPERATION_NOT_GRANTED        = -4200005,
    ERR_FS_DIR_NOT_EMPTY                = -4200006,
    ERR_FS_FDS_MAX                      = -4200007,
    ERR_FS_PROCESS_FILE_MAX             = -4200008,
    ERR_FS_FILE_EXIST                   = -4200009,
    ERR_FS_NO_BASENAME                  = -4200011,
    ERR_FS_BAD_FD                       = -4200012,
    ERR_FS_NO_MORE_FILES                = -4200013,
    ERR_FS_HAS_MOUNTED                  = -4200014,
    ERR_FS_MOUNTED_FS_MAX               = -4200015,
    ERR_FS_UNKNOWN_FILESYSTEM           = -4200016,
    ERR_FS_INVALID_DIR_ENTRY            = -4200018,
    ERR_FS_INVALID_PARAMETER            = -4200019,
    ERR_FS_NOT_SUPPORT                  = -4200020,
    ERR_FS_UNMOUNT_FAILED               = -4200021,
    ERR_FS_NO_MORE_MEMORY               = -4200025,
    ERR_FS_DEVICE_NOT_REGISTER          = -4200027,
    ERR_FS_DISK_FULL                    = -4200030,
    ERR_FS_NOT_FORMAT                   = -4200032,
    ERR_FS_HAS_FORMATED                 = -4200033,
    ERR_FS_NOT_FIND_SB                  = -4200035,
    ERR_FS_DEVICE_BUSY                  = -4200037,
    ERR_FS_OPEN_DEV_FAILED              = -4200038,
    ERR_FS_ROOT_FULL                    = -4200039,
    ERR_FS_ACCESS_REG_FAILED            = -4200040,
    ERR_FS_PATHNAME_PARSE_FAILED        = -4200041,
    ERR_FS_READ_DIR_FAILED              = -4200048,
    ERR_FS_MOUNT_READ_ROOT_INODE_FAILED = -4200050,
    ERR_FS_INVALID_DEV_NUMBER           = -4200051,
    ERR_FS_RENAME_DIFF_PATH             = -4200052,
    ERR_FS_FORMAT_MOUNTING_DEVICE       = -4200053,
    ERR_FS_DATA_DESTROY                 = -4200056,
    ERR_FS_READ_SECTOR_FAILED           = -4200057,
    ERR_FS_WRITE_SECTOR_FAILED          = -4200058,
    ERR_FS_READ_FILE_EXCEED             = -4200059,
    ERR_FS_WRITE_FILE_EXCEED            = -4200060,
    ERR_FS_FILE_TOO_MORE                = -4200061,
    ERR_FS_FILE_NOT_EXIST               = -4200062,
    ERR_FS_DEVICE_DIFF                  = -4200063,
    ERR_FS_GET_DEV_INFO_FAILED          = -4200064,
    ERR_FS_NO_MORE_SB_ITEM              = -4200065,
    ERR_FS_NOT_MOUNT                    = -4200066,
    ERR_FS_NAME_BUFFER_TOO_SHORT        = -4200068,
    ERR_FS_NOT_REGULAR                  = -42000100,
}E_AMOPENAT_FS_ERR_CODE;
/*-\NEW\WJ\2018.10.10\去掉USES_NOR_FLASH宏*/

typedef struct T_AMOPENAT_TFLASH_INIT_PARAM_TAG
{
/*+\BUG WM-719\maliang\2013.3.21\文件系统接口和播放音频文件接口的文件名改为unicode little ending类型*/
    const WCHAR* pszMountPointUniLe; // T卡挂载节点,访问时T卡文件均在此目录下 UNICODE little endian
/*-\BUG WM-719\maliang\2013.3.21\文件系统接口和播放音频文件接口的文件名改为unicode little ending类型*/
}AMOPENAT_TFLASH_INIT_PARAM, *PAMOPENAT_TFLASH_INIT_PARAM;

/*+\NewReq WM-743\maliang\2013.3.28\[OpenAt]增加接口获取文件系统信息*/
typedef enum E_AMOPENAT_FILE_DEVICE_NAME_TAG
{
    E_AMOPENAT_FS_INTERNAL,
    E_AMOPENAT_FS_SDCARD
}E_AMOPENAT_FILE_DEVICE_NAME;

typedef struct T_AMOPENAT_FILE_INFO_TAG
{
    UINT64  totalSize;    // Total size
    UINT64  usedSize;     // Has used  size 
}T_AMOPENAT_FILE_INFO;
/*-\NewReq WM-743\maliang\2013.3.28\[OpenAt]增加接口获取文件系统信息*/
/*+\BUG\AMOPENAT-74\brezen\2013.9.24\添加FLASH NV接口，用来适应掉电机制*/
#define  NV_SUCCESS                (0)
#define  NV_ERR_NO_MORE_MEM        (-1)
#define  NV_ERR_WRITE_FLASH        (-2)
#define  NV_ERR_READ_FLASH         (-3)
#define  NV_ERR_ERASE_FLASH        (-4)
#define  NV_ERR_CH_SECTOR          (-5)
#define  NV_ERR_ADD_PBD            (-6)
#define  NV_ERR_VTB_UNKNOWN_STATUS (-7)
#define  NV_ERR_DEVICE_BUSY        (-8)
#define  NV_ERR_OTHER              (-9)
#define  NV_ERR_NV_NOT_FOUND       (-10)
#define  NV_ERR_DATA_ERR           (-11)
#define  NV_ERR_NV_ALREADY_EXIST   (-12)
#define  NV_ERR_WRITE_FLASH_TIMEOUT (-13)
#define  NV_ERR_ERASE_FLASH_TIMEOUT (-14)
#define  NV_ERR_OPER_NOT_SUPPORT    (-15)
/*-\BUG\AMOPENAT-74\brezen\2013.9.24\添加FLASH NV接口，用来适应掉电机制*/
#endif /* AM_OPENAT_FS_H */

