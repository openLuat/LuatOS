#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Test MCP tools functionality
"""

import sys
import json
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent))

from mcp_server import _build_server


def test_tools():
    """Test MCP tools"""
    print("=" * 60)
    print("Testing MCP Tools")
    print("=" * 60)
    
    # Build server and get tools
    code_root = Path("/opt/sda2/LuatOS")
    mcp = _build_server(code_root, port=8100)
    
    # Test list_libs
    print("\n=== Test list_libs ===")
    try:
        result = mcp.call_tool("list_libs", {})
        print(f"Found {result.get('count', 0)} libraries")
        if result.get('libraries'):
            lib = result['libraries'][0]
            print(f"  First: {lib['name']} - {lib.get('summary', '')[:50]}")
        print("✓ list_libs works")
    except Exception as e:
        print(f"✗ list_libs failed: {e}")
    
    # Test get_lib
    print("\n=== Test get_lib ===")
    try:
        result = mcp.call_tool("get_lib", {"name": "libnet"})
        if result.get('found'):
            print(f"Library: {result['name']}")
            print(f"Summary: {result.get('summary', '')[:50]}")
            print(f"APIs: {len(result.get('apis', []))}")
            print("✓ get_lib works")
        else:
            print(f"✗ get_lib: {result.get('message', 'not found')}")
    except Exception as e:
        print(f"✗ get_lib failed: {e}")
    
    # Test list_modules
    print("\n=== Test list_modules ===")
    try:
        result = mcp.call_tool("list_modules", {})
        print(f"Found {result.get('count', 0)} modules")
        if result.get('modules'):
            mod = result['modules'][0]
            print(f"  First: {mod['name']} ({mod.get('demo_count', 0)} demos)")
        print("✓ list_modules works")
    except Exception as e:
        print(f"✗ list_modules failed: {e}")
    
    # Test list_demos
    print("\n=== Test list_demos ===")
    try:
        result = mcp.call_tool("list_demos", {"module": "Air780EPM"})
        print(f"Module: {result.get('module')}")
        print(f"Demos: {result.get('count', 0)}")
        if result.get('demos'):
            demo = result['demos'][0]
            print(f"  First: {demo.get('name')} - {demo.get('description', '')[:50]}")
        print("✓ list_demos works")
    except Exception as e:
        print(f"✗ list_demos failed: {e}")
    
    # Test search_code
    print("\n=== Test search_code ===")
    try:
        result = mcp.call_tool("search_code", {"query": "MQTT", "scope": "all", "top_k": 3})
        print(f"Query: {result.get('query')}")
        print(f"Results: {result.get('result_count', 0)}")
        if result.get('results'):
            r = result['results'][0]
            print(f"  First: [{r.get('type')}] {r.get('title')} (score: {r.get('score', 0):.3f})")
        print("✓ search_code works")
    except Exception as e:
        print(f"✗ search_code failed: {e}")
    
    # Test resolve_module
    print("\n=== Test resolve_module ===")
    try:
        result = mcp.call_tool("resolve_module", {"query": "如何在 Air8000 上使用 GPIO"})
        print(f"Query: {result.get('query')}")
        print(f"Detected: {result.get('module')} (is_default: {result.get('is_default')})")
        print("✓ resolve_module works")
    except Exception as e:
        print(f"✗ resolve_module failed: {e}")
    
    # Test server_stats
    print("\n=== Test server_stats ===")
    try:
        result = mcp.call_tool("server_stats", {})
        print(f"Uptime: {result.get('uptime_seconds', 0):.1f}s")
        print(f"Total queries: {result.get('total_queries', 0)}")
        stats = result.get('index_stats', {})
        print(f"Chunks: {stats.get('chunk_count', 0)}")
        print(f"Libraries: {stats.get('library_count', 0)}")
        print(f"Demos: {stats.get('demo_count', 0)}")
        print("✓ server_stats works")
    except Exception as e:
        print(f"✗ server_stats failed: {e}")
    
    print("\n" + "=" * 60)
    print("All tool tests completed!")
    print("=" * 60)


if __name__ == "__main__":
    test_tools()
