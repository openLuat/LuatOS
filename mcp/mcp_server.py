#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
LuatOS Code MCP Server (luatos-code)

Provides AI tools with access to:
- Extension libraries from script/libs/ (Lua libraries)
- Module demo code from module/ directory

Default port: 8100 (SSE mode)
"""

import argparse
import inspect
import logging
import os
import re
import threading
import time
from collections import defaultdict
from dataclasses import dataclass, asdict, field
from functools import lru_cache
from pathlib import Path
from typing import Dict, List, Optional, Tuple, Any

from mcp.server.fastmcp import FastMCP
from mcp.server.transport_security import TransportSecuritySettings

# Lazy ChromaDB import — graceful degradation if not installed
try:
    import chromadb
    CHROMADB_AVAILABLE = True
except ImportError:
    CHROMADB_AVAILABLE = False

# Configure logging
logging.basicConfig(level=logging.INFO, format='%(asctime)s - %(levelname)s - %(message)s')
logger = logging.getLogger(__name__)

# Constants
DEFAULT_MODULE = "air780epm"
MODULE_PATTERN = re.compile(r"\bair[0-9][0-9a-z]*\b", re.IGNORECASE)
CHROMA_COLLECTION_NAME = "luatos_code"
CHROMA_PERSIST_DIR_NAME = ".chroma_code"
RRF_K = 60  # Reciprocal Rank Fusion constant
FRESHNESS_CHECK_INTERVAL_SECONDS = 3600.0
GITEE_BASE_URL = "https://gitee.com/openLuat/LuatOS/tree/master/"

# Global state
_last_index_build_time: float = 0.0
_code_root_for_mtime: Optional[str] = None
_last_freshness_check_time: float = 0.0

# Derived caches
_derived_cache_identity: int = 0
_chunk_token_cache: Dict[str, set] = {}
_chunk_text_cache: Dict[str, str] = {}
_chunk_lookup_cache: Dict[str, "CodeChunk"] = {}
_chunks_by_type_cache: Dict[str, List["CodeChunk"]] = defaultdict(list)


# ---------------------------------------------------------------------------
# Data structures
# ---------------------------------------------------------------------------

@dataclass
class LuaAPIDoc:
    """Parsed Lua API documentation"""
    name: str
    summary: str = ""
    params: List[Dict[str, str]] = field(default_factory=list)
    returns: List[str] = field(default_factory=list)
    api_type: str = ""  # @api value


@dataclass
class LibraryInfo:
    """Library metadata"""
    name: str
    summary: str
    version: str
    author: str
    date: str
    file_path: str
    apis: List[LuaAPIDoc] = field(default_factory=list)


@dataclass
class CodeChunk:
    """A chunk of code for indexing"""
    chunk_type: str  # "lib" or "demo"
    module: str  # library name or module model
    file_path: str
    title: str
    chunk_id: int
    text: str
    metadata: Dict[str, Any] = field(default_factory=dict)


# ---------------------------------------------------------------------------
# ChromaDB vector index
# ---------------------------------------------------------------------------

class ChromaIndex:
    """Manages ChromaDB vector index with lazy initialization and background reindexing."""

    def __init__(self, persist_dir: Path):
        self._persist_dir = persist_dir
        self._client = None
        self._collection = None
        self._indexed_chunk_count: int = 0
        self._last_build_time: float = 0.0
        self._reindex_lock = threading.Lock()
        self._reindexing: bool = False

    @property
    def is_available(self) -> bool:
        return CHROMADB_AVAILABLE

    @property
    def indexed_count(self) -> int:
        return self._indexed_chunk_count

    @property
    def last_build_time(self) -> float:
        return self._last_build_time

    def ensure_ready(self) -> bool:
        if not CHROMADB_AVAILABLE:
            return False
        if self._client is not None:
            return True
        try:
            self._persist_dir.mkdir(parents=True, exist_ok=True)
            self._client = chromadb.PersistentClient(path=str(self._persist_dir))
            self._collection = self._client.get_or_create_collection(
                name=CHROMA_COLLECTION_NAME,
                metadata={"hnsw:space": "cosine"},
            )
            self._indexed_chunk_count = self._collection.count()
            logger.info(
                f"ChromaDB ready: {self._indexed_chunk_count} vectors in "
                f"'{CHROMA_COLLECTION_NAME}' at {self._persist_dir}"
            )
            return True
        except Exception as e:
            logger.error(f"ChromaDB initialization failed: {e}")
            self._client = None
            self._collection = None
            return False

    def reindex(self, chunks: List[CodeChunk]) -> None:
        """Full reindex in a background thread. Non-blocking."""
        if not self.ensure_ready():
            return
        if self._reindexing:
            logger.info("ChromaDB reindex already in progress, skipping")
            return

        def _do_reindex():
            self._reindexing = True
            try:
                with self._reindex_lock:
                    self._client.delete_collection(CHROMA_COLLECTION_NAME)
                    self._collection = self._client.create_collection(
                        name=CHROMA_COLLECTION_NAME,
                        metadata={"hnsw:space": "cosine"},
                    )
                    batch_size = 500
                    for i in range(0, len(chunks), batch_size):
                        batch = chunks[i : i + batch_size]
                        ids = [f"{c.file_path}::{c.chunk_id}" for c in batch]
                        documents = [c.text for c in batch]
                        metadatas = [
                            {
                                "chunk_type": c.chunk_type,
                                "module": c.module,
                                "file_path": c.file_path,
                                "title": c.title,
                                "chunk_id": c.chunk_id,
                            }
                            for c in batch
                        ]
                        self._collection.add(ids=ids, documents=documents, metadatas=metadatas)
                    self._indexed_chunk_count = self._collection.count()
                    self._last_build_time = time.time()
                    logger.info(f"ChromaDB reindex complete: {self._indexed_chunk_count} chunks")
            except Exception as e:
                logger.error(f"ChromaDB reindex failed: {e}")
            finally:
                self._reindexing = False

        thread = threading.Thread(target=_do_reindex, daemon=True)
        thread.start()

    def query(
        self,
        query_text: str,
        n_results: int = 20,
        where_filter: Optional[dict] = None,
    ) -> List[Tuple[str, float]]:
        if not self.ensure_ready() or self._indexed_chunk_count == 0 or self._reindexing:
            return []
        try:
            kwargs: Dict[str, object] = {
                "query_texts": [query_text],
                "n_results": min(n_results, self._indexed_chunk_count),
            }
            if where_filter:
                kwargs["where"] = where_filter
            results = self._collection.query(**kwargs)
            ids = results.get("ids", [[]])[0]
            distances = results.get("distances", [[]])[0]
            return list(zip(ids, distances))
        except Exception as e:
            logger.error(f"ChromaDB query failed: {e}")
            return []

    def invalidate(self) -> None:
        self._client = None
        self._collection = None
        self._indexed_chunk_count = 0


# ---------------------------------------------------------------------------
# Observability
# ---------------------------------------------------------------------------

class ServerStats:
    """Tracks server metrics: tool calls, latency, zero-result queries."""

    def __init__(self):
        self._start_time: float = time.time()
        self._total_queries: int = 0
        self._zero_result_queries: List[dict] = []
        self._tool_call_counts: Dict[str, int] = defaultdict(int)
        self._top_queries: Dict[str, int] = defaultdict(int)

    @property
    def uptime_seconds(self) -> float:
        return time.time() - self._start_time

    def record_call(
        self,
        tool_name: str,
        query: str,
        result_count: int,
        elapsed_ms: float,
    ) -> None:
        self._total_queries += 1
        self._tool_call_counts[tool_name] += 1
        if query:
            self._top_queries[query] += 1

        logger.info(
            f"[{tool_name}] query={query!r} results={result_count} elapsed={elapsed_ms:.1f}ms"
        )
        if result_count == 0 and query:
            entry = {
                "tool": tool_name,
                "query": query,
                "elapsed_ms": round(elapsed_ms, 2),
                "timestamp": time.time(),
            }
            self._zero_result_queries.append(entry)
            if len(self._zero_result_queries) > 100:
                self._zero_result_queries = self._zero_result_queries[-100:]
            logger.warning(f"[ZERO-RESULT] tool={tool_name} query={query!r}")

    def get_summary(
        self,
        chunk_count: int,
        lib_count: int,
        demo_count: int,
        last_build_time: float,
        chroma_count: int,
    ) -> dict:
        sorted_queries = sorted(
            self._top_queries.items(), key=lambda x: x[1], reverse=True
        )[:10]
        return {
            "uptime_seconds": round(self.uptime_seconds, 1),
            "total_queries": self._total_queries,
            "tool_call_counts": dict(self._tool_call_counts),
            "index_stats": {
                "chunk_count": chunk_count,
                "library_count": lib_count,
                "demo_count": demo_count,
                "chroma_indexed_count": chroma_count,
                "last_build_time": last_build_time,
            },
            "top_queries": [{"query": q, "count": c} for q, c in sorted_queries],
            "zero_result_query_count": len(self._zero_result_queries),
            "recent_zero_result_queries": [
                {"query": e["query"], "tool": e["tool"]}
                for e in self._zero_result_queries[-10:]
            ],
        }


# ---------------------------------------------------------------------------
# Lua Documentation Parsing
# ---------------------------------------------------------------------------

def parse_lua_doc_comment(content: str) -> Tuple[List[LibraryInfo], List[Dict]]:
    """
    Parse Lua documentation comments from file content.
    Returns (library_infos, function_docs)
    """
    libraries = []
    functions = []
    
    # Pattern for block comments with @ tags
    block_pattern = re.compile(
        r'--\[\[\s*\n?(.*?)\n?\]\]',
        re.DOTALL
    )
    
    # Parse module-level doc
    module_match = block_pattern.search(content)
    lib_info = None
    
    if module_match:
        block = module_match.group(1)
        name = re.search(r'@module\s+(\S+)', block)
        summary = re.search(r'@summary\s+(\S.+?)(?:\n@|\Z)', block, re.DOTALL)
        version = re.search(r'@version\s+(\S+)', block)
        author = re.search(r'@author\s+(\S+)', block)
        date = re.search(r'@date\s+(\S+)', block)
        
        if name:
            lib_info = LibraryInfo(
                name=name.group(1),
                summary=summary.group(1).strip() if summary else "",
                version=version.group(1) if version else "",
                author=author.group(1) if author else "",
                date=date.group(1) if date else "",
                file_path="",
                apis=[]
            )
            libraries.append(lib_info)
    
    # Parse function docs
    for match in block_pattern.finditer(content):
        block = match.group(1)
        if '@api' in block:
            api_match = re.search(r'@api\s+(\S+)', block)
            if api_match:
                api_doc = LuaAPIDoc(
                    name=api_match.group(1),
                    summary=re.search(r'^([^@\n].*?)(?:\n@|\Z)', block, re.DOTALL)
                           .group(1).strip() if re.search(r'^([^@\n].*?)(?:\n@|\Z)', block, re.DOTALL) else "",
                    api_type="function"
                )
                
                # Parse params
                for param_match in re.finditer(r'@(\w+)\s+(\S+)\s+(\S.+?)(?=\n@|\Z)', block):
                    ptype, pname, pdesc = param_match.groups()
                    if ptype in ('param', 'string', 'int', 'bool', 'table', 'function', 'userdata'):
                        api_doc.params.append({
                            'type': ptype if ptype != 'param' else 'any',
                            'name': pname,
                            'desc': pdesc.strip()
                        })
                
                # Parse returns
                ret_match = re.search(r'@return\s+(\S.*)', block)
                if ret_match:
                    api_doc.returns = [r.strip() for r in ret_match.group(1).split(',')]
                
                functions.append({
                    'api': api_doc,
                    'lib': lib_info.name if lib_info else ""
                })
                if lib_info:
                    lib_info.apis.append(api_doc)
    
    return libraries, functions


# ---------------------------------------------------------------------------
# Text processing helpers
# ---------------------------------------------------------------------------

def _clean_text(text: str) -> str:
    text = re.sub(r"!\[[^\]]*\]\([^\)]*\)", " ", text)
    text = re.sub(r"\[([^\]]+)\]\([^\)]*\)", r"\1", text)
    text = re.sub(r"`([^`]+)`", r" \1 ", text)
    text = re.sub(r"```.*?```", " ", text, flags=re.DOTALL)
    text = re.sub(r"\s+", " ", text)
    return text.strip()


def _tokenize(text: str) -> List[str]:
    """Tokenize text using jieba for Chinese + basic tokenization"""
    content = text.lower()
    # Simple tokenization for now (jieba optional)
    tokens = re.findall(r'[a-z0-9_+#.-]+', content)
    # Also extract Chinese characters
    chinese = re.findall(r'[\u4e00-\u9fff]{2,}', content)
    return tokens + chinese


def _chunk_by_paragraphs(text: str, max_chars: int = 900) -> List[str]:
    parts = [item.strip() for item in re.split(r"\n\s*\n", text) if item.strip()]
    if not parts:
        return []

    chunks: List[str] = []
    buffer = ""
    for part in parts:
        if len(buffer) + len(part) + 1 <= max_chars:
            buffer = f"{buffer}\n{part}".strip()
            continue
        if buffer:
            chunks.append(buffer.strip())
        if len(part) <= max_chars:
            buffer = part
            continue
        start = 0
        while start < len(part):
            chunks.append(part[start : start + max_chars].strip())
            start += max_chars
        buffer = ""
    if buffer:
        chunks.append(buffer.strip())
    return chunks


def _chunk_key(chunk: CodeChunk) -> str:
    return f"{chunk.file_path}::{chunk.chunk_id}"


def _ensure_derived_caches(chunks: List[CodeChunk]) -> None:
    global _derived_cache_identity
    global _chunk_token_cache, _chunk_text_cache, _chunk_lookup_cache, _chunks_by_type_cache

    chunks_identity = id(chunks)
    if _derived_cache_identity == chunks_identity:
        return

    token_cache: Dict[str, set] = {}
    text_cache: Dict[str, str] = {}
    lookup_cache: Dict[str, CodeChunk] = {}
    by_type: Dict[str, List[CodeChunk]] = defaultdict(list)

    for chunk in chunks:
        key = _chunk_key(chunk)
        text = f"{chunk.title} {chunk.text}".lower()
        text_cache[key] = text
        token_cache[key] = set(_tokenize(text))
        lookup_cache[key] = chunk
        by_type[chunk.chunk_type].append(chunk)

    _chunk_token_cache = token_cache
    _chunk_text_cache = text_cache
    _chunk_lookup_cache = lookup_cache
    _chunks_by_type_cache = by_type
    _derived_cache_identity = chunks_identity


def _score_chunk(
    query_tokens: List[str],
    query_text: str,
    chunk: CodeChunk,
    text: Optional[str] = None,
    token_set: Optional[set] = None,
) -> float:
    text = text if text is not None else f"{chunk.title} {chunk.text}".lower()
    if not text.strip():
        return 0.0

    score = 0.0
    token_set = token_set if token_set is not None else set(_tokenize(text))
    for token in query_tokens:
        if token in token_set:
            score += 2.0
        elif token in text:
            score += 1.0

    if query_text and query_text in text:
        score += 5.0
    if chunk.title and any(token in chunk.title.lower() for token in query_tokens):
        score += 1.5
    return score


def _reciprocal_rank_fusion(
    keyword_ranked: List[Tuple[float, CodeChunk]],
    vector_ranked: List[Tuple[str, float]],
    chunk_lookup: Dict[str, CodeChunk],
    k: int = RRF_K,
) -> List[Tuple[float, CodeChunk]]:
    """Merge keyword and vector rankings using Reciprocal Rank Fusion."""
    rrf_scores: Dict[str, float] = defaultdict(float)
    chunk_map: Dict[str, CodeChunk] = {}

    for rank, (score, chunk) in enumerate(keyword_ranked):
        key = f"{chunk.file_path}::{chunk.chunk_id}"
        rrf_scores[key] += 1.0 / (k + rank + 1)
        chunk_map[key] = chunk

    for rank, (chunk_id_str, distance) in enumerate(vector_ranked):
        rrf_scores[chunk_id_str] += 1.0 / (k + rank + 1)
        if chunk_id_str not in chunk_map and chunk_id_str in chunk_lookup:
            chunk_map[chunk_id_str] = chunk_lookup[chunk_id_str]

    fused: List[Tuple[float, CodeChunk]] = []
    for key, rrf_score in rrf_scores.items():
        if key in chunk_map:
            fused.append((rrf_score, chunk_map[key]))
    fused.sort(key=lambda pair: pair[0], reverse=True)
    return fused


def _find_module_case_insensitive(module_name: str, demos_by_module: Dict[str, List[Dict]]) -> Optional[str]:
    """Find module name case-insensitively, return the original case name.
    
    Supports multi-module directories separated by underscores.
    Example: 'Air780EHM_Air780EHV_Air780EGH' matches 'Air780EHM', 'Air780EHV', or 'Air780EGH'.
    """
    if not module_name:
        return None
    module_lower = module_name.strip().lower()
    
    for key in demos_by_module.keys():
        key_lower = key.lower()
        # Direct match
        if key_lower == module_lower:
            return key
        # Multi-module directory (separated by underscores)
        if '_' in key:
            sub_modules = key_lower.split('_')
            if module_lower in sub_modules:
                return key
    
    return None


# ---------------------------------------------------------------------------
# Index building
# ---------------------------------------------------------------------------

def _discover_libs(code_root: Path) -> Tuple[List[Path], Dict[str, LibraryInfo]]:
    """Discover all Lua libraries in script/libs/"""
    libs_dir = code_root / "script" / "libs"
    lib_files = []
    lib_infos = {}
    
    if libs_dir.exists():
        for lua_file in libs_dir.glob("*.lua"):
            lib_files.append(lua_file)
            try:
                content = lua_file.read_text(encoding='utf-8', errors='ignore')
                libs, _ = parse_lua_doc_comment(content)
                if libs:
                    lib_info = libs[0]
                    lib_info.file_path = str(lua_file.relative_to(code_root))
                    lib_infos[lua_file.name] = lib_info
            except Exception as e:
                logger.warning(f"Failed to parse {lua_file}: {e}")
    
    return lib_files, lib_infos


def _discover_demos(code_root: Path) -> Tuple[List[Path], Dict[str, List[Dict]]]:
    """Discover all module demos in module/*/demo/"""
    module_dir = code_root / "module"
    demo_files = []
    demos_by_module = {}
    
    if module_dir.exists():
        for module_subdir in module_dir.iterdir():
            if not module_subdir.is_dir():
                continue
            module_name = module_subdir.name
            demo_dir = module_subdir / "demo"
            
            if demo_dir.exists():
                module_demos = []
                for lua_file in demo_dir.rglob("*.lua"):
                    demo_files.append(lua_file)
                    try:
                        content = lua_file.read_text(encoding='utf-8', errors='ignore')
                        # Extract simple description from first comment
                        desc = ""
                        first_comment = re.search(r'--\[\[\s*\n?(.*?)\n?\]\]', content, re.DOTALL)
                        if first_comment:
                            desc = first_comment.group(1).split('\n')[0][:100]
                        
                        module_demos.append({
                            'name': lua_file.stem,
                            'path': str(lua_file.relative_to(code_root)),
                            'description': desc
                        })
                    except Exception as e:
                        logger.warning(f"Failed to read {lua_file}: {e}")
                
                demos_by_module[module_name] = module_demos
    
    return demo_files, demos_by_module


@lru_cache(maxsize=2)
def _build_index(code_root_str: str) -> Tuple[List[CodeChunk], Dict[str, LibraryInfo], Dict[str, List[Dict]]]:
    """Build index of all code chunks from libraries and demos."""
    code_root = Path(code_root_str)
    chunks: List[CodeChunk] = []
    
    # Discover libraries
    lib_files, lib_infos = _discover_libs(code_root)
    
    # Discover demos
    demo_files, demos_by_module = _discover_demos(code_root)
    
    # Index libraries
    for lua_file in lib_files:
        try:
            content = lua_file.read_text(encoding='utf-8', errors='ignore')
            rel_path = str(lua_file.relative_to(code_root))
            lib_name = lua_file.stem
            
            # Parse documentation
            libs, funcs = parse_lua_doc_comment(content)
            lib_info = libs[0] if libs else None
            
            title = lib_info.name if lib_info else lib_name
            summary = lib_info.summary if lib_info else ""
            
            # Create chunks by paragraphs
            for idx, chunk_text in enumerate(_chunk_by_paragraphs(content)):
                chunks.append(CodeChunk(
                    chunk_type="lib",
                    module=lib_name,
                    file_path=rel_path,
                    title=title,
                    chunk_id=idx,
                    text=chunk_text,
                    metadata={
                        "summary": summary,
                        "is_api_doc": "@api" in chunk_text or "@param" in chunk_text
                    }
                ))
        except Exception as e:
            logger.error(f"Failed to index library {lua_file}: {e}")
    
    # Index demos
    for lua_file in demo_files:
        try:
            content = lua_file.read_text(encoding='utf-8', errors='ignore')
            rel_path = str(lua_file.relative_to(code_root))
            
            # Extract module name from path (module/MODULE_NAME/demo/...)
            parts = lua_file.relative_to(code_root).parts
            module_name = parts[1] if len(parts) > 1 else "unknown"
            demo_name = lua_file.stem
            
            # Create chunks by paragraphs
            for idx, chunk_text in enumerate(_chunk_by_paragraphs(content)):
                chunks.append(CodeChunk(
                    chunk_type="demo",
                    module=module_name,
                    file_path=rel_path,
                    title=demo_name,
                    chunk_id=idx,
                    text=chunk_text,
                    metadata={
                        "demo_name": demo_name
                    }
                ))
        except Exception as e:
            logger.error(f"Failed to index demo {lua_file}: {e}")
    
    logger.info(f"Index built: {len(chunks)} chunks from {len(lib_files)} libs and {len(demo_files)} demos")
    return chunks, lib_infos, demos_by_module


def _check_freshness(code_root_str: str) -> bool:
    """Check if any code files have changed since last index build."""
    global _last_index_build_time
    if _last_index_build_time == 0.0:
        return False

    code_root = Path(code_root_str)
    
    # Check library files
    libs_dir = code_root / "script" / "libs"
    if libs_dir.exists():
        for lua_file in libs_dir.glob("*.lua"):
            try:
                if lua_file.stat().st_mtime > _last_index_build_time:
                    return True
            except OSError:
                continue
    
    # Check demo files (sample up to 50)
    module_dir = code_root / "module"
    checked = 0
    if module_dir.exists():
        for demo_file in module_dir.rglob("demo/*.lua"):
            if checked >= 50:
                break
            checked += 1
            try:
                if demo_file.stat().st_mtime > _last_index_build_time:
                    return True
            except OSError:
                continue
    
    return False


def _get_index_and_sync(
    code_root_str: str,
    chroma: ChromaIndex,
) -> Tuple[List[CodeChunk], Dict[str, LibraryInfo], Dict[str, List[Dict]]]:
    """Get index with mtime freshness check, sync ChromaDB if needed."""
    global _last_index_build_time, _code_root_for_mtime, _last_freshness_check_time

    # Check freshness with interval throttling
    now = time.time()
    should_check = (
        _last_index_build_time > 0
        and (now - _last_freshness_check_time) >= FRESHNESS_CHECK_INTERVAL_SECONDS
    )
    if should_check:
        _last_freshness_check_time = now
        if _check_freshness(code_root_str):
            logger.info("Code change detected, invalidating index cache")
            _build_index.cache_clear()
            if chroma.is_available:
                chroma.invalidate()
            _last_index_build_time = 0.0

    chunks, lib_infos, demos_by_module = _build_index(code_root_str)
    _ensure_derived_caches(chunks)

    # Update build timestamp
    if _last_index_build_time == 0.0 or _code_root_for_mtime != code_root_str:
        _last_index_build_time = time.time()
        _code_root_for_mtime = code_root_str

    # Sync ChromaDB
    if chroma.is_available:
        chroma.ensure_ready()
        if chroma.indexed_count == 0 or chroma.indexed_count != len(chunks):
            chroma.reindex(chunks)
            _last_index_build_time = time.time()

    return chunks, lib_infos, demos_by_module


# ---------------------------------------------------------------------------
# MCP server builder
# ---------------------------------------------------------------------------

def _build_server(code_root: Path, port: int = 8100) -> FastMCP:
    mcp = FastMCP("luatos-code", host="0.0.0.0", port=port)

    # ChromaDB index
    project_root = code_root
    chroma_persist_dir = project_root / CHROMA_PERSIST_DIR_NAME
    chroma_index = ChromaIndex(persist_dir=chroma_persist_dir)

    # Observability
    stats = ServerStats()

    @mcp.tool()
    def list_libs() -> Dict[str, object]:
        """List all available extension libraries with brief info."""
        t0 = time.time()
        _, lib_infos, _ = _get_index_and_sync(str(code_root), chroma_index)
        
        results = []
        for name, info in sorted(lib_infos.items()):
            results.append({
                "name": info.name or name,
                "file": name,
                "summary": info.summary,
                "version": info.version,
                "author": info.author,
                "api_count": len(info.apis),
                "url": f"https://gitee.com/openLuat/LuatOS/tree/master/{info.file_path}"
            })
        
        elapsed_ms = (time.time() - t0) * 1000
        stats.record_call("list_libs", "", len(results), elapsed_ms)
        
        return {
            "count": len(results),
            "libraries": results
        }

    @mcp.tool()
    def get_lib(name: str) -> Dict[str, object]:
        """Get full content and documentation of a specific library."""
        t0 = time.time()
        _, lib_infos, _ = _get_index_and_sync(str(code_root), chroma_index)
        
        # Try exact match first, then partial
        lib_info = None
        if name in lib_infos:
            lib_info = lib_infos[name]
        else:
            for key, info in lib_infos.items():
                if info.name == name or key.lower() == name.lower():
                    lib_info = info
                    break
        
        if not lib_info:
            elapsed_ms = (time.time() - t0) * 1000
            stats.record_call("get_lib", name, 0, elapsed_ms)
            return {
                "found": False,
                "message": f"Library '{name}' not found. Use list_libs() to see available libraries."
            }
        
        # Read full content
        lib_path = code_root / lib_info.file_path
        full_content = ""
        try:
            full_content = lib_path.read_text(encoding='utf-8', errors='ignore')
        except Exception as e:
            logger.error(f"Failed to read library file: {e}")
        
        apis = []
        for api in lib_info.apis:
            apis.append({
                "name": api.name,
                "summary": api.summary,
                "params": api.params,
                "returns": api.returns
            })
        
        elapsed_ms = (time.time() - t0) * 1000
        stats.record_call("get_lib", name, 1, elapsed_ms)
        
        return {
            "found": True,
            "name": lib_info.name,
            "summary": lib_info.summary,
            "version": lib_info.version,
            "author": lib_info.author,
            "date": lib_info.date,
            "file_path": lib_info.file_path,
            "url": f"https://gitee.com/openLuat/LuatOS/tree/master/{lib_info.file_path}",
            "apis": apis,
            "content": full_content
        }

    @mcp.tool()
    def list_modules() -> Dict[str, object]:
        """List all module models with demo counts."""
        t0 = time.time()
        _, _, demos_by_module = _get_index_and_sync(str(code_root), chroma_index)
        
        results = []
        for module_name, demos in sorted(demos_by_module.items()):
            results.append({
                "name": module_name,
                "demo_count": len(demos)
            })
        
        elapsed_ms = (time.time() - t0) * 1000
        stats.record_call("list_modules", "", len(results), elapsed_ms)
        
        return {
            "count": len(results),
            "modules": results
        }

    @mcp.tool()
    def list_demos(module: str) -> Dict[str, object]:
        """List all demos for a specific module."""
        t0 = time.time()
        _, _, demos_by_module = _get_index_and_sync(str(code_root), chroma_index)
        
        # Case-insensitive module lookup
        target_module = _find_module_case_insensitive(module.strip(), demos_by_module)
        if target_module is None:
            elapsed_ms = (time.time() - t0) * 1000
            stats.record_call("list_demos", module, 0, elapsed_ms)
            return {
                "module": module.strip(),
                "count": 0,
                "demos": [],
                "note": f"Module '{module}' not found. Available: {list(demos_by_module.keys())}"
            }
        
        demos = demos_by_module.get(target_module, [])
        
        # Add URL to each demo
        demos_with_url = []
        for d in demos:
            demo_copy = dict(d)
            demo_copy['url'] = f"https://gitee.com/openLuat/LuatOS/tree/master/{d['path']}"
            demos_with_url.append(demo_copy)
        
        elapsed_ms = (time.time() - t0) * 1000
        stats.record_call("list_demos", module, len(demos), elapsed_ms)
        
        return {
            "module": target_module,
            "count": len(demos),
            "demos": demos_with_url
        }

    @mcp.tool()
    def get_demo(module: str, demo_name: str) -> Dict[str, object]:
        """Get full content of a specific demo."""
        t0 = time.time()
        _, _, demos_by_module = _get_index_and_sync(str(code_root), chroma_index)
        
        # Case-insensitive module lookup
        target_module = _find_module_case_insensitive(module.strip(), demos_by_module)
        if target_module is None:
            elapsed_ms = (time.time() - t0) * 1000
            stats.record_call("get_demo", f"{module}/{demo_name}", 0, elapsed_ms)
            return {
                "found": False,
                "message": f"Module '{module}' not found. Use list_modules() to see available modules."
            }
        
        demos = demos_by_module.get(target_module, [])
        
        # Find the demo (case-insensitive for demo_name too)
        demo_info = None
        for d in demos:
            if d['name'] == demo_name or d['name'].lower() == demo_name.lower():
                demo_info = d
                break
        
        if not demo_info:
            elapsed_ms = (time.time() - t0) * 1000
            stats.record_call("get_demo", f"{module}/{demo_name}", 0, elapsed_ms)
            return {
                "found": False,
                "message": f"Demo '{demo_name}' not found in module '{target_module}'. Use list_demos() to see available demos."
            }
        
        # Read full content
        demo_path = code_root / demo_info['path']
        full_content = ""
        try:
            full_content = demo_path.read_text(encoding='utf-8', errors='ignore')
        except Exception as e:
            logger.error(f"Failed to read demo file: {e}")
        
        elapsed_ms = (time.time() - t0) * 1000
        stats.record_call("get_demo", f"{module}/{demo_name}", 1, elapsed_ms)
        
        return {
            "found": True,
            "module": target_module,
            "name": demo_info['name'],
            "description": demo_info['description'],
            "file_path": demo_info['path'],
            "url": f"https://gitee.com/openLuat/LuatOS/tree/master/{demo_info['path']}",
            "content": full_content
        }

    @mcp.tool()
    def search_code(
        query: str,
        scope: str = "all",
        top_k: int = 8
    ) -> Dict[str, object]:
        """
        Search across libraries and demos with keywords+vector hybrid.
        
        Args:
            query: Search query text
            scope: "all", "libs", or "demos"
            top_k: Number of results to return (max 20)
        """
        t0 = time.time()
        chunks, lib_infos, demos_by_module = _get_index_and_sync(str(code_root), chroma_index)
        
        q = (query or "").strip().lower()
        tokens = _tokenize(q)
        if not tokens and q:
            tokens = [q]
        
        # Determine search scope
        scope = scope.lower()
        if scope == "libs":
            search_chunks = _chunks_by_type_cache.get("lib", [])
        elif scope == "demos":
            search_chunks = _chunks_by_type_cache.get("demo", [])
        else:
            search_chunks = chunks
        
        # Keyword scoring
        keyword_candidates: List[Tuple[float, CodeChunk]] = []
        for item in search_chunks:
            key = _chunk_key(item)
            score = _score_chunk(
                tokens,
                q,
                item,
                text=_chunk_text_cache.get(key),
                token_set=_chunk_token_cache.get(key),
            )
            if score <= 0:
                continue
            keyword_candidates.append((score, item))
        keyword_candidates.sort(key=lambda pair: pair[0], reverse=True)
        keyword_top = keyword_candidates[:40]
        
        # Vector search (ChromaDB)
        vector_results: List[Tuple[str, float]] = []
        if chroma_index.is_available and q:
            where_filter = None
            if scope == "libs":
                where_filter = {"chunk_type": "lib"}
            elif scope == "demos":
                where_filter = {"chunk_type": "demo"}
            vector_results = chroma_index.query(
                query_text=q,
                n_results=40,
                where_filter=where_filter,
            )
        
        # Fusion
        effective_top_k = max(1, min(int(top_k or 8), 20))
        if vector_results:
            fused = _reciprocal_rank_fusion(keyword_top, vector_results, _chunk_lookup_cache)
            top_items = fused[:effective_top_k]
        else:
            top_items = keyword_top[:effective_top_k]
        
        results = []
        for score, item in top_items:
            results.append({
                "score": round(score, 6),
                "type": item.chunk_type,
                "module": item.module,
                "file_path": item.file_path,
                "title": item.title,
                "chunk_id": item.chunk_id,
                "snippet": item.text[:420],
                "metadata": item.metadata
            })
        
        elapsed_ms = (time.time() - t0) * 1000
        stats.record_call("search_code", query, len(results), elapsed_ms)
        
        return {
            "query": query,
            "scope": scope,
            "result_count": len(results),
            "results": results
        }

    @mcp.tool()
    def resolve_module(query: str = "") -> Dict[str, object]:
        """
        Extract module model from query (air780epm, air8000, etc.).
        Returns the detected module and whether it's a default.
        """
        t0 = time.time()
        _, _, demos_by_module = _get_index_and_sync(str(code_root), chroma_index)
        
        known_modules = list(demos_by_module.keys())
        known_set = set(m.lower() for m in known_modules)
        
        query_lower = query.lower()
        mentions = MODULE_PATTERN.findall(query_lower)
        
        detected_module = None
        source = "default"
        is_default = True
        
        for m in mentions:
            m_lower = m.lower()
            if m_lower in known_set:
                # Find exact case
                for km in known_modules:
                    if km.lower() == m_lower:
                        detected_module = km
                        source = "query_detected"
                        is_default = False
                        break
                break
        
        if detected_module is None:
            # Check for default
            if DEFAULT_MODULE in known_set or DEFAULT_MODULE.upper() in [k.upper() for k in known_modules]:
                detected_module = DEFAULT_MODULE
            elif known_modules:
                detected_module = known_modules[0]
            else:
                detected_module = "unknown"
        
        elapsed_ms = (time.time() - t0) * 1000
        stats.record_call("resolve_module", query, 1, elapsed_ms)
        
        return {
            "module": detected_module,
            "source": source,
            "is_default": is_default,
            "query": query,
            "known_modules": known_modules
        }

    @mcp.tool()
    def server_stats() -> Dict[str, object]:
        """Return server statistics."""
        chunks, lib_infos, demos_by_module = _build_index(str(code_root))
        
        demo_count = sum(len(demos) for demos in demos_by_module.values())
        
        return stats.get_summary(
            chunk_count=len(chunks),
            lib_count=len(lib_infos),
            demo_count=demo_count,
            last_build_time=_last_index_build_time,
            chroma_count=chroma_index.indexed_count,
        )

    return mcp


# ---------------------------------------------------------------------------
# Entry point
# ---------------------------------------------------------------------------

def main() -> None:
    parser = argparse.ArgumentParser(description="LuatOS Code MCP Server (luatos-code)")
    parser.add_argument(
        "--code-root",
        default=os.environ.get("LUATOS_CODE_ROOT", "/opt/sda2/LuatOS"),
        help="LuatOS code root directory (default: /opt/sda2/LuatOS)",
    )
    parser.add_argument(
        "--transport",
        default=os.environ.get("MCP_TRANSPORT", "stdio"),
        choices=["stdio", "sse"],
        help="MCP transport mode (default: stdio)",
    )
    parser.add_argument(
        "--port",
        type=int,
        default=int(os.environ.get("MCP_PORT", "8100")),
        help="Port for SSE transport (default: 8100)",
    )
    args = parser.parse_args()

    code_root = Path(args.code_root).resolve()
    if not code_root.exists():
        raise FileNotFoundError(f"Code root not found: {code_root}")

    logger.info(f"Starting luatos-code MCP server")
    logger.info(f"Code root: {code_root}")
    logger.info(f"Transport: {args.transport}")
    if args.transport == "sse":
        logger.info(f"Port: {args.port}")

    server = _build_server(code_root=code_root, port=args.port)

    if args.transport == "sse":
        allowed_hosts = [
            item.strip()
            for item in os.environ.get("MCP_ALLOWED_HOSTS", "").split(",")
            if item.strip()
        ]
        allowed_origins = [
            item.strip()
            for item in os.environ.get("MCP_ALLOWED_ORIGINS", "").split(",")
            if item.strip()
        ]
        disable_rebinding = os.environ.get("MCP_DISABLE_DNS_REBINDING", "").lower() in ("1", "true", "yes")

        transport_security = None
        if disable_rebinding:
            transport_security = TransportSecuritySettings(enable_dns_rebinding_protection=False)
        elif allowed_hosts or allowed_origins:
            transport_security = TransportSecuritySettings(
                enable_dns_rebinding_protection=True,
                allowed_hosts=allowed_hosts,
                allowed_origins=allowed_origins,
            )

        run_kwargs = {}
        if transport_security is not None:
            supported_params = inspect.signature(server.run).parameters
            if "transport_security" in supported_params:
                run_kwargs["transport_security"] = transport_security
            else:
                print(
                    "Warning: transport_security not supported by installed mcp version; "
                    "run without DNS rebinding settings.",
                    flush=True,
                )

        server.run(transport=args.transport, **run_kwargs)
        return

    server.run(transport=args.transport)


if __name__ == "__main__":
    main()
