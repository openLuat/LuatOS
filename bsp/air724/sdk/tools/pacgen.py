#!/usr/bin/env python3
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


def cfg_init(args):
    pc = PacConfig()
    pc.szVersion = args.version
    pc.szPrdName = args.pname
    pc.szPrdVersion = args.pversion
    pc.szPrdAlias = args.palias
    pc.dwMode = args.mode
    pc.dwFlashType = args.flashtype
    pc.dwIsNvBackup = 0
    pc.dwOmaDmProductFlag = args.productflag
    pc.dwIsOmaDm = args.omadm
    pc.dwIsPreload = args.preload
    pc.store_to_json(args.cfg)
    return 0


def cfg_nvitem(args):
    pc = PacConfig()
    pc.load_from_json(args.cfg)
    pc.add_nvitem(args.name, int(args.id, 16),
                  args.use, args.replace, args.cont, args.backup)
    pc.store_to_json(args.cfg)
    return 0


def cfg_host_fdl(args):
    name = args.name if args.name else os.path.basename(args.path)

    pc = PacConfig()
    pc.load_from_json(args.cfg)
    pc.add_host_fdl(args.address, args.size, args.path, name)
    pc.store_to_json(args.cfg)
    return 0


def cfg_fdl2(args):
    name = args.name if args.name else os.path.basename(args.path)

    pc = PacConfig()
    pc.load_from_json(args.cfg)
    pc.add_fdl2(args.address, args.size, args.path, name)
    pc.store_to_json(args.cfg)
    return 0


def cfg_fdl(args):
    name = args.name if args.name else os.path.basename(args.path)

    pc = PacConfig()
    pc.load_from_json(args.cfg)
    pc.add_fdl(args.address, args.size, args.path, name)
    pc.store_to_json(args.cfg)
    return 0


def cfg_image(args):
    name = args.name if args.name else os.path.basename(args.path)
    desc = args.desc if args.desc else args.id

    pc = PacConfig()
    pc.load_from_json(args.cfg)
    pc.add_code(args.id, desc, args.can_omit, args.default_check,
                args.force_check, args.address, args.size,
                args.path, name)
    pc.store_to_json(args.cfg)
    return 0


def cfg_clear_nv(args):
    pc = PacConfig()
    pc.load_from_json(args.cfg)
    pc.add_clear_nv()
    pc.store_to_json(args.cfg)
    return 0

def cfg_clear_sysfs(args):
    pc = PacConfig()
    pc.load_from_json(args.cfg)
    pc.add_clear_sysfs(args.default_check)
    pc.store_to_json(args.cfg)
    return 0

def cfg_erase_flash(args):
    pc = PacConfig()
    pc.load_from_json(args.cfg)
    pc.add_erase_flash(args.id, args.address, args.size)
    pc.store_to_json(args.cfg)
    return 0


def cfg_del_appimg(args):
    pc = PacConfig()
    pc.load_from_json(args.cfg)
    pc.add_del_appimg(args.id)
    pc.store_to_json(args.cfg)
    return 0


def cfg_phase_check(args):
    pc = PacConfig()
    pc.load_from_json(args.cfg)
    pc.add_phase_check()
    pc.store_to_json(args.cfg)
    return 0


def cfg_nv(args):
    name = args.name if args.name else os.path.basename(args.path)

    pc = PacConfig()
    pc.load_from_json(args.cfg)
    pc.add_nv(args.size, args.path, name)
    pc.store_to_json(args.cfg)
    return 0


def cfg_pack_file(args):
    name = args.name if args.name else os.path.basename(args.path)
    desc = args.desc if args.desc else args.id

    pc = PacConfig()
    pc.load_from_json(args.cfg)
    pc.add_pack_file(args.id, desc, args.can_omit, args.default_check,
                     args.force_check, args.path, name)
    pc.store_to_json(args.cfg)
    return 0


def cfg_pack_cpio(args):
    name = args.name if args.name else os.path.basename(args.path)
    desc = args.desc if args.desc else args.id

    pc = PacConfig()
    pc.load_from_json(args.cfg)
    pc.add_pack_cpio(args.id, desc, args.can_omit, args.default_check,
                     args.force_check, args.path, name)
    pc.store_to_json(args.cfg)
    return 0


def dep_gen(args):
    pc = PacConfig()
    pc.load_from_json(args.cfg)
    flist = pc.dep_files()

    norm_list = []
    for f in flist:
        f.replace('\\', '/').replace('//', '/')
        if args.base and not f.startswith('/') and ':' not in f:
            norm_list.append('{}/{}'.format(args.base, f))
        else:
            norm_list.append(f)

    norm_list = sorted(list(set(norm_list)))
    print(';'.join(norm_list))
    return 0


def pac_gen(args):
    pc = PacConfig()
    pc.load_from_json(args.cfg)
    pc.pac_gen(args.fname)
    return 0


def cfg_init_args(sub_parsers):
    parser = sub_parsers.add_parser('cfg-init', help='init configuration file')
    parser.set_defaults(func=cfg_init)
    parser.add_argument('--pname', dest='pname', required=True,
                        help='product name')
    parser.add_argument('--palias', dest='palias', required=True,
                        help='product alias')
    parser.add_argument('--pversion', dest='pversion', required=True,
                        help='product version')
    parser.add_argument('--version', dest='version', required=True,
                        help='version string')
    parser.add_argument('--flashtype', dest='flashtype',
                        type=int, required=True)
    parser.add_argument('--mode', dest='mode', type=int, default=0)
    parser.add_argument('--productflag', dest='productflag',
                        type=int, choices=[0, 1], default=0)
    parser.add_argument('--omadm', dest='omadm',
                        type=int, choices=[0, 1], default=1)
    parser.add_argument('--preload', dest='preload',
                        type=int, choices=[0, 1], default=1)
    parser.add_argument('cfg', help='configuration file name')


def cfg_nvitem_args(sub_parsers):
    parser = sub_parsers.add_parser('cfg-nvitem', help='add backup nvitem')
    parser.set_defaults(func=cfg_nvitem)
    parser.add_argument('-n', '--name', dest='name', required=True,
                        help='nvitem name, for display')
    parser.add_argument('-i', '--id', dest='id', required=True,
                        help='NV id')
    parser.add_argument('--use', dest='use', type=int, choices=[0, 1], default=1,
                        help='nvitem use flag')
    parser.add_argument('--replace', dest='replace', type=int, choices=[0, 1], default=0,
                        help='nvitem replace flag')
    parser.add_argument('--continue', dest='cont', type=int, choices=[0, 1], required=True,
                        help='nvitem replace flag')
    parser.add_argument('--backup', dest='backup', type=int, choices=[0, 1], default=1,
                        help='nvitem backup flag')
    parser.add_argument('cfg', help='configuration file name')


def cfg_host_fdl_args(sub_parsers):
    parser = sub_parsers.add_parser(
        'cfg-host-fdl', help='add fdl through 8910 ROM protocol')
    parser.set_defaults(func=cfg_host_fdl)
    parser.add_argument('-a', '--address', dest='address', type=auto_int, required=True,
                        help='host fdl load address')
    parser.add_argument('-s', '--size', dest='size', type=auto_int, required=True,
                        help='host fdl size')
    parser.add_argument('-p', '--path', dest='path', required=True,
                        help='local host fdl image file path')
    parser.add_argument('-n', '--name', dest='name', default=None,
                        help='host fdl image file name in pac')
    parser.add_argument('cfg', help='configuration file name')


def cfg_fdl2_args(sub_parsers):
    parser = sub_parsers.add_parser(
        'cfg-fdl2', help='add fdl2')
    parser.set_defaults(func=cfg_fdl2)
    parser.add_argument('-a', '--address', dest='address', type=auto_int, required=True,
                        help='fdl2 load address')
    parser.add_argument('-s', '--size', dest='size', type=auto_int, required=True,
                        help='fdl2 size')
    parser.add_argument('-p', '--path', dest='path', required=True,
                        help='local fdl2 image file path')
    parser.add_argument('-n', '--name', dest='name', default=None,
                        help='fdl2 image file name in pac')
    parser.add_argument('cfg', help='configuration file name')


def cfg_fdl_args(sub_parsers):
    parser = sub_parsers.add_parser(
        'cfg-fdl', help='add fdl')
    parser.set_defaults(func=cfg_fdl)
    parser.add_argument('-a', '--address', dest='address', type=auto_int, required=True,
                        help='fdl load address')
    parser.add_argument('-s', '--size', dest='size', type=auto_int, required=True,
                        help='fdl size')
    parser.add_argument('-p', '--path', dest='path', required=True,
                        help='local fdl image file path')
    parser.add_argument('-n', '--name', dest='name', default=None,
                        help='fdl image file name in pac')
    parser.add_argument('cfg', help='configuration file name')


def cfg_image_args(sub_parsers):
    parser = sub_parsers.add_parser(
        'cfg-image', help='add image')
    parser.set_defaults(func=cfg_image)
    parser.add_argument('-i', '--id', dest='id', required=True,
                        help='file ID in pac')
    parser.add_argument('-d', '--desc', dest='desc', default=None,
                        help='file description in pac')
    parser.add_argument('--can-omit', dest='can_omit',
                        type=int, choices=[0, 1], default=0,
                        help='file can omit flag in pac')
    parser.add_argument('--default-check', dest='default_check',
                        type=int, choices=[0, 1], default=1,
                        help='file default check flag in pac')
    parser.add_argument('--force-check', dest='force_check',
                        type=int, choices=[0, 1], default=0,
                        help='file force check flag in pac')
    parser.add_argument('-a', '--address', dest='address', type=auto_int, required=True,
                        help='image load address')
    parser.add_argument('-s', '--size', dest='size', type=auto_int, required=True,
                        help='image size')
    parser.add_argument('-p', '--path', dest='path', required=True,
                        help='local image file path')
    parser.add_argument('-n', '--name', dest='name', default=None,
                        help='image file name in pac')
    parser.add_argument('cfg', help='configuration file name')


def cfg_clear_nv_args(sub_parsers):
    parser = sub_parsers.add_parser(
        'cfg-clear-nv', help='add erase running NV')
    parser.set_defaults(func=cfg_clear_nv)
    parser.add_argument('cfg', help='configuration file name')

def cfg_clear_sysfs_args(sub_parsers):
    parser = sub_parsers.add_parser(
        'cfg-clear-sysfs', help='add erase sys partition')
    parser.set_defaults(func=cfg_clear_sysfs)
    parser.add_argument('--default-check', dest='default_check',
                        type=int, choices=[0, 1], default=1,
                        help='file default check flag in pac')
    parser.add_argument('cfg', help='configuration file name')

def cfg_erase_flash_args(sub_parsers):
    parser = sub_parsers.add_parser(
        'cfg-erase-flash', help='add erase flash')
    parser.set_defaults(func=cfg_erase_flash)
    parser.add_argument('-i', '--id', dest='id', required=True,
                        help='file ID in pac')
    parser.add_argument('-a', '--address', dest='address', type=auto_int, required=True,
                        help='erase flash start address')
    parser.add_argument('-s', '--size', dest='size', type=auto_int, required=True,
                        help='erase flash size')
    parser.add_argument('cfg', help='configuration file name')


def cfg_del_appimg_args(sub_parsers):
    parser = sub_parsers.add_parser(
        'cfg-del-appimg', help='add delete appimg file')
    parser.set_defaults(func=cfg_del_appimg)
    parser.add_argument('-i', '--id', dest='id', required=True,
                        help='file ID in pac')
    parser.add_argument('cfg', help='configuration file name')


def cfg_phase_check_args(sub_parsers):
    parser = sub_parsers.add_parser(
        'cfg-phase-check', help='add phase check')
    parser.set_defaults(func=cfg_phase_check)
    parser.add_argument('cfg', help='configuration file name')


def cfg_nv_args(sub_parsers):
    parser = sub_parsers.add_parser(
        'cfg-nv', help='add NV download')
    parser.set_defaults(func=cfg_nv)
    parser.add_argument('-s', '--size', dest='size', type=auto_int, required=True,
                        help='host fdl size')
    parser.add_argument('-p', '--path', dest='path', required=True,
                        help='local host fdl image file path')
    parser.add_argument('-n', '--name', dest='name', default=None,
                        help='host fdl image file name in pac')
    parser.add_argument('cfg', help='configuration file name')


def cfg_pack_file_args(sub_parsers):
    parser = sub_parsers.add_parser(
        'cfg-pack-file', help='add download one file or directory')
    parser.set_defaults(func=cfg_pack_file)
    parser.add_argument('-i', '--id', dest='id', required=True,
                        help='file ID in pac')
    parser.add_argument('-d', '--desc', dest='desc', default=None,
                        help='file description in pac')
    parser.add_argument('--can-omit', dest='can_omit',
                        type=int, choices=[0, 1], default=0,
                        help='file can omit flag in pac')
    parser.add_argument('--default-check', dest='default_check',
                        type=int, choices=[0, 1], default=1,
                        help='file default check flag in pac')
    parser.add_argument('--force-check', dest='force_check',
                        type=int, choices=[0, 1], default=0,
                        help='file force check flag in pac')
    parser.add_argument('-p', '--path', dest='path', required=True,
                        help='local file or directory path')
    parser.add_argument('-n', '--name', dest='name', default=None,
                        help='remote file or directory path')
    parser.add_argument('cfg', help='configuration file name')


def cfg_pack_cpio_args(sub_parsers):
    parser = sub_parsers.add_parser(
        'cfg-pack-cpio', help='add pre-generated cpio')
    parser.set_defaults(func=cfg_pack_cpio)
    parser.add_argument('-i', '--id', dest='id', required=True,
                        help='file ID in pac')
    parser.add_argument('-d', '--desc', dest='desc', default=None,
                        help='file description in pac')
    parser.add_argument('--can-omit', dest='can_omit',
                        type=int, choices=[0, 1], default=0,
                        help='file can omit flag in pac')
    parser.add_argument('--default-check', dest='default_check',
                        type=int, choices=[0, 1], default=1,
                        help='file default check flag in pac')
    parser.add_argument('--force-check', dest='force_check',
                        type=int, choices=[0, 1], default=0,
                        help='file force check flag in pac')
    parser.add_argument('-p', '--path', dest='path', required=True,
                        help='cpio file or directory path')
    parser.add_argument('-n', '--name', dest='name', default=None,
                        help='cpio file name in pac')
    parser.add_argument('cfg', help='configuration file name')


def pac_gen_args(sub_parsers):
    parser = sub_parsers.add_parser(
        'pac-gen', help='generate pac file')
    parser.set_defaults(func=pac_gen)
    parser.add_argument('cfg', help='configuration file name')
    parser.add_argument('fname', help='pac file name')


def dep_gen_args(sub_parsers):
    parser = sub_parsers.add_parser(
        'dep-gen', help='generate dependency files')
    parser.set_defaults(func=dep_gen)
    parser.add_argument('--base', dest='base', default=None,
                        help='base directory of the dependency files')
    parser.add_argument('cfg', help='configuration file name')


def main(argv):
    parser = argparse.ArgumentParser(description=DESCRIPTION,
                                     formatter_class=argparse.RawDescriptionHelpFormatter)
    sub_parsers = parser.add_subparsers(description="")
    cfg_init_args(sub_parsers)
    cfg_nvitem_args(sub_parsers)
    cfg_host_fdl_args(sub_parsers)
    cfg_fdl2_args(sub_parsers)
    cfg_fdl_args(sub_parsers)
    cfg_image_args(sub_parsers)
    cfg_clear_nv_args(sub_parsers)
    cfg_clear_sysfs_args(sub_parsers)
    cfg_phase_check_args(sub_parsers)
    cfg_nv_args(sub_parsers)
    cfg_erase_flash_args(sub_parsers)
    cfg_del_appimg_args(sub_parsers)
    cfg_pack_file_args(sub_parsers)
    cfg_pack_cpio_args(sub_parsers)
    pac_gen_args(sub_parsers)
    dep_gen_args(sub_parsers)

    if not argv:
        parser.parse_args(["-h"])
        return 0

    cmdlist = list(sub_parsers.choices.keys())

    def splitcmd(args):
        subcmd = []
        for arg in args:
            if arg in cmdlist:
                if subcmd:
                    yield subcmd
                subcmd = [arg]
            else:
                subcmd.append(arg)
        if subcmd:
            yield subcmd

    cmdlines = list(splitcmd(argv))
    namespace = argparse.Namespace()
    for cmdline in cmdlines:
        args = parser.parse_args(cmdline, namespace=namespace)
        if args.__contains__("func"):
            ret = args.func(args)
            if ret != 0:
                return ret
        else:
            parser.parse_args(["-h"])
            return 0
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
