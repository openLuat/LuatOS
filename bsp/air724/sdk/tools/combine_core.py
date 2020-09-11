#!/usr/bin/env python3
#!--encoding=utf-8
# Copyright (C) 2018 RDA Technologies Limited and/or its affiliates("RDA").
# All rights reserved.
#
# This software is supplied "AS IS" without any warranties.
# RDA assumes no responsibility or liability for the use of the software,
# conveys no license or title under any patent, copyright, or mask work
# right to the product. RDA reserves the right to make changes in the
# software without notification.  RDA also make no representation or
# warranty that such application will be suitable for the specified use
# without further testing or modification.

import os
import sys
import argparse
import json
import struct

from time import sleep
from xml.etree import ElementTree as ET
from xml.dom import minidom

DESCRIPTION = '''
Tool for pac configuration and generation.
'''

RESERVED_UTF16 = "".encode("utf-16le")
RESERVED_BYTE = "".encode("ascii")
PAC_HEADER_FMT = "48sI512s512s7I200s3I800sI2H"
FILE_HEADER_FMT = "I512s512s512s6I5I996s"
CPIO_FILE_FORMAT = '=2s12H{}s{}s'
CPIO_OLDLE_MAGIC = b'\xc7\x71'
ERASE_NV_LOGIC_ADDRESS = 0xFE000001
PHASECHECK_LOGIC_ADDRESS = 0xFE000002
NV_LOGIC_ADDRESS = 0xFE000003
PRE_PACK_FILE_LOGIC_ADDRESS = 0xFE000004
DEL_APPIMG_LOGIC_ADDRESS = 0xFE000005
ERASE_SYSFS_LOGIC_ADDRESS = 0xFE000006
PHASE_CHECK_SIZE = 0x100

CRC16_TABLE = [
    0x0000, 0xC0C1, 0xC181, 0x0140, 0xC301, 0x03C0, 0x0280, 0xC241,
    0xC601, 0x06C0, 0x0780, 0xC741, 0x0500, 0xC5C1, 0xC481, 0x0440,
    0xCC01, 0x0CC0, 0x0D80, 0xCD41, 0x0F00, 0xCFC1, 0xCE81, 0x0E40,
    0x0A00, 0xCAC1, 0xCB81, 0x0B40, 0xC901, 0x09C0, 0x0880, 0xC841,
    0xD801, 0x18C0, 0x1980, 0xD941, 0x1B00, 0xDBC1, 0xDA81, 0x1A40,
    0x1E00, 0xDEC1, 0xDF81, 0x1F40, 0xDD01, 0x1DC0, 0x1C80, 0xDC41,
    0x1400, 0xD4C1, 0xD581, 0x1540, 0xD701, 0x17C0, 0x1680, 0xD641,
    0xD201, 0x12C0, 0x1380, 0xD341, 0x1100, 0xD1C1, 0xD081, 0x1040,
    0xF001, 0x30C0, 0x3180, 0xF141, 0x3300, 0xF3C1, 0xF281, 0x3240,
    0x3600, 0xF6C1, 0xF781, 0x3740, 0xF501, 0x35C0, 0x3480, 0xF441,
    0x3C00, 0xFCC1, 0xFD81, 0x3D40, 0xFF01, 0x3FC0, 0x3E80, 0xFE41,
    0xFA01, 0x3AC0, 0x3B80, 0xFB41, 0x3900, 0xF9C1, 0xF881, 0x3840,
    0x2800, 0xE8C1, 0xE981, 0x2940, 0xEB01, 0x2BC0, 0x2A80, 0xEA41,
    0xEE01, 0x2EC0, 0x2F80, 0xEF41, 0x2D00, 0xEDC1, 0xEC81, 0x2C40,
    0xE401, 0x24C0, 0x2580, 0xE541, 0x2700, 0xE7C1, 0xE681, 0x2640,
    0x2200, 0xE2C1, 0xE381, 0x2340, 0xE101, 0x21C0, 0x2080, 0xE041,
    0xA001, 0x60C0, 0x6180, 0xA141, 0x6300, 0xA3C1, 0xA281, 0x6240,
    0x6600, 0xA6C1, 0xA781, 0x6740, 0xA501, 0x65C0, 0x6480, 0xA441,
    0x6C00, 0xACC1, 0xAD81, 0x6D40, 0xAF01, 0x6FC0, 0x6E80, 0xAE41,
    0xAA01, 0x6AC0, 0x6B80, 0xAB41, 0x6900, 0xA9C1, 0xA881, 0x6840,
    0x7800, 0xB8C1, 0xB981, 0x7940, 0xBB01, 0x7BC0, 0x7A80, 0xBA41,
    0xBE01, 0x7EC0, 0x7F80, 0xBF41, 0x7D00, 0xBDC1, 0xBC81, 0x7C40,
    0xB401, 0x74C0, 0x7580, 0xB541, 0x7700, 0xB7C1, 0xB681, 0x7640,
    0x7200, 0xB2C1, 0xB381, 0x7340, 0xB101, 0x71C0, 0x7080, 0xB041,
    0x5000, 0x90C1, 0x9181, 0x5140, 0x9301, 0x53C0, 0x5280, 0x9241,
    0x9601, 0x56C0, 0x5780, 0x9741, 0x5500, 0x95C1, 0x9481, 0x5440,
    0x9C01, 0x5CC0, 0x5D80, 0x9D41, 0x5F00, 0x9FC1, 0x9E81, 0x5E40,
    0x5A00, 0x9AC1, 0x9B81, 0x5B40, 0x9901, 0x59C0, 0x5880, 0x9841,
    0x8801, 0x48C0, 0x4980, 0x8941, 0x4B00, 0x8BC1, 0x8A81, 0x4A40,
    0x4E00, 0x8EC1, 0x8F81, 0x4F40, 0x8D01, 0x4DC0, 0x4C80, 0x8C41,
    0x4400, 0x84C1, 0x8581, 0x4540, 0x8701, 0x47C0, 0x4680, 0x8641,
    0x8201, 0x42C0, 0x4380, 0x8341, 0x4100, 0x81C1, 0x8081, 0x4040
]


def calc_crc16(crc_base, s):
    ''' calculate/update CRC16 used in pac
    '''
    for b in s:
        crc_base = (crc_base >> 8) ^ (CRC16_TABLE[(crc_base ^ b) & 0xff])
    return crc_base


def auto_int(x: str) -> int:
    ''' convert decimal or hexdecimal string to integer
    '''
    return int(x, 0)


def ushort_lo(x: int) -> int:
    ''' get the low 16bits of an integer
    '''
    return int(x) & 0xffff


def ushort_hi(x: int):
    ''' get the high 16bits of an integer
    '''
    return (int(x) >> 16) & 0xffff


class CpioConfig():
    ''' CPIO configuration. Internally, there is only a local -> remote
        map. Local can be file or directory.

        Local path will be normalized:
            * all /, without \ (backslash)
            * remove duplicated /
        Remove path will be normalized:
            * all /, without \ (backslash)
            * remove duplicated /
            * remove leading /
    '''

    def __init__(self):
        self.items = {}

    def local_path(self):
        ''' All local path, file or directory.
        '''
        return self.items.keys()

    def _insert_path(self, local, remote):
        ''' normalize and insert (local, remote)

            even local isn't exist, the record will be kept.
        '''
        local = local.replace('\\', '/').replace('//', '/')
        remote = remote.replace('\\', '/').replace('//', '/').lstrip('/')

        # special case: when remote is / (root), don't record it
        if remote:
            self.items[local] = remote

        if os.path.isdir(local):
            for f in os.listdir(local):
                self._insert_path('{}/{}'.format(local, f),
                                  '{}/{}'.format(remote, f))

    def add_path(self, local, remote):
        ''' Add path, file or directory. When local is directory,
            all childrens will be added recursively.
        '''
        self._insert_path(local, remote)

    def _gen_file_data(self, local, remote) -> bytes:
        ''' Generate data for one file or directory. The format is:
            * magic in short
            * 12 short
            * remote name with NUL, padding to even length
            * file data if exists, padding to even length
        '''
        name = self.items[local].encode('utf-8')
        name_size = len(name) + 1  # include NUL
        name_size_aligned = (name_size + 1) & ~1  # pad to even

        file_data = bytes()
        if os.path.isfile(local):
            with open(local, 'rb') as fh:
                file_data = fh.read()
        file_size = len(file_data)
        file_size_aligned = (file_size + 1) & ~1  # pad to even

        fstat = os.stat(local)
        fmt = CPIO_FILE_FORMAT.format(name_size_aligned, file_size_aligned)
        data = struct.pack(fmt,
                           CPIO_OLDLE_MAGIC,
                           ushort_lo(fstat.st_dev),
                           ushort_lo(fstat.st_ino),
                           ushort_lo(fstat.st_mode),
                           ushort_lo(fstat.st_uid),
                           ushort_lo(fstat.st_gid),
                           ushort_lo(fstat.st_nlink),
                           0,  # rdevice_num
                           ushort_hi(fstat.st_mtime),
                           ushort_lo(fstat.st_mtime),
                           ushort_lo(name_size),
                           ushort_hi(file_size),
                           ushort_lo(file_size),
                           name,
                           file_data)
        return data

    def _gen_trailer(self) -> bytes:
        ''' Generate trailer data, for end of cpio.
        '''
        name = b'TRAILER!!!'
        name_size = len(name) + 1
        name_size_aligned = (name_size + 1) & ~1

        fmt = CPIO_FILE_FORMAT.format(name_size_aligned, 0)
        data = struct.pack(fmt,
                           CPIO_OLDLE_MAGIC,
                           0, 0, 0, 0, 0,
                           1, 0, 0, 0,
                           ushort_lo(name_size),
                           0, 0,
                           name,
                           bytes())
        return data

    def gen_data(self) -> bytes:
        ''' Generate content of cpio, all files and trailer
        '''
        data = bytes()
        for local in sorted(self.items.keys()):
            data += self._gen_file_data(local, self.items[local])
        data += self._gen_trailer()
        return data


class PacNvitemConfig():
    ''' nvitem configuration. It will be easier to be accessed than dict
    '''

    def __init__(self, name: str, id: int, use: int, replace: int, cont: int, backup: int):
        self.name = name
        self.ID = id
        self.use = use
        self.replace = replace
        self.cont = cont
        self.backup = backup


class PacFileConfig():
    ''' pac file configuration, bunch of information. Inherit isn't
        used, rathe cfgType indicates the type. And if-else shall
        be used for different file type.

        File header will use:
        * szFileID
        * szFileName
        * dwFileFlag
        * defaultCheck
        * dwCanOmitFlag
        XML block will use:
        * szFileID
        * type
        * dwAddress
        * fixedSize
        * dwFileFlag
        * forceCheck
        * description
    '''

    PLAIN_FILE = 1  # there is a normal local file
    EMPTY_FILE = 2  # there are no file content
    XML_FILE = 3  # special type for the generated XML
    PACK_FILE = 4  # pack one file or directory with cpio

    def __init__(self):
        self.content = None

    def set_plain_file(self, type: str, szFileID: str, description: str,
                       dwCanOmitFlag: int, defaultCheck: int, forceCheck: int,
                       dwAddress: int, fixedSize: int,
                       filePath: str, szFileName: str):
        ''' set plain file properties
        '''
        self.cfgType = self.PLAIN_FILE
        self.type = type
        self.szFileID = szFileID
        self.description = description
        self.dwFileFlag = 1
        self.dwCanOmitFlag = dwCanOmitFlag
        self.defaultCheck = defaultCheck
        self.forceCheck = forceCheck
        self.dwAddress = dwAddress
        self.fixedSize = fixedSize
        self.filePath = filePath
        self.szFileName = szFileName

    def set_empty_file(self, type: str, szFileID: str, description: str,
                       dwCanOmitFlag: int, defaultCheck: int, forceCheck: int,
                       dwAddress: int, fixedSize: int):
        ''' set empty file properties
        '''
        self.cfgType = self.EMPTY_FILE
        self.type = type
        self.szFileID = szFileID
        self.description = description
        self.dwFileFlag = 0
        self.dwCanOmitFlag = dwCanOmitFlag
        self.defaultCheck = defaultCheck
        self.forceCheck = forceCheck
        self.dwAddress = dwAddress
        self.fixedSize = fixedSize
        self.szFileName = ''

    def set_xml_file(self, szPrdName: str, xml_data: bytes):
        ''' set xml file properties
        '''
        self.cfgType = self.XML_FILE
        self.szFileID = ''
        self.szFileName = '{}.xml'.format(szPrdName)
        self.dwFileFlag = 2
        self.defaultCheck = 0
        self.dwCanOmitFlag = 0
        self.dwAddress = 0
        self.content = xml_data

    def set_pack_file(self, szFileID: str, description: str,
                      dwCanOmitFlag: int, defaultCheck: int, forceCheck: int,
                      filePath: str, remotePath: str):
        ''' set pack file or directory properties
        '''
        self.cfgType = self.PACK_FILE
        self.type = 'CODE'
        self.szFileID = szFileID
        self.description = description
        self.dwFileFlag = 1
        self.dwCanOmitFlag = dwCanOmitFlag
        self.defaultCheck = defaultCheck
        self.forceCheck = forceCheck
        self.dwAddress = PRE_PACK_FILE_LOGIC_ADDRESS
        self.fixedSize = 0
        self.filePath = filePath
        self.szFileName = '{}.cpio'.format(szFileID)
        self.remotePath = remotePath
        self.cpioConfig = CpioConfig()
        self.cpioConfig.add_path(self.filePath, self.remotePath)

    def dep_files(self):
        ''' Get the used local files or directories (in cpio).
        '''
        flist = []
        if self.cfgType == self.PLAIN_FILE:
            flist.append(self.filePath)
        elif self.cfgType == self.PACK_FILE:
            flist.extend(self.cpioConfig.local_path())
        return flist

    def _prepare_content(self):
        ''' Prepare pac file content.
        '''
        if self.cfgType == self.PLAIN_FILE:
            with open(self.filePath, 'rb') as fh:
                self.content = fh.read()
        elif self.cfgType == self.EMPTY_FILE:
            self.content = bytes()
        elif self.cfgType == self.PACK_FILE:
            self.content = self.cpioConfig.gen_data()

    def _file_size(self) -> int:
        ''' Size in pac
        '''
        if self.content is None:
            self._prepare_content()
        return len(self.content)

    def file_data(self):
        ''' Data in pac
        '''
        if self.content is None:
            self._prepare_content()
        return self.content

    def file_header(self, offset: int):
        ''' Header in pac. Offset will be embeded into header, and it is
            not a file property. So, it is a parameter.
        '''
        return struct.pack(
            FILE_HEADER_FMT,
            struct.calcsize(FILE_HEADER_FMT),
            self.szFileID.encode('utf-16le'),
            self.szFileName.encode('utf-16le'),
            RESERVED_UTF16,
            self._file_size(),
            self.dwFileFlag,
            self.defaultCheck,
            offset,
            self.dwCanOmitFlag,
            1,
            self.dwAddress, 0, 0, 0, 0,
            RESERVED_BYTE)


class PacConfig():
    ''' configuration for PAC
    '''

    def __init__(self):
        self.dwNandStrategy = 0
        self.dwNandPageType = 0
        self.nvitems = []
        self.files = []

    def load_from_json(self, fname: str):
        ''' Load pac configuration from json. Json format should
            match store.
        '''
        with open(fname, 'r') as fh:
            cfg = json.load(fh)

        self.szVersion = cfg['szVersion']
        self.szPrdName = cfg['szPrdName']
        self.szPrdVersion = cfg['szPrdVersion']
        self.szPrdAlias = cfg['szPrdAlias']
        self.dwMode = cfg['dwMode']
        self.dwFlashType = cfg['dwFlashType']
        self.dwIsNvBackup = cfg['dwIsNvBackup']
        self.dwOmaDmProductFlag = cfg['dwOmaDmProductFlag']
        self.dwIsOmaDm = cfg['dwIsOmaDm']
        self.dwIsPreload = cfg['dwIsPreload']

        for f in cfg.get('NVItem', []):
            nc = PacNvitemConfig(f['name'],
                                 int(f['ID'], 16),
                                 f['use'],
                                 f['Replace'],
                                 f['Continue'],
                                 f['backup'])
            self.nvitems.append(nc)

        for f in cfg.get('pacFiles', []):
            fc = PacFileConfig()
            if f['cfgType'] == 'PLAIN_FILE':
                fc.set_plain_file(f['type'],
                                  f['szFileID'],
                                  f['description'],
                                  f['dwCanOmitFlag'],
                                  f['defaultCheck'],
                                  f['forceCheck'],
                                  int(f['dwAddress'], 16),
                                  int(f['fixedSize'], 16),
                                  f['filePath'],
                                  f['szFileName'])
            elif f['cfgType'] == 'EMPTY_FILE':
                fc.set_empty_file(f['type'],
                                  f['szFileID'],
                                  f['description'],
                                  f['dwCanOmitFlag'],
                                  f['defaultCheck'],
                                  f['forceCheck'],
                                  int(f['dwAddress'], 16),
                                  int(f['fixedSize'], 16))
            elif f['cfgType'] == 'PACK_FILE':
                fc.set_pack_file(f['szFileID'],
                                 f['description'],
                                 f['dwCanOmitFlag'],
                                 f['defaultCheck'],
                                 f['forceCheck'],
                                 f['filePath'],
                                 f['remotePath'])

            self.files.append(fc)

    def store_to_json(self, fname: str):
        ''' Store pac configuration to json. Json format should
            match load.
        '''
        cfg = {}
        cfg['szVersion'] = self.szVersion
        cfg['szPrdName'] = self.szPrdName
        cfg['szPrdVersion'] = self.szPrdVersion
        cfg['szPrdAlias'] = self.szPrdAlias
        cfg['dwMode'] = self.dwMode
        cfg['dwFlashType'] = self.dwFlashType
        cfg['dwIsNvBackup'] = self.dwIsNvBackup
        cfg['dwOmaDmProductFlag'] = self.dwOmaDmProductFlag
        cfg['dwIsOmaDm'] = self.dwIsOmaDm
        cfg['dwIsPreload'] = self.dwIsPreload

        cfg['NVItem'] = []
        for nc in self.nvitems:
            f = {}
            f['name'] = nc.name
            f['ID'] = hex(nc.ID)
            f['use'] = nc.use
            f['Replace'] = nc.replace
            f['Continue'] = nc.cont
            f['backup'] = nc.backup
            cfg['NVItem'].append(f)

        cfg['pacFiles'] = []
        for fc in self.files:
            if fc.cfgType == fc.XML_FILE:
                continue

            f = {}
            if fc.cfgType == fc.PLAIN_FILE:
                f['cfgType'] = 'PLAIN_FILE'
                f['type'] = fc.type
                f['szFileID'] = fc.szFileID
                f['description'] = fc.description
                f['dwCanOmitFlag'] = fc.dwCanOmitFlag
                f['defaultCheck'] = fc.defaultCheck
                f['forceCheck'] = fc.forceCheck
                f['dwAddress'] = hex(fc.dwAddress)
                f['fixedSize'] = hex(fc.fixedSize)
                f['filePath'] = fc.filePath
                f['szFileName'] = fc.szFileName
            elif fc.cfgType == fc.EMPTY_FILE:
                f['cfgType'] = 'EMPTY_FILE'
                f['type'] = fc.type
                f['szFileID'] = fc.szFileID
                f['description'] = fc.description
                f['dwCanOmitFlag'] = fc.dwCanOmitFlag
                f['defaultCheck'] = fc.defaultCheck
                f['forceCheck'] = fc.forceCheck
                f['dwAddress'] = hex(fc.dwAddress)
                f['fixedSize'] = hex(fc.fixedSize)
            elif fc.cfgType == fc.PACK_FILE:
                f['cfgType'] = 'PACK_FILE'
                f['type'] = fc.type
                f['szFileID'] = fc.szFileID
                f['description'] = fc.description
                f['dwCanOmitFlag'] = fc.dwCanOmitFlag
                f['defaultCheck'] = fc.defaultCheck
                f['forceCheck'] = fc.forceCheck
                f['filePath'] = fc.filePath
                f['remotePath'] = fc.remotePath

            cfg['pacFiles'].append(f)

        with open(fname, 'w') as fh:
            json.dump(cfg, fh, indent=4, sort_keys=True)

    def add_nvitem(self, name: str, id: int, use: int, replace: int, cont: int, backup: int):
        ''' Add backup nvitem.
        '''
        nc = PacNvitemConfig(name, id, use, replace, cont, backup)
        self.nvitems.append(nc)
        self.dwIsNvBackup = 1

    def add_host_fdl(self, address: int, size: int, filePath: str, szFileName: str):
        ''' Add HOST_FDL pac file
        '''
        fc = PacFileConfig()
        fc.set_plain_file('HOST_FDL', 'HOST_FDL', 'HOST_FDL',
                          0, 1, 1,
                          address, size, filePath, szFileName)
        self.files.append(fc)

    def add_fdl2(self, address: int, size: int, filePath: str, szFileName: str):
        ''' Add FDL2 pac file
        '''
        fc = PacFileConfig()
        fc.set_plain_file('FDL2', 'FDL2', 'FDL2',
                          0, 1, 1,
                          address, size, filePath, szFileName)
        self.files.append(fc)

    def add_fdl(self, address: int, size: int, filePath: str, szFileName: str):
        ''' Add FDL pac file
        '''
        fc = PacFileConfig()
        fc.set_plain_file('FDL', 'FDL', 'FDL',
                          0, 1, 1,
                          address, size, filePath, szFileName)
        self.files.append(fc)

    def add_code(self, szFileID: str, description: str, dwCanOmitFlag: int,
                 defaultCheck: int, forceCheck: int, address: int, size: int,
                 filePath: str, szFileName: str):
        ''' Add generic code pac file.
        '''
        fc = PacFileConfig()
        fc.set_plain_file('CODE', szFileID, description,
                          dwCanOmitFlag, defaultCheck, forceCheck,
                          address, size, filePath, szFileName)
        self.files.append(fc)

    def add_clear_nv(self):
        ''' Add clear NV operation.
        '''
        fc = PacFileConfig()
        fc.set_empty_file('EraseFlash', 'FLASH', 'Erase NV',
                          1, 1, 0, ERASE_NV_LOGIC_ADDRESS, 0x0)
        self.files.append(fc)

    def add_clear_sysfs(self, default_check: int):
        ''' Add clear sysfs operation.
        '''
        fc = PacFileConfig()
        fc.set_empty_file('EraseFlash', 'CLEARSYSFS', 'Clear Sysfs',
                          1, default_check, 0, ERASE_SYSFS_LOGIC_ADDRESS, 0x0)
        self.files.append(fc)

    def add_erase_flash(self, szFileID: str, address: int, size: int):
        ''' Add clear flash operation.
        '''
        fc = PacFileConfig()
        fc.set_empty_file('EraseFlash', szFileID, 'Erase flash',
                          1, 1, 0, address, size)
        self.files.append(fc)

    def add_del_appimg(self, szFileID: str):
        ''' Add delete appimg file operation.
        '''
        fc = PacFileConfig()
        fc.set_empty_file('EraseFlash', szFileID, 'Delete appimg file',
                          1, 1, 0, DEL_APPIMG_LOGIC_ADDRESS, 0)
        self.files.append(fc)

    def add_nv(self, size: int, filePath: str, szFileName: str):
        ''' Add NV download operation.
        '''
        fc = PacFileConfig()
        fc.set_plain_file('NV', 'NV', 'NV',
                          1, 1, 0,
                          NV_LOGIC_ADDRESS, size, filePath, szFileName)
        self.files.append(fc)

    def add_phase_check(self):
        ''' Add phase check operation.
        '''
        fc = PacFileConfig()
        fc.set_empty_file('CODE', 'PhaseCheck', 'Producting phases information section',
                          1, 1, 0, PHASECHECK_LOGIC_ADDRESS, PHASE_CHECK_SIZE)
        self.files.append(fc)

    def add_pack_file(self, szFileID: str, description: str, dwCanOmitFlag: int,
                      defaultCheck: int, forceCheck: int,
                      filePath: str, remotePath: str):
        ''' Add pack one file or directory operation.
        '''
        fc = PacFileConfig()
        fc.set_pack_file(szFileID, description,
                         dwCanOmitFlag, defaultCheck, forceCheck,
                         filePath, remotePath)
        self.files.append(fc)

    def add_pack_cpio(self, szFileID: str, description: str, dwCanOmitFlag: int,
                      defaultCheck: int, forceCheck: int,
                      filePath: str, szFileName: str):
        ''' Add pre-generated cpio operation.
        '''
        fc = PacFileConfig()
        fc.set_plain_file('CODE', szFileID, description,
                          dwCanOmitFlag, defaultCheck, forceCheck,
                          PRE_PACK_FILE_LOGIC_ADDRESS, 0x0, filePath, szFileName)
        self.files.append(fc)

    def dep_files(self):
        ''' Get the used local files or directories (in cpio).
        '''
        flist = []
        for f in self.files:
            flist.extend(f.dep_files())
        return flist

    def _create_xml(self):
        ''' Create embeded XML
        '''
        root = ET.Element("BMAConfig")

        # ProductList
        product_list = ET.SubElement(root, "ProductList")

        # ProductList -> Product
        product = ET.SubElement(product_list, "Product",
                                {"name": self.szPrdName})
        ET.SubElement(product, "SchemeName").text = self.szPrdName
        ET.SubElement(product, "FlashTypeID").text = str(self.dwFlashType)
        ET.SubElement(product, "Mode").text = str(self.dwMode)

        NVBackup = ET.SubElement(product, "NVBackup",
                                 backup=str(self.dwIsNvBackup))
        for nc in self.nvitems:
            NVItem = ET.SubElement(NVBackup, "NVItem",
                                   name=nc.name, backup=str(nc.backup))
            ET.SubElement(NVItem, "ID").text = hex(nc.ID)
            BackupFlag = ET.SubElement(NVItem, "BackupFlag", use=str(nc.use))
            if nc.replace:
                ET.SubElement(BackupFlag, "NVFlag",
                              name="Replace", check=str(nc.replace))
            if nc.cont:
                ET.SubElement(BackupFlag, "NVFlag",
                              name="Continue", check=str(nc.cont))

        prod_chips = ET.SubElement(product, "Chips", {"enable": "0"})
        ET.SubElement(prod_chips, "ChipItem", {"id": "0x2222", "name": "L2"})
        ET.SubElement(prod_chips, "ChipItem", {"id": "0x7777", "name": "L7"})

        # SchemeList
        scheme_list = ET.SubElement(root, "SchemeList")

        # SchemeList -> Scheme
        scheme = ET.SubElement(scheme_list, "Scheme", {
                               "name": self.szPrdName})
        for fc in self.files:
            if fc.cfgType == fc.XML_FILE:
                continue

            sf = ET.SubElement(scheme, "File")
            ET.SubElement(sf, "ID").text = fc.szFileID
            ET.SubElement(sf, "IDAlias").text = fc.szFileID
            ET.SubElement(sf, "Type").text = fc.type
            block = ET.SubElement(sf, "Block")
            ET.SubElement(block, "Base").text = hex(fc.dwAddress)
            ET.SubElement(block, "Size").text = hex(fc.fixedSize)
            ET.SubElement(sf, "Flag").text = str(fc.dwFileFlag)
            ET.SubElement(sf, "CheckFlag").text = str(fc.forceCheck)
            ET.SubElement(sf, "Description").text = fc.description

        xml_string = ET.tostring(root, encoding='utf8', method='xml')
        return minidom.parseString(xml_string).toprettyxml(encoding='utf-8', newl='\r\n')

    def pac_gen(self, fname):
        ''' Generate pac, and write to file.
        '''
        # append xml to the file list
        fc = PacFileConfig()
        fc.set_xml_file(self.szPrdName, self._create_xml())

        files = self.files
        files.append(fc)

        # generate header and data of all files
        files_header = []
        files_data = []

        # offset is moving, always for the current file to be handled.
        file_count = len(files)
        offset = struct.calcsize(PAC_HEADER_FMT) + \
            file_count * struct.calcsize(FILE_HEADER_FMT)
        for fc in self.files:
            fheader = fc.file_header(offset)
            fdata = fc.file_data()

            offset += len(fdata)
            files_header.append(fheader)
            files_data.append(fdata)

        # After all files are handled, offset is just the whole pac size
        pac_size = offset
        file_offset = struct.calcsize(PAC_HEADER_FMT)
        magic = 0xFFFAFFFA

        header_no_crc = struct.pack(
            PAC_HEADER_FMT[:-2],
            self.szVersion.encode('utf-16le'),
            pac_size,
            self.szPrdName.encode('utf-16le'),
            self.szPrdVersion.encode('utf-16le'),
            file_count,
            file_offset,
            self.dwMode,
            self.dwFlashType,
            self.dwNandStrategy,
            self.dwIsNvBackup,
            self.dwNandPageType,
            self.szPrdAlias.encode('utf-16le'),
            self.dwOmaDmProductFlag,
            self.dwIsOmaDm,
            self.dwIsPreload,
            RESERVED_BYTE,
            magic)

        crc1 = calc_crc16(0, header_no_crc)
        crc2 = 0
        for d in files_header:
            crc2 = calc_crc16(crc2, d)
        for d in files_data:
            crc2 = calc_crc16(crc2, d)

        header = struct.pack(
            PAC_HEADER_FMT,
            self.szVersion.encode('utf-16le'),
            pac_size,
            self.szPrdName.encode('utf-16le'),
            self.szPrdVersion.encode('utf-16le'),
            file_count,
            file_offset,
            self.dwMode,
            self.dwFlashType,
            self.dwNandStrategy,
            self.dwIsNvBackup,
            self.dwNandPageType,
            self.szPrdAlias.encode('utf-16le'),
            self.dwOmaDmProductFlag,
            self.dwIsOmaDm,
            self.dwIsPreload,
            RESERVED_BYTE,
            magic,
            crc1,
            crc2)

        with open(fname, 'wb') as fh:
            fh.write(header)
            [fh.write(x) for x in files_header]
            [fh.write(x) for x in files_data]

    def pac_combine_appimg(self, in_path, bin_data, out_path, is_sffs):
        find_lua = False
        with open(in_path, 'rb') as fh:
            org_data = fh.read()
        szVersion, pac_size, szPrdName, szPrdVersion, file_count, file_offset, dwMode, dwFlashType, dwNandStrategy, dwIsNvBackup, dwNandPageType, szPrdAlias, dwOmaDmProductFlag, dwIsOmaDm, dwIsPreload, other, magic, crc1, crc2 = struct.unpack(PAC_HEADER_FMT, org_data[0:struct.calcsize(PAC_HEADER_FMT)])
        crc1_check = calc_crc16(0, org_data[0:struct.calcsize(PAC_HEADER_FMT[:-2])])
        if crc1_check != crc1:
            return False
        files_header = []
        files_data = []
        file_header_len = struct.calcsize(FILE_HEADER_FMT)
        offset = struct.calcsize(PAC_HEADER_FMT) + file_count * file_header_len
        if bin_data:
            for i in range(0, file_count):
                start = file_offset + i * file_header_len
                header_data = org_data[start:start+file_header_len]
                header_size, szFileID, szFileName, unuse, data_size, dwFileFlag, defaultCheck, data_offset, dwCanOmitFlag, unuse2, dwAddress, zero0, zero1, zero2, zero3, unuse3 = struct.unpack(FILE_HEADER_FMT, header_data)
                file_data = org_data[data_offset: data_offset + data_size]
                if szFileID.decode('utf-16le').find('APPIMG') != -1:
                    print("is_sffs ", is_sffs)
                    if is_sffs == 0:
                        file_data = bin_data
                if szFileID.decode('utf-16le').find('SFFS') != -1:
                    if is_sffs == 1:
                        file_data = bin_data
                fheader = struct.pack(
                    FILE_HEADER_FMT,
                    file_header_len,
                    szFileID,
                    szFileName,
                    RESERVED_UTF16,
                    len(file_data),
                    dwFileFlag,
                    defaultCheck,
                    offset,
                    dwCanOmitFlag,
                    1,
                    dwAddress, 0, 0, 0, 0,
                    RESERVED_BYTE)
                offset += len(file_data)
                files_header.append(fheader)
                files_data.append(file_data)

            pac_size = offset
            header_no_crc = struct.pack(
                PAC_HEADER_FMT[:-2],
                szVersion,
                pac_size,
                szPrdName,
                szPrdVersion,
                file_count,
                file_offset,
                dwMode,
                dwFlashType,
                dwNandStrategy,
                dwIsNvBackup,
                dwNandPageType,
                szPrdAlias,
                dwOmaDmProductFlag,
                dwIsOmaDm,
                dwIsPreload,
                RESERVED_BYTE,
                magic)
            crc1 = calc_crc16(0, header_no_crc)
            crc2 = 0
            for d in files_header:
                crc2 = calc_crc16(crc2, d)
            for d in files_data:
                crc2 = calc_crc16(crc2, d)

            header = struct.pack(
                PAC_HEADER_FMT,
                szVersion,
                pac_size,
                szPrdName,
                szPrdVersion,
                file_count,
                file_offset,
                dwMode,
                dwFlashType,
                dwNandStrategy,
                dwIsNvBackup,
                dwNandPageType,
                szPrdAlias,
                dwOmaDmProductFlag,
                dwIsOmaDm,
                dwIsPreload,
                RESERVED_BYTE,
                magic,
                crc1,
                crc2)
            with open(out_path, 'wb') as fh:
                fh.write(header)
                [fh.write(x) for x in files_header]
                [fh.write(x) for x in files_data]
                fh.close()
            return True
        else:

            for i in range(0, file_count):
                start = file_offset + i * file_header_len
                header_data = org_data[start:start+file_header_len]
                header_size, szFileID, szFileName, unuse, data_size, dwFileFlag, defaultCheck, data_offset, dwCanOmitFlag, unuse2, dwAddress, zero0, zero1, zero2, zero3, unuse3 = struct.unpack(FILE_HEADER_FMT, header_data)
                file_data = org_data[data_offset: data_offset + data_size]
                if szFileName.decode('utf-16le').find('xml') != -1:
                    dom_tree = minidom.parseString(file_data.decode('utf8'))
                    root_node = dom_tree.documentElement
                    file_node_list = root_node.getElementsByTagName("File")
                    if not file_node_list:
                        return False
                    else:
                        for file_node in file_node_list:
                            ID = file_node.getElementsByTagName("ID")
                            if ID and ID[0].childNodes[0].data.find('APPIMG') != -1:
                                Size = file_node.getElementsByTagName("Size")
                                if Size:
                                    find_lua = int(Size[0].childNodes[0].data, 16)
                                    with open(out_path, 'wb') as f:
                                        f.write(org_data)
                                    return int(Size[0].childNodes[0].data, 16)
            return False
if __name__ == "__main__":
    result = False
    
    if sys.argv[3] == "0":
        core_dir = "core/iot_SDK_720U"
        print("core_dir:",core_dir)
    elif sys.argv[3] == "1":
        core_dir = "core/iot_SDK_720U_TTS"
        print("core_dir:",core_dir)
    else:
        raise IOError("not found core_type")
    
    #检索底层固件
    for i in os.walk(core_dir):
        if i:
            core_name = i[2][0] 
            break
    #两秒钟没有检索到需要的文件就退出
    for i in range(20):
        if os.access(sys.argv[1], os.F_OK) and os.access(core_dir+'/'+core_name, os.F_OK):
            result = True
            break
        else:
            sleep(0.1)
    if not result:
        raise IOError("not found: "+sys.argv[1])

    with open(sys.argv[1], 'rb') as fh:
        bin_data = fh.read()
    object = PacConfig()
    
    object.pac_combine_appimg(core_dir+'/'+core_name,bin_data,sys.argv[2],0)
    
	#通过参数4判断是否替换sffs.img
    if sys.argv[4] != "NULL":
        with open(sys.argv[4], 'rb') as sffs_fh:
            sffs_data = sffs_fh.read()
            object.pac_combine_appimg(sys.argv[2],sffs_data,sys.argv[2],1)

