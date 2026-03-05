#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Test script for LuatOS MCP Server
"""

import sys
import json
import time
from pathlib import Path

# Add parent directory to path
sys.path.insert(0, str(Path(__file__).parent))

from mcp_server import _build_index, _discover_libs, _discover_demos, parse_lua_doc_comment


def test_library_discovery():
    """Test library discovery"""
    print("\n=== Testing Library Discovery ===")
    code_root = Path("/opt/sda2/LuatOS")
    lib_files, lib_infos = _discover_libs(code_root)
    
    print(f"Found {len(lib_files)} library files:")
    for i, (name, info) in enumerate(sorted(lib_infos.items())[:5]):
        print(f"  - {name}: {info.name} ({len(info.apis)} APIs)")
    if len(lib_infos) > 5:
        print(f"  ... and {len(lib_infos) - 5} more")
    
    return len(lib_files) > 0


def test_demo_discovery():
    """Test demo discovery"""
    print("\n=== Testing Demo Discovery ===")
    code_root = Path("/opt/sda2/LuatOS")
    demo_files, demos_by_module = _discover_demos(code_root)
    
    print(f"Found demos in {len(demos_by_module)} modules:")
    for module, demos in sorted(demos_by_module.items()):
        print(f"  - {module}: {len(demos)} demos")
    
    return len(demo_files) > 0


def test_lua_parsing():
    """Test Lua documentation parsing"""
    print("\n=== Testing Lua Doc Parsing ===")
    
    sample_lua = '''
--[[
@module libnet
@summary libnet 在socket库基础上的同步阻塞api
@version 1.0
@date    2023.03.16
@author  lisiqi
]]

--[[
阻塞等待网卡的网络连接上
@api libnet.waitLink(taskName,timeout,...)
@string 任务标志
@int 超时时间
@return boolean 失败或超时返回false
]]
function libnet.waitLink(taskName, timeout, ...)
    -- implementation
end
'''
    
    libs, funcs = parse_lua_doc_comment(sample_lua)
    
    print(f"Parsed {len(libs)} libraries, {len(funcs)} functions")
    if libs:
        lib = libs[0]
        print(f"  Library: {lib.name}")
        print(f"  Summary: {lib.summary}")
        print(f"  APIs: {len(lib.apis)}")
    
    return len(libs) > 0 and len(funcs) > 0


def test_index_building():
    """Test index building"""
    print("\n=== Testing Index Building ===")
    code_root = Path("/opt/sda2/LuatOS")
    
    start = time.time()
    chunks, lib_infos, demos_by_module = _build_index(str(code_root))
    elapsed = time.time() - start
    
    print(f"Built index with {len(chunks)} chunks in {elapsed:.2f}s")
    print(f"  Libraries: {len(lib_infos)}")
    print(f"  Demo modules: {len(demos_by_module)}")
    
    # Check chunk types
    lib_chunks = [c for c in chunks if c.chunk_type == "lib"]
    demo_chunks = [c for c in chunks if c.chunk_type == "demo"]
    print(f"  Library chunks: {len(lib_chunks)}")
    print(f"  Demo chunks: {len(demo_chunks)}")
    
    return len(chunks) > 0


def main():
    print("=" * 60)
    print("LuatOS MCP Server Test Suite")
    print("=" * 60)
    
    results = []
    
    try:
        results.append(("Library Discovery", test_library_discovery()))
        results.append(("Demo Discovery", test_demo_discovery()))
        results.append(("Lua Doc Parsing", test_lua_parsing()))
        results.append(("Index Building", test_index_building()))
        
        print("\n" + "=" * 60)
        print("Test Results:")
        print("=" * 60)
        
        all_passed = True
        for name, passed in results:
            status = "✓ PASS" if passed else "✗ FAIL"
            print(f"  {status}: {name}")
            if not passed:
                all_passed = False
        
        print("=" * 60)
        if all_passed:
            print("All tests passed!")
            return 0
        else:
            print("Some tests failed!")
            return 1
            
    except Exception as e:
        print(f"\n✗ Test suite failed with error: {e}")
        import traceback
        traceback.print_exc()
        return 1


if __name__ == "__main__":
    sys.exit(main())
