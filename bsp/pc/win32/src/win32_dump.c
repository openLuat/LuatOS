#include <windows.h>
#include <dbghelp.h> // 确保链接了 dbghelp.lib
#include <stdio.h>
#include <tchar.h>

// 确保链接DbgHelp库
#pragma comment(lib, "dbghelp.lib")

// 生成迷你转储文件的函数
BOOL GenerateMiniDump(void* pExceptionPointers) {
    TCHAR dumpFileName[MAX_PATH];
    SYSTEMTIME stLocalTime;

    // 获取当前本地时间，用于生成文件名
    GetLocalTime(&stLocalTime);
    _stprintf_s(dumpFileName, MAX_PATH,
        _T("CrashDump_%04d%02d%02d_%02d%02d%02d.dmp"),
        stLocalTime.wYear, stLocalTime.wMonth, stLocalTime.wDay,
        stLocalTime.wHour, stLocalTime.wMinute, stLocalTime.wSecond);

    // 创建转储文件
    HANDLE hDumpFile = CreateFile(dumpFileName, GENERIC_WRITE, 0, NULL, CREATE_ALWAYS, FILE_ATTRIBUTE_NORMAL, NULL);
    if (hDumpFile == INVALID_HANDLE_VALUE) {
        _tprintf(_T("CreateFile failed for dump file. Error: %d\n"), GetLastError());
        return FALSE;
    }

    // 初始化MINIDUMP_EXCEPTION_INFORMATION结构
    MINIDUMP_EXCEPTION_INFORMATION dumpExceptionInfo;
    dumpExceptionInfo.ThreadId = GetCurrentThreadId();
    dumpExceptionInfo.ExceptionPointers = pExceptionPointers;
    dumpExceptionInfo.ClientPointers = FALSE;

    // 写入迷你转储
    BOOL success = MiniDumpWriteDump(GetCurrentProcess(),
        GetCurrentProcessId(),
        hDumpFile,
        MiniDumpNormal, // 你也可以使用 MiniDumpWithFullMemory 获取更完整信息
        (pExceptionPointers != NULL) ? &dumpExceptionInfo : NULL,
        NULL,
        NULL);

    CloseHandle(hDumpFile);

    if (success) {
        _tprintf(_T("崩溃转储文件已生成: %s\n"), dumpFileName);
    } else {
        _tprintf(_T("MiniDumpWriteDump failed. Error: %d\n"), GetLastError());
        // 如果生成失败，尝试删除不完整的dump文件
        DeleteFile(dumpFileName);
    }

    return success;
}

// 顶层的未处理异常过滤器函数
LONG WINAPI TopLevelExceptionFilter(void* pExceptionPointers) {
    _tprintf(_T("程序发生致命异常，正在生成转储文件...\n"));
    GenerateMiniDump(pExceptionPointers);
    _tprintf(_T("程序即将退出。\n"));
    // 返回 EXCEPTION_EXECUTE_HANDLER 会让系统终止程序
    return EXCEPTION_EXECUTE_HANDLER;
}

// 初始化崩溃转储功能
void InitCrashDump() {
    SetUnhandledExceptionFilter(TopLevelExceptionFilter);
}
