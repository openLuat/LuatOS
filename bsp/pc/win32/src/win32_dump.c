#include <windows.h>
#include <dbghelp.h>
#include <stdio.h>
#include <tchar.h>

/* Lua public API — needed for PrintLuaStack (lua_getstack / lua_getinfo) */
#include "lua.h"

/* Ensure DbgHelp is linked */
#pragma comment(lib, "dbghelp.lib")

/* ================================================================
   Task Registry
   win32_task_register() is called from each new pthread at startup
   (luat_rtos_task_pc.c: rtos_task, main_mini.c: uv_luat_main).
   Using a static fixed-size array avoids heap dependency in crash path.
   ================================================================ */

#define MAX_TASK_ENTRIES 32

typedef struct {
    HANDLE handle;   /* Win32 handle: THREAD_SUSPEND_RESUME | THREAD_GET_CONTEXT */
    char   name[64];
    int    active;
} TaskEntry;

static TaskEntry      s_tasks[MAX_TASK_ENTRIES];
static CRITICAL_SECTION s_cs;
static volatile int   s_cs_ready = 0;

static void ensure_cs(void) {
    if (!s_cs_ready) {
        InitializeCriticalSection(&s_cs);
        s_cs_ready = 1;
    }
}

/* Called at task thread startup to add this thread to the registry */
void win32_task_register(const char* name) {
    if (!s_cs_ready) return;
    HANDLE h = OpenThread(
        THREAD_SUSPEND_RESUME | THREAD_GET_CONTEXT | THREAD_QUERY_INFORMATION,
        FALSE, GetCurrentThreadId());
    if (h == NULL) return;
    EnterCriticalSection(&s_cs);
    for (int i = 0; i < MAX_TASK_ENTRIES; i++) {
        if (!s_tasks[i].active) {
            s_tasks[i].handle = h;
            strncpy_s(s_tasks[i].name, sizeof(s_tasks[i].name),
                      name ? name : "unnamed", _TRUNCATE);
            s_tasks[i].active = 1;
            break;
        }
    }
    LeaveCriticalSection(&s_cs);
}

/* Called at task thread exit */
void win32_task_unregister(void) {
    if (!s_cs_ready) return;
    DWORD tid = GetCurrentThreadId();
    EnterCriticalSection(&s_cs);
    for (int i = 0; i < MAX_TASK_ENTRIES; i++) {
        if (s_tasks[i].active && GetThreadId(s_tasks[i].handle) == tid) {
            CloseHandle(s_tasks[i].handle);
            s_tasks[i].handle = NULL;
            s_tasks[i].active = 0;
            break;
        }
    }
    LeaveCriticalSection(&s_cs);
}

/* ================================================================
   Helper: exception code → readable string
   ================================================================ */
static const char* exception_code_str(DWORD code) {
    switch (code) {
        case EXCEPTION_ACCESS_VIOLATION:         return "ACCESS_VIOLATION";
        case EXCEPTION_ARRAY_BOUNDS_EXCEEDED:    return "ARRAY_BOUNDS_EXCEEDED";
        case EXCEPTION_BREAKPOINT:               return "BREAKPOINT";
        case EXCEPTION_DATATYPE_MISALIGNMENT:    return "DATATYPE_MISALIGNMENT";
        case EXCEPTION_FLT_DIVIDE_BY_ZERO:       return "FLT_DIVIDE_BY_ZERO";
        case EXCEPTION_FLT_OVERFLOW:             return "FLT_OVERFLOW";
        case EXCEPTION_FLT_STACK_CHECK:          return "FLT_STACK_CHECK";
        case EXCEPTION_FLT_UNDERFLOW:            return "FLT_UNDERFLOW";
        case EXCEPTION_ILLEGAL_INSTRUCTION:      return "ILLEGAL_INSTRUCTION";
        case EXCEPTION_IN_PAGE_ERROR:            return "IN_PAGE_ERROR";
        case EXCEPTION_INT_DIVIDE_BY_ZERO:       return "INT_DIVIDE_BY_ZERO";
        case EXCEPTION_INT_OVERFLOW:             return "INT_OVERFLOW";
        case EXCEPTION_PRIV_INSTRUCTION:         return "PRIV_INSTRUCTION";
        case EXCEPTION_STACK_OVERFLOW:           return "STACK_OVERFLOW";
        default:                                 return "UNKNOWN";
    }
}

/* ================================================================
   Inner StackWalk64 loop.
   Assumes SymInitialize() has already been called (done in InitCrashDump).
   hThread must be a real Win32 handle (not the pseudo-handle) with
   THREAD_SUSPEND_RESUME | THREAD_GET_CONTEXT, and must be SUSPENDED
   before calling this function (except for the crashing thread itself).
   ================================================================ */
static void WalkThreadStack(HANDLE hProcess, HANDLE hThread, CONTEXT* ctx) {
    CONTEXT ctxCopy = *ctx;
    STACKFRAME64 sf;
    memset(&sf, 0, sizeof(sf));

    DWORD machineType;
#ifdef _M_IX86
    machineType             = IMAGE_FILE_MACHINE_I386;
    sf.AddrPC.Offset        = ctxCopy.Eip;
    sf.AddrPC.Mode          = AddrModeFlat;
    sf.AddrStack.Offset     = ctxCopy.Esp;
    sf.AddrStack.Mode       = AddrModeFlat;
    sf.AddrFrame.Offset     = ctxCopy.Ebp;
    sf.AddrFrame.Mode       = AddrModeFlat;
#elif defined(_M_X64)
    machineType             = IMAGE_FILE_MACHINE_AMD64;
    sf.AddrPC.Offset        = ctxCopy.Rip;
    sf.AddrPC.Mode          = AddrModeFlat;
    sf.AddrStack.Offset     = ctxCopy.Rsp;
    sf.AddrStack.Mode       = AddrModeFlat;
    sf.AddrFrame.Offset     = ctxCopy.Rbp;
    sf.AddrFrame.Mode       = AddrModeFlat;
#else
    #error "Unsupported architecture for stack walk"
#endif

    char symBuf[sizeof(SYMBOL_INFO) + MAX_SYM_NAME];
    SYMBOL_INFO*    symInfo = (SYMBOL_INFO*)symBuf;
    IMAGEHLP_LINE64 line;

    for (int frame = 0; frame < 64; frame++) {
        if (!StackWalk64(machineType, hProcess, hThread, &sf, &ctxCopy,
                         NULL, SymFunctionTableAccess64, SymGetModuleBase64, NULL)) {
            break;
        }
        if (sf.AddrPC.Offset == 0) break;

        memset(symBuf, 0, sizeof(symBuf));
        symInfo->SizeOfStruct = sizeof(SYMBOL_INFO);
        symInfo->MaxNameLen   = MAX_SYM_NAME;

        memset(&line, 0, sizeof(line));
        line.SizeOfStruct = sizeof(IMAGEHLP_LINE64);

        DWORD64 symDisp  = 0;
        DWORD   lineDisp = 0;

        if (SymFromAddr(hProcess, sf.AddrPC.Offset, &symDisp, symInfo)) {
            if (SymGetLineFromAddr64(hProcess, sf.AddrPC.Offset, &lineDisp, &line)) {
                printf("  #%-2d %p  %s+0x%llx  [%s:%lu]\n",
                       frame,
                       (void*)(uintptr_t)sf.AddrPC.Offset,
                       symInfo->Name,
                       (unsigned long long)symDisp,
                       line.FileName,
                       line.LineNumber);
            } else {
                printf("  #%-2d %p  %s+0x%llx\n",
                       frame,
                       (void*)(uintptr_t)sf.AddrPC.Offset,
                       symInfo->Name,
                       (unsigned long long)symDisp);
            }
        } else {
            printf("  #%-2d %p  (no symbol)\n",
                   frame,
                   (void*)(uintptr_t)sf.AddrPC.Offset);
        }
    }
}

/* ================================================================
   Print Lua-level call stack.
   The Lua thread should be suspended before calling this (or the
   caller must be on the Lua thread itself).
   ================================================================ */
static void PrintLuaStack(lua_State* L) {
    if (L == NULL) return;
    printf("\n--- Lua stack ---\n");
    lua_Debug ar;
    int level = 0;
    while (lua_getstack(L, level, &ar)) {
        lua_getinfo(L, "nSl", &ar);
        const char* kind = "";
        if      (ar.what[0] == 'C') kind = " [C]";
        else if (ar.what[0] == 'm') kind = " [main chunk]";
        printf("  #%-2d  %s:%d  in %s%s\n",
               level,
               ar.short_src,
               ar.currentline,
               ar.name ? ar.name : "?",
               kind);
        if (++level > 50) { printf("  ... (truncated)\n"); break; }
    }
    if (level == 0) printf("  (empty or not in Lua)\n");
}

/* ================================================================
   Print crash basic info
   ================================================================ */
static void PrintCrashInfo(EXCEPTION_POINTERS* ep) {
    EXCEPTION_RECORD* er = ep->ExceptionRecord;
    printf("\n====== FATAL CRASH ======\n");
    printf("Exception : 0x%08lX (%s)\n", er->ExceptionCode, exception_code_str(er->ExceptionCode));
    printf("Address   : %p\n", er->ExceptionAddress);
    if (er->ExceptionCode == EXCEPTION_ACCESS_VIOLATION && er->NumberParameters >= 2) {
        const char* op = er->ExceptionInformation[0] == 0 ? "READ"
                       : er->ExceptionInformation[0] == 1 ? "WRITE" : "DEP";
        printf("Access    : %s at %p\n", op, (void*)er->ExceptionInformation[1]);
    }
}

/* ================================================================
   Dump all registered task stacks + Lua stack.

   currentCtx: CONTEXT of the already-captured/crashing thread (NULL for Ctrl+C path).
   currentTid: thread ID already handled (skip double-dump on crash path).
   L:          global lua_State* from luat_main.c (may be NULL early in boot).
   ================================================================ */
static void DumpAllTasks(CONTEXT* currentCtx, DWORD currentTid, lua_State* L) {
    HANDLE hProcess = GetCurrentProcess();

    printf("\n====== THREAD STACKS ======\n");

    /* Note: we skip the CS lock intentionally in crash context.
       If the crash happened while holding s_cs, a lock would deadlock.
       Reading stale/partial data is acceptable during a fatal dump. */
    int found = 0;
    HANDLE luaThreadHandle = NULL; /* track the lua-main handle for Lua stack */

    for (int i = 0; i < MAX_TASK_ENTRIES; i++) {
        if (!s_tasks[i].active) continue;
        HANDLE h = s_tasks[i].handle;
        if (h == NULL || h == INVALID_HANDLE_VALUE) continue;

        DWORD tid = GetThreadId(h);
        printf("\n--- [%s] (tid=%lu) ---\n", s_tasks[i].name, (unsigned long)tid);

        if (tid == currentTid && currentCtx != NULL) {
            /* Crashing thread — CONTEXT already provided, thread is running the handler */
            WalkThreadStack(hProcess, GetCurrentThread(), currentCtx);
        } else {
            DWORD sus = SuspendThread(h);
            if (sus == (DWORD)-1) {
                printf("  [Failed to suspend: %lu]\n", GetLastError());
                continue;
            }
            CONTEXT ctx;
            memset(&ctx, 0, sizeof(ctx));
            ctx.ContextFlags = CONTEXT_FULL;
            if (GetThreadContext(h, &ctx)) {
                WalkThreadStack(hProcess, h, &ctx);
            } else {
                printf("  [GetThreadContext failed: %lu]\n", GetLastError());
            }
            /* Keep the lua-main thread suspended while we read its Lua stack */
            if (strncmp(s_tasks[i].name, "lua-main", 8) == 0) {
                luaThreadHandle = h; /* will resume after Lua stack dump */
            } else {
                ResumeThread(h);
            }
        }
        found++;
    }

    if (found == 0) {
        printf("  (no registered tasks — call InitCrashDump() before creating tasks)\n");
    }

    /* Lua stack — read while lua-main is still suspended for consistency */
    PrintLuaStack(L);

    /* Resume lua-main if we kept it suspended */
    if (luaThreadHandle != NULL) {
        ResumeThread(luaThreadHandle);
    }

    printf("\n===========================\n\n");
}

/* ================================================================
   Generate minidump file (for offline analysis with WinDbg)
   ================================================================ */
static BOOL GenerateMiniDump(void* pExceptionPointers) {
    TCHAR dumpFileName[MAX_PATH];
    SYSTEMTIME stLocalTime;

    GetLocalTime(&stLocalTime);
    _stprintf_s(dumpFileName, MAX_PATH,
        _T("CrashDump_%04d%02d%02d_%02d%02d%02d.dmp"),
        stLocalTime.wYear, stLocalTime.wMonth, stLocalTime.wDay,
        stLocalTime.wHour, stLocalTime.wMinute, stLocalTime.wSecond);

    HANDLE hDumpFile = CreateFile(dumpFileName, GENERIC_WRITE, 0, NULL,
                                  CREATE_ALWAYS, FILE_ATTRIBUTE_NORMAL, NULL);
    if (hDumpFile == INVALID_HANDLE_VALUE) {
        _tprintf(_T("[CreateFile failed for dump. Error: %lu]\n"), GetLastError());
        return FALSE;
    }

    MINIDUMP_EXCEPTION_INFORMATION dumpExceptionInfo;
    dumpExceptionInfo.ThreadId          = GetCurrentThreadId();
    dumpExceptionInfo.ExceptionPointers = pExceptionPointers;
    dumpExceptionInfo.ClientPointers    = FALSE;

    BOOL success = MiniDumpWriteDump(GetCurrentProcess(), GetCurrentProcessId(),
                                     hDumpFile, MiniDumpNormal,
                                     (pExceptionPointers != NULL) ? &dumpExceptionInfo : NULL,
                                     NULL, NULL);
    CloseHandle(hDumpFile);

    if (success) {
        _tprintf(_T("Minidump : %s\n"), dumpFileName);
    } else {
        _tprintf(_T("[MiniDumpWriteDump failed. Error: %lu]\n"), GetLastError());
        DeleteFile(dumpFileName);
    }
    return success;
}

/* ================================================================
   Global lua_State* (defined in luat/modules/luat_main.c)
   ================================================================ */
extern lua_State* L;

/* ================================================================
   Top-level unhandled exception filter (hard crash handler)
   ================================================================ */
LONG WINAPI TopLevelExceptionFilter(void* pExceptionPointers) {
    EXCEPTION_POINTERS* ep = (EXCEPTION_POINTERS*)pExceptionPointers;
    PrintCrashInfo(ep);
    DumpAllTasks(ep->ContextRecord, GetCurrentThreadId(), L);
    GenerateMiniDump(pExceptionPointers);
    printf("程序即将退出。\n");
    fflush(stdout);
    return EXCEPTION_EXECUTE_HANDLER;
}

/* ================================================================
   Ctrl+C / Ctrl+Break handler — dump all threads on freeze
   ================================================================ */
static BOOL WINAPI CtrlHandler(DWORD type) {
    if (type == CTRL_C_EVENT || type == CTRL_BREAK_EVENT) {
        printf("\n====== CTRL+C: Thread Stack Dump ======\n");
        fflush(stdout);
        DumpAllTasks(NULL, GetCurrentThreadId(), L);
        fflush(stdout);
        /* Return FALSE so the default handler runs and exits the process.
           This is intentional: Ctrl+C on a frozen simulator should terminate. */
        return FALSE;
    }
    return FALSE;
}

/* ================================================================
   Initialize crash dump — call once at program startup (before creating threads)
   ================================================================ */
void InitCrashDump(void) {
    /* Initialize task registry lock */
    ensure_cs();

    /* Load debug symbols early (once) so StackWalk64 resolves names.
       SymInitialize must NOT be called again later. */
    SymSetOptions(SYMOPT_LOAD_LINES | SYMOPT_UNDNAME | SYMOPT_DEFERRED_LOADS);
    SymInitialize(GetCurrentProcess(), NULL, TRUE);

    SetUnhandledExceptionFilter(TopLevelExceptionFilter);
    SetConsoleCtrlHandler(CtrlHandler, TRUE);
}

