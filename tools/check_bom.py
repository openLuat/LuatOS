#!/usr/bin/python
# -*- coding: UTF-8 -*-
"""
检查目录内是否存在带 UTF-8 BOM 的文件。

用法:
    python tools/check_bom.py [路径] [扩展名 ...]

示例:
    python tools/check_bom.py
    python tools/check_bom.py luat/modules .c .h
"""

import os
import sys

UTF8_BOM = b'\xef\xbb\xbf'

DEFAULT_EXTS = ['.c', '.h', '.cpp', '.lua', '.py', '.txt', '.md']


def is_bom_file(path):
    """读取文件前3字节，判断是否以 UTF-8 BOM 开头。"""
    try:
        with open(path, 'rb') as f:
            return f.read(3) == UTF8_BOM
    except (IOError, OSError):
        return False


def walk_files(root, exts):
    """递归收集指定扩展名的文件。"""
    result = []
    for home, _, files in os.walk(root):
        for filename in files:
            if any(filename.endswith(ext) for ext in exts):
                result.append(os.path.join(home, filename))
    return result


def main():
    root = sys.argv[1] if len(sys.argv) > 1 else os.getcwd()
    exts = sys.argv[2:] if len(sys.argv) > 2 else DEFAULT_EXTS

    root = os.path.abspath(root)
    if not os.path.isdir(root):
        print('路径不存在: ' + root)
        sys.exit(1)

    files = walk_files(root, exts)
    bom_files = [f for f in files if is_bom_file(f)]

    print('Scan path: ' + root)
    print('Extensions: ' + ', '.join(exts))
    print('Files scanned: ' + str(len(files)))

    if bom_files:
        print('\nFiles with UTF-8 BOM:')
        for f in bom_files:
            print('  ' + f)
        sys.exit(1)
    else:
        print('No UTF-8 BOM files found.')
        sys.exit(0)


if __name__ == '__main__':
    main()
