# pgfs Design Spec (NAND Log-Structured Filesystem)

Date: 2026-05-28  
Status: Approved for planning  
Scope: LuatOS component `components/pgfs/`

## 1. Goals

Design and implement `pgfs` as a NAND-optimized log-structured filesystem for LuatOS with these hard requirements:

1. Optimize for NAND constraints (append-friendly, erase-block aware, bad-block aware).
2. Power-loss semantics: data before `fclose` may be lost; if `fclose` returns success, durability is guaranteed.
3. Balanced read/write performance; filesystem status query (`info`) must be fast.
4. Support superblock-based generation management.
5. RAM scales with FS size; prioritize correctness/perf balance over extreme minimization; target typical total RAM <= 512 KiB.
6. PC simulator must be first bring-up target, with stress tests.
7. Flash backend API is exactly four ops: `read`, `write`, `erase`, `control`.
8. Optional locking to protect caches/metadata from concurrent access corruption.
9. Must mount through LuatOS VFS.

## 2. Architecture and Boundaries

`pgfs` is a new component, not a rename of existing NAND components.

Planned internal modules:

- `pgfs_core`: object model, record encode/decode, replay coordinator.
- `pgfs_checkpoint`: dual-superblock / dual-checkpoint generation protocol.
- `pgfs_alloc_gc`: segment allocator, reclaim policy, bad-block retirement hooks.
- `pgfs_cache_lock`: write cache and optional lock wrappers.
- `pgfs_vfs_adapter`: LuatOS VFS operation mapping.
- `pgfs_flash_opts`: 4-op flash abstraction.
- `pgfs_pc_backend`: simulator NAND backend and fault injection.

Boundary rules:

- Persistent media access occurs only through `pgfs_flash_opts`.
- `fclose` is the sole durability boundary for normal file writes.
- `info()` uses fast metadata path (memory/checkpoint), not steady-state full scan.

## 3. YAFFS2 Lessons (Modernized and Adopted)

This spec adopts high-value YAFFS2 principles, updated for in-band metadata only (no OOB tags):

1. **Copy-on-write only (MUST)**: no in-place overwrite for mutable metadata/data.
2. **Atomic commit boundary (MUST)**: `fclose` success implies durable committed generation.
3. **Dual generations (MUST)**: keep at least two superblock/checkpoint generations with monotonic sequence and CRC.
4. **Fast-mount first (MUST)**: mount reads superblock + checkpoint + summaries first; replay/scan is fallback only.
5. **In-band tag semantics (MUST)**: each record carries object/chunk/sequence/type/checksum fields in-band.
6. **Segment summaries (SHOULD)**: maintain compact live/dead summary for GC candidate selection.
7. **Incremental GC (SHOULD)**: budgeted, preemptible reclaim to avoid long foreground stalls.
8. **Bad-block aware allocation (MUST)**: allocator skips known bad blocks and supports runtime retirement.
9. **Deterministic recovery (MUST)**: replay and winner selection are sequence-driven and deterministic.
10. **Integrity layering (SHOULD)**: per-record CRC mandatory; stronger policy configurable via `control`.
11. **Bounded RAM indexing (MUST)**: index/cache growth is policy-bounded.
12. **Observability (SHOULD)**: expose replay/GC/checkpoint counters and timing metrics.

## 4. On-Disk Model

Logical regions:

- `SB_A` / `SB_B`: dual superblocks with generation pointer and integrity fields.
- `CP_A` / `CP_B`: dual checkpoints with index/counter snapshots.
- `SEGMENTS`: append-only log segments for file and metadata records.

Record header (in-band, minimum):

- `magic`
- `version`
- `rec_type`
- `object_id`
- `chunk_id`
- `seq`
- `payload_len`
- `crc32`

Minimum record types:

- `DATA`
- `INODE`
- `DENTRY`
- `DELETE`
- `CP_DELTA`

## 5. Commit and Recovery Protocol

### 5.1 Commit protocol (`fclose`)

On close of a modified file:

1. Flush pending write cache into append log records.
2. Append checkpoint-delta record(s).
3. Build and write next checkpoint generation (`CP_A/B` alternating), verify integrity.
4. Atomically switch superblock pointer (`SB_A/B` alternating) to new generation.
5. Return success only if the new generation is durable and readable.

Any failure in steps above returns error; no false durability claim is allowed.

### 5.2 Mount/recovery protocol

1. Read both superblocks, select latest valid generation by sequence + CRC.
2. Load pointed checkpoint generation.
3. If selected generation is invalid, roll back to previous valid generation.
4. If no valid checkpoint is available, replay log deterministically and materialize a fresh checkpoint generation.
5. Enter steady state with fast metadata path enabled.

## 6. Performance, Memory, and GC

### 6.1 Fast status path

- Keep runtime counters in RAM.
- Persist counters in checkpoint.
- `info()` reads RAM/checkpoint state directly.
- If metadata invalidation is detected, do one rebuild path, then restore fast path.

### 6.2 GC model

- Segment summary tracks `live_bytes`, `dead_bytes`, age/hotness metadata.
- Foreground I/O does budgeted GC only.
- Background/idle path performs deeper reclaim.
- Watermark triggers protect free-space floor.

### 6.3 Memory model

- Capacity-tiered policy for cache/index windows.
- Bounded growth for in-memory structures.
- Typical target budget <= 512 KiB without sacrificing correctness.

## 7. Concurrency and Locking

- Locking is optional and configurable.
- Lock scope includes:
  - write cache mutation
  - generation switch path
  - GC metadata queues
- Lock disabled mode is supported for deterministic single-thread access patterns.

## 8. Flash Backend Interface (`pgfs_flash_opts`)

Exactly four operations:

- `read(ctx, addr, buf, len)`
- `write(ctx, addr, buf, len)`
- `erase(ctx, block_addr, block_count)`
- `control(ctx, cmd, arg)`

`control` minimum expected capabilities:

- geometry query
- bad-block query/mark-retired
- flush/barrier semantics
- optional test fault injection and stats.

## 9. LuatOS VFS Integration

`pgfs_vfs_adapter` will provide LuatOS VFS hooks for:

- `mkfs`, `mount`, `umount`, `info`
- `fopen`, `fread`, `fwrite`, `fflush`, `fclose`, `fseek`, `ftell`
- `remove`, `rename`, `truncate`
- directory operations (`mkdir`, `rmdir`, `lsdir`, `opendir`, `closedir`)

Behavioral contract:

- all write-path durability claims are aligned with section 5.
- mount and info avoid full scan in steady state.

## 10. PC-First Validation and Stress Matrix

Mandatory test classes:

1. Power-loss injection at each close-commit stage.
2. Generation selection correctness when latest generation is corrupted.
3. GC pressure with mixed small append + create/delete/rename churn.
4. Bad-block retirement simulation and survivability checks.
5. `info()` latency stability under long-run workloads.
6. Lock-on vs lock-off consistency behavior tests.

Validation order:

1. minimal mount/read/write loop on PC backend
2. close durability tests
3. recovery matrix
4. stress/fragmentation/reclaim tests
5. VFS integration regression

## 11. Non-Goals

- No OOB tag dependency.
- No attempt to maximize compression ratio.
- No requirement for extreme minimum RAM at the expense of correctness/latency stability.

## 12. Acceptance Criteria

Design is accepted when implementation can prove:

1. `fclose` durability boundary is true under fault injection.
2. mount recovers deterministically across interrupted commits.
3. fast `info()` path remains available in steady state.
4. NAND bad-block handling does not violate data consistency guarantees.
5. tests pass on PC simulator as first-class gate.
