#include "luat_base.h"

#ifdef LUAT_USE_WINDOWS
#include <windows.h>
#include <stdio.h>
#include <string.h>
#include <TlHelp32.h>
#include <Psapi.h>

// Windows控制台编码自动设置
void luat_console_auto_encoding(void) {
    // 检测是否在Windows控制台环境中
    HANDLE hStdout = GetStdHandle(STD_OUTPUT_HANDLE);
    if (hStdout == INVALID_HANDLE_VALUE) {
        return; // 不在控制台中运行（可能是重定向或其他）
    }
    
    // 检测控制台模式
    DWORD mode = 0;
    if (!GetConsoleMode(hStdout, &mode)) {
        return; // 不是真正的控制台
    }
    
    // 获取当前控制台代码页
    UINT currentCP = GetConsoleOutputCP();
    
    // 如果已经是UTF-8，无需设置
    if (currentCP == 65001) {
        // 启用虚拟终端序列支持
        mode |= ENABLE_VIRTUAL_TERMINAL_PROCESSING;
        SetConsoleMode(hStdout, mode);
        return;
    }
    
    // 尝试检测父进程类型并相应设置编码
    DWORD parentPid = 0;
    HANDLE hSnapshot = CreateToolhelp32Snapshot(TH32CS_SNAPPROCESS, 0);
    if (hSnapshot != INVALID_HANDLE_VALUE) {
        PROCESSENTRY32 pe32;
        pe32.dwSize = sizeof(PROCESSENTRY32);
        DWORD currentPid = GetCurrentProcessId();
        
        if (Process32First(hSnapshot, &pe32)) {
            do {
                if (pe32.th32ProcessID == currentPid) {
                    parentPid = pe32.th32ParentProcessID;
                    break;
                }
            } while (Process32Next(hSnapshot, &pe32));
        }
        
        // 查找父进程名称
        if (parentPid != 0) {
            HANDLE hParent = OpenProcess(PROCESS_QUERY_INFORMATION | PROCESS_VM_READ, FALSE, parentPid);
            if (hParent) {
                char szProcessName[MAX_PATH];
                if (GetModuleFileNameExA(hParent, NULL, szProcessName, MAX_PATH)) {
                    char* pszFileName = strrchr(szProcessName, '\\');
                    if (pszFileName) {
                        pszFileName++;
                        
                        // 转换为小写进行比较
                        for (char* p = pszFileName; *p; p++) {
                            if (*p >= 'A' && *p <= 'Z') *p = *p + 32;
                        }
                        
                        // 检测命令行类型并设置编码
                        if (strstr(pszFileName, "cmd.exe")) {
                            // CMD: 使用system调用chcp命令
                            system("chcp 65001 >nul 2>&1");
                        }
                        else if (strstr(pszFileName, "powershell.exe") || 
                                strstr(pszFileName, "pwsh.exe")) {
                            // PowerShell: 直接设置控制台代码页
                            SetConsoleOutputCP(65001);
                            SetConsoleCP(65001);
                            // 设置环境变量影响PowerShell行为
                            SetEnvironmentVariableA("PYTHONIOENCODING", "utf-8");
                        }
                        else {
                            // 其他情况，直接设置为UTF-8
                            SetConsoleOutputCP(65001);
                            SetConsoleCP(65001);
                        }
                    }
                }
                CloseHandle(hParent);
            }
        }
        CloseHandle(hSnapshot);
    }
    else {
        // 如果无法检测父进程，直接设置UTF-8
        SetConsoleOutputCP(65001);
        SetConsoleCP(65001);
    }
    
    // 启用虚拟终端序列支持
    mode |= ENABLE_VIRTUAL_TERMINAL_PROCESSING;
    SetConsoleMode(hStdout, mode);
}
#endif
