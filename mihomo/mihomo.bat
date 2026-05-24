@echo off
chcp 65001 >nul
rem 切换目录
cd /d "%~dp0"
title Mihomo Core 启停开关

rem ==========================
rem 1. 自动请求管理员权限 (TUN模式强依赖)
rem ==========================
net session >nul 2>&1
if %errorLevel% neq 0 (
    powershell -NoProfile -Command "Start-Process '%~dpnx0' -Verb RunAs"
    exit
)

rem ==========================
rem 初始化 ANSI 颜色引擎
rem ==========================
reg add HKCU\Console /v VirtualTerminalLevel /t REG_DWORD /d 1 /f >nul 2>&1
for /F "delims=#" %%E in ('"prompt #$E# & for %%a in (1) do rem"') do set "ESC=%%E"
set "C_RESET=%ESC%[0m"
set "C_GREEN=%ESC%[92m"
set "C_RED=%ESC%[91m"
rem ==========================

set "MIHOMO_EXE=mihomo-windows-amd64.exe"
set "CONFIG_FILE=config.yaml"
set "PROXY_SERVER=127.0.0.1:7890"
set "PROXY_BYPASS=localhost;127.*;10.*;172.16.*;192.168.*;<local>"

rem 精准进程检测 (防止误判同名文件夹)
tasklist /FI "IMAGENAME eq %MIHOMO_EXE%" 2>nul | find /I "%MIHOMO_EXE%" >nul
if not errorlevel 1 goto IsRunning
goto StartMenu


:IsRunning
rem 检测当前是 TUN 模式还是系统代理模式
reg query "HKCU\Software\Microsoft\Windows\CurrentVersion\Internet Settings" /v ProxyEnable 2>nul | find /i "0x1" >nul
if not errorlevel 1 goto RunningProxyMenu


:RunningTun
echo.
echo  %C_GREEN%发现 Mihomo 正在运行 [当前状态: TUN 模式]%C_RESET%
echo.
echo  %C_GREEN%--------------------------------------------------%C_RESET%
echo  %C_GREEN% 请选择操作:%C_RESET%
echo  %C_GREEN%  1. 切换代理    （仅接管系统代理，适合日常网页）%C_RESET%
echo  %C_GREEN%  2. 彻底退出    （关闭核心，系统恢复直连）%C_RESET%
echo  %C_GREEN%--------------------------------------------------%C_RESET%
echo.
powershell -NoProfile -Command "[Console]::TreatControlCAsInput=$true; $k=[Console]::ReadKey($true).KeyChar; if($k -eq '1'){exit 1}elseif($k -eq '2'){exit 2}else{exit 3}"

if errorlevel 3 exit
if errorlevel 2 goto StopProcess
if errorlevel 1 goto SwitchToProxy
exit


:RunningProxyMenu
echo.
echo  %C_GREEN%发现 Mihomo 正在运行 [当前状态: 系统代理模式]%C_RESET%
echo.
echo  %C_GREEN%--------------------------------------------------%C_RESET%
echo  %C_GREEN% 请选择操作:%C_RESET%
echo  %C_GREEN%  1. 切换TUN     （全局接管，适合开始打游戏）%C_RESET%
echo  %C_GREEN%  2. 彻底退出    （关闭核心，系统恢复直连）%C_RESET%
echo  %C_GREEN%--------------------------------------------------%C_RESET%
echo.
powershell -NoProfile -Command "[Console]::TreatControlCAsInput=$true; $k=[Console]::ReadKey($true).KeyChar; if($k -eq '1'){exit 1}elseif($k -eq '2'){exit 2}else{exit 3}"

if errorlevel 3 exit
if errorlevel 2 goto StopProcess
if errorlevel 1 goto SwitchToTun
exit


:SwitchToProxy
echo.
echo  %C_GREEN%正在关闭当前进程，准备切换至 系统代理 模式...%C_RESET%
taskkill /F /IM "%MIHOMO_EXE%" >nul 2>&1
goto ModeProxy


:SwitchToTun
echo.
echo  %C_GREEN%正在关闭当前代理进程，准备切换至 TUN 模式...%C_RESET%
taskkill /F /IM "%MIHOMO_EXE%" >nul 2>&1
goto ModeTun


:StopProcess
echo.
echo  %C_GREEN%正在关闭 Mihomo 核心...%C_RESET%
taskkill /F /IM "%MIHOMO_EXE%" >nul 2>&1
echo  %C_GREEN%正在关闭系统代理...%C_RESET%
call :DisableSystemProxy
echo.
echo  %C_GREEN%清理完成：Mihomo 已退出，网络已恢复直连！%C_RESET%
timeout /t 2 >nul
exit


:StartMenu
echo.
echo  %C_GREEN%Mihomo 当前未运行%C_RESET%
echo.
echo  %C_GREEN%--------------------------------------------------%C_RESET%
echo  %C_GREEN% 请选择本次启动的模式:%C_RESET%
echo  %C_GREEN%  1. TUN 模式    （全局网卡接管，适合游戏）%C_RESET%
echo  %C_GREEN%  2. 代理模式    （仅接管系统代理，适合日常网页）%C_RESET%
echo  %C_GREEN%--------------------------------------------------%C_RESET%
echo.
powershell -NoProfile -Command "[Console]::TreatControlCAsInput=$true; $k=[Console]::ReadKey($true).KeyChar; if($k -eq '1'){exit 1}elseif($k -eq '2'){exit 2}else{exit 3}"

if errorlevel 3 exit
if errorlevel 2 goto ModeProxy
if errorlevel 1 goto ModeTun
exit


:ModeProxy
echo.
echo  %C_GREEN%正在修改配置 , 关闭 TUN 模式...%C_RESET%
set "TUN_STATE=false"
call :ModifyTun
echo  %C_GREEN%正在开启 Windows 系统代理 %PROXY_SERVER% ...%C_RESET%
call :EnableSystemProxy
goto RunMihomo


:ModeTun
echo.
echo  %C_GREEN%正在修改配置 , 启用 TUN 模式...%C_RESET%
set "TUN_STATE=true"
call :ModifyTun
echo  %C_GREEN%正在确保系统代理已关闭...%C_RESET%
call :DisableSystemProxy
goto RunMihomo


:RunMihomo
echo.
echo  %C_GREEN%正在执行配置预检...%C_RESET%

rem 清理旧的报错日志
if exist "core_error.log" del /f /q "core_error.log"
if exist "core_output.log" del /f /q "core_output.log"

rem 终极优化1: 调用 Mihomo 的 "-t" 测试命令进行硬核语法预检。这能将 99% 的缩进、错别字错误拦截在启动前！
"%MIHOMO_EXE%" -d . -t > "core_error.log" 2>&1
if errorlevel 1 (
    echo.
    echo  %C_RED%[致命错误] config.yaml 语法或节点配置有误，已中止启动！%C_RESET%
    goto Rollback
)

echo  %C_GREEN%配置预检通过，正在后台启动核心...%C_RESET%

rem 终极优化2: 彻底分离标准输出(-RedirectStandardOutput)和错误输出(-RedirectStandardError)，捕获运行时异常(如端口被占用)
powershell -NoProfile -Command "Start-Process -WindowStyle Hidden -FilePath '.\%MIHOMO_EXE%' -ArgumentList '-d .' -RedirectStandardOutput '.\core_output.log' -RedirectStandardError '.\core_error.log'"

rem 给核心 2 秒钟的时间绑定端口
ping 127.0.0.1 -n 3 >nul

rem 二次健康检查（捕获启动后发现 7890 端口被占用的闪退情况）
tasklist /FI "IMAGENAME eq %MIHOMO_EXE%" 2>nul | find /I "%MIHOMO_EXE%" >nul
if errorlevel 1 (
    echo.
    echo  %C_RED%[致命错误] Mihomo 启动后闪退！可能是 7890 等端口被其他软件占用。%C_RESET%
    goto Rollback
)

echo  %C_GREEN%Mihomo 环境已成功启动，接管完成！%C_RESET%
timeout /t 2 >nul
exit


:Rollback
echo  %C_RED%请打开脚本目录下的 core_error.log 或 core_output.log 查看具体报错内容。%C_RESET%
echo.
echo  %C_GREEN%[自动防御] 正在回滚配置，防止系统断网...%C_RESET%
call :DisableSystemProxy
echo  %C_GREEN%清理完成，网络已恢复直连状态。按任意键退出。%C_RESET%
pause >nul
exit


rem ==========================
rem 子程序区域
rem ==========================

:ModifyTun
if not exist "%CONFIG_FILE%" (
    echo  %C_GREEN%未找到 %CONFIG_FILE% , 跳过修改%C_RESET%
    exit /b
)
set "PS_CMD=$file='%CONFIG_FILE%'; $enc=[System.Text.Encoding]::UTF8; $lines=[System.IO.File]::ReadAllLines($file, $enc); $inTun=$false; for($i=0; $i -lt $lines.Length; $i++){ if($lines[$i] -match '^tun:\s*$') { $inTun=$true } elseif($lines[$i] -match '^[a-zA-Z_-]+:') { $inTun=$false } if($inTun -and $lines[$i] -match '^\s+enable:\s*(true|false)') { $lines[$i] = $lines[$i] -replace 'enable:\s*(true|false)', ('enable: ' + '%TUN_STATE%'); break; } } $utf8NoBom = New-Object System.Text.UTF8Encoding $false; [System.IO.File]::WriteAllLines($file, $lines, $utf8NoBom);"
powershell -NoProfile -Command "%PS_CMD%"
exit /b

:EnableSystemProxy
reg add "HKCU\Software\Microsoft\Windows\CurrentVersion\Internet Settings" /v ProxyServer /t REG_SZ /d "%PROXY_SERVER%" /f >nul
reg add "HKCU\Software\Microsoft\Windows\CurrentVersion\Internet Settings" /v ProxyOverride /t REG_SZ /d "%PROXY_BYPASS%" /f >nul
reg add "HKCU\Software\Microsoft\Windows\CurrentVersion\Internet Settings" /v ProxyEnable /t REG_DWORD /d 1 /f >nul
powershell -NoProfile -Command "$q=[char]34; $t='[DllImport('+$q+'wininet.dll'+$q+')] public static extern bool InternetSetOption(int h, int o, int p, int d);'; $w=Add-Type -MemberDefinition $t -Name W -PassThru; $w::InternetSetOption(0,39,0,0) | Out-Null; $w::InternetSetOption(0,37,0,0) | Out-Null"
exit /b

:DisableSystemProxy
reg add "HKCU\Software\Microsoft\Windows\CurrentVersion\Internet Settings" /v ProxyEnable /t REG_DWORD /d 0 /f >nul
powershell -NoProfile -Command "$q=[char]34; $t='[DllImport('+$q+'wininet.dll'+$q+')] public static extern bool InternetSetOption(int h, int o, int p, int d);'; $w=Add-Type -MemberDefinition $t -Name W -PassThru; $w::InternetSetOption(0,39,0,0) | Out-Null; $w::InternetSetOption(0,37,0,0) | Out-Null"
exit /b
