@echo off
chcp 65001 >nul
title Mihomo Core 控制台

net session >nul 2>&1
if %errorLevel% neq 0 (
    powershell -NoProfile -Command "Start-Process '%~dpnx0' -Verb RunAs"
    exit
)

cls
echo.
echo    正在加载控制台组件，请稍候...

cd /d "%~dp0"
reg add HKCU\Console /v VirtualTerminalLevel /t REG_DWORD /d 1 /f >nul 2>&1
for /F "delims=#" %%E in ('"prompt #$E# & for %%a in (1) do echo."') do set "ESC=%%E"
set "C_RES=%ESC%[0m"
set "C_GRN=%ESC%[92m"
set "C_RED=%ESC%[91m"
set "C_YEL=%ESC%[93m"
set "C_CYN=%ESC%[96m"
set "C_GRY=%ESC%[90m"

set "MIHOMO_EXE=mihomo-windows-amd64.exe"
set "CONFIG_FILE=config.yaml"
set "PROXY_SERVER=127.0.0.1:7890"
set "PROXY_BYPASS=localhost;127.*;10.*;172.16.*;192.168.*;<local>"
set "VBS_FILE=%~dp0MihomoAutoStart.vbs"
set "LOG_OUT=%TEMP%\mihomo_core.tmp"
set "MSG="
set "LAST_SEL=0"

if not exist "%MIHOMO_EXE%" (
    echo. & echo    %C_RED%[X] 缺失核心文件: %MIHOMO_EXE%%C_RES% & pause >nul & exit
)
if not exist "%CONFIG_FILE%" (
    echo. & echo    %C_RED%[X] 缺失配置文件: %CONFIG_FILE%%C_RES% & pause >nul & exit
)

call :InitTUI

:MenuLoop
call :CheckStatus

set "O5=  编辑配置文件  "
set "O6=  查看运行日志  "
set "O7=  切换开机自启  "
set "O8=  打开脚本目录  "

if "%CURRENT_MODE%"=="STOPPED" (
    set "STATUS_TEXT=○ 未运行"
    set "O1=  启动系统代理  "
    set "O2=  启动TUN模式   "
    set "O3=   核心未运行   "
    set "O4=   核心未运行   "
) else if "%CURRENT_MODE%"=="PROXY" (
    set "STATUS_TEXT=● 运行中 [系统代理]"
    set "O1=   当前为代理   "
    set "O2=  切换TUN模式   "
    set "O3=    重启核心    "
    set "O4=    停止核心    "
) else if "%CURRENT_MODE%"=="TUN" (
    set "STATUS_TEXT=● 运行中 [TUN模式]"
    set "O1=  切换系统代理  "
    set "O2=   当前为TUN    "
    set "O3=    重启核心    "
    set "O4=    停止核心    "
)

reg query "HKCU\Software\Microsoft\Windows\CurrentVersion\Run" /v "MihomoCore" >nul 2>&1
if %errorlevel% equ 0 ( set "VBS_TEXT=已开启" ) else ( set "VBS_TEXT=未开启" )

set "CHOICE=0"
powershell -NoProfile -Command "$code = [System.IO.File]::ReadAllText('%TUI_FILE%', [System.Text.Encoding]::UTF8); Invoke-Command -ScriptBlock ([Scriptblock]::Create($code)) -ArgumentList '%STATUS_TEXT%','%VBS_TEXT%','%O1%','%O2%','%O3%','%O4%','%O5%','%O6%','%O7%','%O8%','%MSG%','%LAST_SEL%'"
set "CHOICE=%errorlevel%"
set "MSG="

if "%CHOICE%"=="9" exit
set /a "LAST_SEL=CHOICE-1"

if "%CHOICE%"=="8" goto OpenDir
if "%CHOICE%"=="7" goto ToggleAutoStart
if "%CHOICE%"=="6" goto ViewLogs
if "%CHOICE%"=="5" goto EditConfig
if "%CHOICE%"=="4" goto StopProcess
if "%CHOICE%"=="3" goto RestartCore
if "%CHOICE%"=="2" goto Action2
if "%CHOICE%"=="1" goto Action1
goto MenuLoop

:Action1
if "%CURRENT_MODE%"=="TUN" (
    echo    %C_YEL%» 正在停止 TUN 模式...%C_RES%
    call :KillMihomo
)
goto ModeProxy

:Action2
if "%CURRENT_MODE%"=="PROXY" (
    echo    %C_YEL%» 正在停止系统代理...%C_RES%
    call :KillMihomo
)
goto ModeTun

:RestartCore
echo    %C_YEL%» 正在重启核心...%C_RES%
call :KillMihomo
if "%CURRENT_MODE%"=="TUN" goto ModeTun
if "%CURRENT_MODE%"=="PROXY" goto ModeProxy
goto MenuLoop

:StopProcess
echo    %C_YEL%» 正在停止核心并恢复直连...%C_RES%
call :KillMihomo
call :DisableSystemProxy
if exist "%LOG_OUT%" del /f /q "%LOG_OUT%" >nul 2>&1
echo    %C_GRN%» 核心已停止，系统代理已关闭。%C_RES%
ping 127.0.0.1 -n 2 >nul
set "MSG=提示: 核心已停止，系统代理已恢复直连。"
goto MenuLoop

:ModeProxy
echo    %C_YEL%» 正在应用配置: 系统代理...%C_RES%
set "TUN_STATE=false"
call :ModifyTun
call :EnableSystemProxy
goto RunMihomo

:ModeTun
echo    %C_YEL%» 正在应用配置: TUN模式...%C_RES%
set "TUN_STATE=true"
call :ModifyTun
call :DisableSystemProxy
goto RunMihomo

:RunMihomo
echo    %C_YEL%» 正在执行配置预检...%C_RES%
if exist "%LOG_OUT%" del /f /q "%LOG_OUT%" >nul 2>&1
"%MIHOMO_EXE%" -d . -t > "%LOG_OUT%" 2>&1
if errorlevel 1 goto Rollback

echo    %C_YEL%» 正在后台拉起核心进程...%C_RES%
powershell -NoProfile -Command "Start-Process -WindowStyle Hidden -FilePath 'cmd.exe' -ArgumentList '/c %MIHOMO_EXE% -d . > \"%LOG_OUT%\" 2>&1'"

ping 127.0.0.1 -n 2 >nul
tasklist /FI "IMAGENAME eq %MIHOMO_EXE%" 2>nul | find /I "%MIHOMO_EXE%" >nul
if errorlevel 1 goto Rollback

echo    %C_GRN%» 启动成功！%C_RES%
ping 127.0.0.1 -n 1 >nul

if "%TUN_STATE%"=="true" (
    set "MSG=提示: 核心已成功启动 (当前为 TUN 模式)。"
) else (
    set "MSG=提示: 核心已成功启动 (当前为 系统代理)。"
)
goto MenuLoop

:Rollback
call :DisableSystemProxy
cls
echo.
echo    %C_RED%[X] 启动失败: 配置文件异常或端口被占用！%C_RES%
echo    %C_YEL%» 请按任意键返回主界面，并在菜单中选择“查看运行日志”排查。%C_RES%
pause >nul
set "MSG=错误: 启动失败，配置文件异常或端口被占用！请在菜单中选择“查看运行日志”排查。"
goto MenuLoop

:EditConfig
start "" "%CONFIG_FILE%"
set "MSG=提示: 配置文件修改保存后，请点击“重启核心”使新配置生效！"
goto MenuLoop

:OpenDir
start "" "%~dp0"
set "MSG=提示: 已为您打开脚本所在目录。"
goto MenuLoop

:ViewLogs
cls
echo.
echo    %C_GRY%───────────────[ 实时运行日志 ]───────────────%C_RES%
echo.
powershell -NoProfile -Command "if(Test-Path '%LOG_OUT%'){ $lines = Get-Content '%LOG_OUT%' -Tail 35 -ErrorAction SilentlyContinue; if($lines){ foreach($line in $lines){ if($line -match 'error|FTAL|ERR|fail'){ Write-Host '   '$line -ForegroundColor Red } elseif($line -match 'warning|WARN'){ Write-Host '   '$line -ForegroundColor Yellow } else { Write-Host '   '$line -ForegroundColor Gray } } } else { Write-Host '   日志文件为空' -ForegroundColor DarkGray } } else { Write-Host '   暂无日志记录' -ForegroundColor DarkGray }"
echo.
echo    %C_GRY%──────────────────────────────────────────────%C_RES%
echo.
echo    按任意键返回...
pause >nul
cls
goto MenuLoop

:ToggleAutoStart
reg query "HKCU\Software\Microsoft\Windows\CurrentVersion\Run" /v "MihomoCore" >nul 2>&1
if %errorlevel% equ 0 (
    reg delete "HKCU\Software\Microsoft\Windows\CurrentVersion\Run" /v "MihomoCore" /f >nul 2>&1
    if exist "%VBS_FILE%" del /f /q "%VBS_FILE%" >nul 2>&1
    set "MSG=提示: 已成功关闭开机自启。"
) else (
    call :WriteVBS
    reg add "HKCU\Software\Microsoft\Windows\CurrentVersion\Run" /v "MihomoCore" /t REG_SZ /d "wscript.exe \"%VBS_FILE%\"" /f >nul 2>&1
    set "MSG=提示: 已成功开启开机自启。"
)
goto MenuLoop

:CheckStatus
set "CURRENT_MODE=STOPPED"
tasklist /FI "IMAGENAME eq %MIHOMO_EXE%" 2>nul | find /I "%MIHOMO_EXE%" >nul
if errorlevel 1 exit /b
reg query "HKCU\Software\Microsoft\Windows\CurrentVersion\Internet Settings" /v ProxyEnable 2>nul | find /i "0x1" >nul
if not errorlevel 1 ( set "CURRENT_MODE=PROXY" ) else ( set "CURRENT_MODE=TUN" )
exit /b

:InitTUI
set "TUI_FILE=%TEMP%\mihomo_tui_v25.ps1"
if exist "%TUI_FILE%" exit /b

> "%TUI_FILE%" echo param($s, $v, $o1, $o2, $o3, $o4, $o5, $o6, $o7, $o8, $m, $lsel)
>>"%TUI_FILE%" echo $opts = @($o1, $o2, $o3, $o4, $o5, $o6, $o7, $o8)
>>"%TUI_FILE%" echo $sel = [int]$lsel; if($sel -lt 0 -or $sel -gt 7){ $sel = 0 }
>>"%TUI_FILE%" echo $max = 8; $cols = 4
>>"%TUI_FILE%" echo $host.UI.RawUI.WindowTitle = "Mihomo Core 控制台"
>>"%TUI_FILE%" echo [Console]::TreatControlCAsInput = $true
>>"%TUI_FILE%" echo [Console]::CursorVisible = $false
>>"%TUI_FILE%" echo for($cl=13; $cl -lt 25; $cl++){ [Console]::SetCursorPosition(0, $cl); Write-Host "                                                                                " }
>>"%TUI_FILE%" echo [Console]::SetCursorPosition(0, 14)
>>"%TUI_FILE%" echo if($m){ if($m -match '错误'){ Write-Host "    $m" -ForegroundColor Red }else{ Write-Host "    $m" -ForegroundColor Yellow } }
>>"%TUI_FILE%" echo while($true){
>>"%TUI_FILE%" echo   [Console]::SetCursorPosition(0,0)
>>"%TUI_FILE%" echo   Write-Host "                                                                                "
>>"%TUI_FILE%" echo   Write-Host "    MIHOMO CORE " -ForegroundColor Cyan -NoNewline; Write-Host "控制面板                                           " -ForegroundColor DarkGray
>>"%TUI_FILE%" echo   Write-Host "                                                                                "
>>"%TUI_FILE%" echo   Write-Host "    系统状态: " -NoNewline; if($s -match '未运行'){Write-Host $s"            " -ForegroundColor Red}else{Write-Host $s"            " -ForegroundColor Green}
>>"%TUI_FILE%" echo   Write-Host "    开机自启: " -NoNewline; if($v -match '未开启'){Write-Host $v"            " -ForegroundColor DarkGray}else{Write-Host $v"            " -ForegroundColor Green}
>>"%TUI_FILE%" echo   Write-Host "                                                                                "
>>"%TUI_FILE%" echo   Write-Host "    [ WASD / 方向键 / Tab 切换 | Enter / Space 确认 | ESC 退出 ]              " -ForegroundColor DarkGray
>>"%TUI_FILE%" echo   Write-Host "                                                                                "
>>"%TUI_FILE%" echo   Write-Host "  ┌────────────────┬────────────────┬────────────────┬────────────────┐       " -ForegroundColor DarkCyan
>>"%TUI_FILE%" echo   Write-Host "  │                │                │                │                │       " -ForegroundColor DarkCyan
>>"%TUI_FILE%" echo   Write-Host "  ├────────────────┼────────────────┼────────────────┼────────────────┤       " -ForegroundColor DarkCyan
>>"%TUI_FILE%" echo   Write-Host "  │                │                │                │                │       " -ForegroundColor DarkCyan
>>"%TUI_FILE%" echo   Write-Host "  └────────────────┴────────────────┴────────────────┴────────────────┘       " -ForegroundColor DarkCyan
>>"%TUI_FILE%" echo   for($i=0; $i -lt 8; $i++){
>>"%TUI_FILE%" echo     $x = 3 + ($i %% 4) * 17
>>"%TUI_FILE%" echo     $y = 9 + [math]::Floor($i / 4) * 2
>>"%TUI_FILE%" echo     [Console]::SetCursorPosition($x, $y)
>>"%TUI_FILE%" echo     if($i -eq $sel){ Write-Host $opts[$i] -BackgroundColor Cyan -ForegroundColor Black -NoNewline }
>>"%TUI_FILE%" echo     else{ if($opts[$i] -match "当前|未运行"){ Write-Host $opts[$i] -ForegroundColor DarkGray -NoNewline }else{ Write-Host $opts[$i] -ForegroundColor Gray -NoNewline } }
>>"%TUI_FILE%" echo   }
>>"%TUI_FILE%" echo   for($r=0; $r -lt 2; $r++){
>>"%TUI_FILE%" echo     $y = 9 + $r * 2
>>"%TUI_FILE%" echo     [Console]::SetCursorPosition(2, $y); Write-Host "│" -ForegroundColor DarkCyan
>>"%TUI_FILE%" echo     [Console]::SetCursorPosition(19, $y); Write-Host "│" -ForegroundColor DarkCyan
>>"%TUI_FILE%" echo     [Console]::SetCursorPosition(36, $y); Write-Host "│" -ForegroundColor DarkCyan
>>"%TUI_FILE%" echo     [Console]::SetCursorPosition(53, $y); Write-Host "│" -ForegroundColor DarkCyan
>>"%TUI_FILE%" echo     [Console]::SetCursorPosition(70, $y); Write-Host "│" -ForegroundColor DarkCyan
>>"%TUI_FILE%" echo   }
>>"%TUI_FILE%" echo   [Console]::SetCursorPosition(0, 16)
>>"%TUI_FILE%" echo   while($host.UI.KeyAvailable) { $null = $host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown") }
>>"%TUI_FILE%" echo   $k = $host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
>>"%TUI_FILE%" echo   if($k.KeyDown){
>>"%TUI_FILE%" echo     $vk = $k.VirtualKeyCode
>>"%TUI_FILE%" echo     if($vk -eq 9 -or $vk -eq 39 -or $vk -eq 68){ $sel = $sel + 1; if($sel -ge $max){$sel=0} }
>>"%TUI_FILE%" echo     elseif($vk -eq 37 -or $vk -eq 65){ $sel = $sel - 1; if($sel -lt 0){$sel=$max-1} }
>>"%TUI_FILE%" echo     elseif($vk -eq 40 -or $vk -eq 83){ $sel = $sel + $cols; if($sel -ge $max){$sel=$sel-$max} }
>>"%TUI_FILE%" echo     elseif($vk -eq 38 -or $vk -eq 87){ $sel = $sel - $cols; if($sel -lt 0){$sel=$sel+$max} }
>>"%TUI_FILE%" echo     elseif($vk -eq 13 -or $vk -eq 32){
>>"%TUI_FILE%" echo       if($opts[$sel] -notmatch "当前|未运行"){
>>"%TUI_FILE%" echo         if($sel -eq 4){
>>"%TUI_FILE%" echo           Start-Process 'config.yaml' -ErrorAction SilentlyContinue
>>"%TUI_FILE%" echo           $m = '提示: 配置文件修改保存后，请点击“重启核心”使新配置生效！'
>>"%TUI_FILE%" echo           [Console]::SetCursorPosition(0, 14); Write-Host "                                                                                "
>>"%TUI_FILE%" echo           [Console]::SetCursorPosition(0, 14); Write-Host "    $m" -ForegroundColor Yellow
>>"%TUI_FILE%" echo           continue
>>"%TUI_FILE%" echo         }
>>"%TUI_FILE%" echo         if($sel -eq 7){
>>"%TUI_FILE%" echo           Start-Process '.' -ErrorAction SilentlyContinue
>>"%TUI_FILE%" echo           $m = '提示: 已为您打开脚本所在目录。'
>>"%TUI_FILE%" echo           [Console]::SetCursorPosition(0, 14); Write-Host "                                                                                "
>>"%TUI_FILE%" echo           [Console]::SetCursorPosition(0, 14); Write-Host "    $m" -ForegroundColor Yellow
>>"%TUI_FILE%" echo           continue
>>"%TUI_FILE%" echo         }
>>"%TUI_FILE%" echo         [Console]::CursorVisible = $true
>>"%TUI_FILE%" echo         for($cl=14; $cl -lt 25; $cl++){ [Console]::SetCursorPosition(0, $cl); Write-Host "                                                                                " }
>>"%TUI_FILE%" echo         [Console]::SetCursorPosition(0, 14)
>>"%TUI_FILE%" echo         exit ($sel + 1)
>>"%TUI_FILE%" echo       }
>>"%TUI_FILE%" echo     }
>>"%TUI_FILE%" echo     elseif($vk -eq 27){ [Console]::CursorVisible = $true; Clear-Host; exit 9 }
>>"%TUI_FILE%" echo   }
>>"%TUI_FILE%" echo }
exit /b

:WriteVBS
> "%VBS_FILE%" echo Dim ws, fso, f, line, cleanLine, inTun, tunEnabled
>>"%VBS_FILE%" echo Set ws = CreateObject("WScript.Shell")
>>"%VBS_FILE%" echo Set fso = CreateObject("Scripting.FileSystemObject")
>>"%VBS_FILE%" echo ws.CurrentDirectory = "%~dp0"
>>"%VBS_FILE%" echo inTun = False
>>"%VBS_FILE%" echo tunEnabled = False
>>"%VBS_FILE%" echo If fso.FileExists("%~dp0%CONFIG_FILE%") Then
>>"%VBS_FILE%" echo     Set f = fso.OpenTextFile("%~dp0%CONFIG_FILE%", 1)
>>"%VBS_FILE%" echo     Do Until f.AtEndOfStream
>>"%VBS_FILE%" echo         line = f.ReadLine
>>"%VBS_FILE%" echo         cleanLine = line
>>"%VBS_FILE%" echo         If InStr(cleanLine, "#") ^> 0 Then cleanLine = Left(cleanLine, InStr(cleanLine, "#") - 1)
>>"%VBS_FILE%" echo         If Trim(cleanLine) ^<^> "" Then
>>"%VBS_FILE%" echo             If Left(cleanLine, 1) ^<^> " " And Left(cleanLine, 1) ^<^> Chr(9) Then
>>"%VBS_FILE%" echo                 If Left(cleanLine, 4) = "tun:" Then
>>"%VBS_FILE%" echo                     inTun = True
>>"%VBS_FILE%" echo                 Else
>>"%VBS_FILE%" echo                     inTun = False
>>"%VBS_FILE%" echo                 End If
>>"%VBS_FILE%" echo             End If
>>"%VBS_FILE%" echo             If inTun And InStr(cleanLine, "enable:") ^> 0 And InStr(cleanLine, "true") ^> 0 Then
>>"%VBS_FILE%" echo                 tunEnabled = True
>>"%VBS_FILE%" echo                 Exit Do
>>"%VBS_FILE%" echo             End If
>>"%VBS_FILE%" echo         End If
>>"%VBS_FILE%" echo     Loop
>>"%VBS_FILE%" echo     f.Close
>>"%VBS_FILE%" echo End If
>>"%VBS_FILE%" echo If Not tunEnabled Then
>>"%VBS_FILE%" echo     ws.RegWrite "HKCU\Software\Microsoft\Windows\CurrentVersion\Internet Settings\ProxyServer", "%PROXY_SERVER%", "REG_SZ"
>>"%VBS_FILE%" echo     ws.RegWrite "HKCU\Software\Microsoft\Windows\CurrentVersion\Internet Settings\ProxyOverride", "%PROXY_BYPASS%", "REG_SZ"
>>"%VBS_FILE%" echo     ws.RegWrite "HKCU\Software\Microsoft\Windows\CurrentVersion\Internet Settings\ProxyEnable", 1, "REG_DWORD"
>>"%VBS_FILE%" echo Else
>>"%VBS_FILE%" echo     ws.RegWrite "HKCU\Software\Microsoft\Windows\CurrentVersion\Internet Settings\ProxyEnable", 0, "REG_DWORD"
>>"%VBS_FILE%" echo End If
>>"%VBS_FILE%" echo ws.Run "powershell -NoProfile -WindowStyle Hidden -Command ""$q=[char]34; $t='[DllImport('+$q+'wininet.dll'+$q+')] public static extern bool InternetSetOption(int h, int o, int p, int d);'; $w=Add-Type -MemberDefinition $t -Name W -PassThru; $w::InternetSetOption(0,39,0,0) | Out-Null; $w::InternetSetOption(0,37,0,0) | Out-Null""", 0, True
>>"%VBS_FILE%" echo Dim q: q = Chr(34)
>>"%VBS_FILE%" echo ws.Run "cmd /c " ^& q ^& q ^& "%~dp0%MIHOMO_EXE%" ^& q ^& " -d . > " ^& q ^& "%LOG_OUT%" ^& q ^& " 2>&1" ^& q, 0, False
exit /b

:KillMihomo
taskkill /F /IM "%MIHOMO_EXE%" >nul 2>&1
ping 127.0.0.1 -n 2 >nul
exit /b

:ModifyTun
set "PS_CMD=$file='%CONFIG_FILE%'; $enc=[System.Text.Encoding]::UTF8; $lines=[System.IO.File]::ReadAllLines($file, $enc); $inTun=$false; for($i=0; $i -lt $lines.Length; $i++){ if($lines[$i] -match '^\s*tun:\s*') { $inTun=$true } elseif($lines[$i] -match '^[a-zA-Z_-]+:') { $inTun=$false } if($inTun -and $lines[$i] -match '^\s+enable:\s*(true|false)') { $lines[$i] = $lines[$i] -replace 'enable:\s*(true|false)', ('enable: ' + '%TUN_STATE%'); break; } } $utf8NoBom = New-Object System.Text.UTF8Encoding $false; [System.IO.File]::WriteAllLines($file, $lines, $utf8NoBom);"
powershell -NoProfile -Command "%PS_CMD%"
exit /b

:EnableSystemProxy
reg add "HKCU\Software\Microsoft\Windows\CurrentVersion\Internet Settings" /v ProxyServer /t REG_SZ /d "%PROXY_SERVER%" /f >nul
reg add "HKCU\Software\Microsoft\Windows\CurrentVersion\Internet Settings" /v ProxyOverride /t REG_SZ /d "%PROXY_BYPASS%" /f >nul
reg add "HKCU\Software\Microsoft\Windows\CurrentVersion\Internet Settings" /v ProxyEnable /t REG_DWORD /d 1 /f >nul
call :RefreshSystemProxy
exit /b

:DisableSystemProxy
reg add "HKCU\Software\Microsoft\Windows\CurrentVersion\Internet Settings" /v ProxyEnable /t REG_DWORD /d 0 /f >nul
call :RefreshSystemProxy
exit /b

:RefreshSystemProxy
powershell -NoProfile -Command "$q=[char]34; $t='[DllImport('+$q+'wininet.dll'+$q+')] public static extern bool InternetSetOption(int h, int o, int p, int d);'; $w=Add-Type -MemberDefinition $t -Name W -PassThru; $w::InternetSetOption(0,39,0,0) | Out-Null; $w::InternetSetOption(0,37,0,0) | Out-Null"
exit /b
