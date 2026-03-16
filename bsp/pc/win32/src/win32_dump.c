#include <windows.h>
#include <dbghelp.h>
#include <stdio.h>
#include <tchar.h>

// 确保链接DbgHelp库
#pragma comment(lib, "dbghelp.lib")

// 将异常代码转换为可读字符串
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

// 打印异常基本信息
static void PrintCrashInfo(EXCEPTION_POINTERS* ep) {
    EXCEPTION_RECORD* er = ep->ExceptionRecord;
    printf("\n====== FATAL CRASH ======\n");
    printf("Exception : 0x%08lX (%s)\n", er->ExceptionCode, exception_code_str(er->ExceptionCode));
    printf("Address   : %p\n", er->ExceptionAddress);
    // ACCESS_VIOLATION 额外打印读/写方向和目标地址
    if (er->ExceptionCode == EXCEPTION_ACCESS_VIOLATION && er->NumberParameters >= 2) {
        const char* op = er->ExceptionInformation[0] == 0 ? "READ"
                       : er->ExceptionInformation[0] == 1 ? "WRITE" : "DEP";
        printf("Access    : %s at %p\n", op, (void*)er->ExceptionInformation[1]);
    }
}

// 使用 StackWalk64 打印调用栈（需要构建时生成 PDB）
static void PrintStackTrace(CONTEXT* ctx) {
    HANDLE hProcess = GetCurrentProcess();
    HANDLE hThread  = GetCurrentThread();

    SymSetOptions(SYMOPT_LOAD_LINES | SYMOPT_UNDNAME | SYMOPT_DEFERRED_LOADS);
    if (!SymInitialize(hProcess, NULL, TRUE)) {
        printf("[SymInitialize failed: %lu]\n", GetLastError());
        return;
    }

    // 必须对 CONTEXT 做拷贝，StackWalk64 会修改它
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

    printf("\nStack trace:\n");

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
    printf("=========================\n\n");

    SymCleanup(hProcess);
}

// 生成迷你转储文件（作为备份，供离线分析）
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

// 顶层未处理异常过滤器
LONG WINAPI TopLevelExceptionFilter(void* pExceptionPointers) {
    EXCEPTION_POINTERS* ep = (EXCEPTION_POINTERS*)pExceptionPointers;
    PrintCrashInfo(ep);
    PrintStackTrace(ep->ContextRecord);
    GenerateMiniDump(pExceptionPointers);
    printf("程序即将退出。\n");
    return EXCEPTION_EXECUTE_HANDLER;
}

// 初始化崩溃转储功能
void InitCrashDump() {
    SetUnhandledExceptionFilter(TopLevelExceptionFilter);
}
