@echo off
setlocal EnableDelayedExpansion

set SRC=%~dp0
if "%SRC:~-1%"=="\" set SRC=%SRC:~0,-1%

set CFG_FILE=%SRC%\deploy.config
set PASS_FILE=%SRC%\synology.pass
set PLINK=%SRC%\plink.exe
set PSCP=%SRC%\pscp.exe

echo.
echo  ====================================================
echo    Telegram Web A -- Deploy to Synology NAS
echo  ====================================================
echo.

:: -- Connection settings (deploy.config) --
if exist "%CFG_FILE%" (
    for /f "usebackq tokens=1,* delims==" %%a in ("%CFG_FILE%") do set "%%a=%%b"
    echo   [OK] Settings loaded from deploy.config
) else (
    echo   First run -- enter your Synology connection details:
    echo.
    set /p HOST=  Synology IP or hostname:
    set /p PORT=  SSH port [22]:
    set /p SSHUSER=  SSH username:
    set /p RDIR=  Remote folder [/volume1/docker/telegram]:
    if "!PORT!"=="" set PORT=22
    if "!RDIR!"=="" set RDIR=/volume1/docker/telegram
    (
        echo HOST=!HOST!
        echo PORT=!PORT!
        echo SSHUSER=!SSHUSER!
        echo RDIR=!RDIR!
    )>"%CFG_FILE%"
    echo.
    echo   [OK] Saved to deploy.config
)
echo.
echo   To   : %SSHUSER%@%HOST%:%RDIR%
echo   Port : %PORT%
echo.

:: -- Password (synology.pass) --
if exist "%PASS_FILE%" (
    set /p PASS=<"%PASS_FILE%"
    echo   [OK] Password loaded from synology.pass
) else (
    set /p PASS=  Enter SSH password:
    echo !PASS!>"%PASS_FILE%"
    echo   [OK] Password saved to synology.pass
)
echo.

:: -- Check setup.sh --
if not exist "%SRC%\setup.sh" ( echo   [ERROR] setup.sh not found next to deploy.bat & goto :end )

:: -- Download plink / pscp if needed --
if not exist "%PLINK%" (
    echo   Downloading plink.exe...
    powershell -NoProfile -Command "Invoke-WebRequest -Uri 'https://the.earth.li/~sgtatham/putty/latest/w64/plink.exe' -OutFile '%PLINK%' -UseBasicParsing"
    if not exist "%PLINK%" ( echo   [ERROR] Failed to download plink.exe & goto :end )
)
if not exist "%PSCP%" (
    echo   Downloading pscp.exe...
    powershell -NoProfile -Command "Invoke-WebRequest -Uri 'https://the.earth.li/~sgtatham/putty/latest/w64/pscp.exe' -OutFile '%PSCP%' -UseBasicParsing"
    if not exist "%PSCP%" ( echo   [ERROR] Failed to download pscp.exe & goto :end )
)
echo   [OK] PuTTY tools ready
echo.

:: -- Step 1: create remote folder (accepts SSH host key on first run) --
echo   Step 1/2  Creating remote folder...
echo y | "%PLINK%" -pw "!PASS!" -P %PORT% %SSHUSER%@%HOST% "mkdir -p %RDIR% && chmod 755 %RDIR% && echo FOLDER_OK"
if %ERRORLEVEL% neq 0 (
    echo   [ERROR] Connection failed. Check deploy.config and synology.pass.
    echo   Delete those files to re-enter settings.
    goto :end
)
echo   [OK] Folder ready
echo.

:: -- Step 2: copy setup.sh --
echo   Step 2/2  Copying setup.sh...
"%PSCP%" -scp -batch -pw "!PASS!" -P %PORT% "%SRC%\setup.sh" %SSHUSER%@%HOST%:%RDIR%/setup.sh
if %ERRORLEVEL% neq 0 ( echo   [ERROR] Copy failed & goto :end )
"%PLINK%" -pw "!PASS!" -P %PORT% %SSHUSER%@%HOST% "chmod +x %RDIR%/setup.sh && echo CHMOD_OK"
if %ERRORLEVEL% neq 0 ( echo   [WARN] chmod failed - run manually: chmod +x %RDIR%/setup.sh ) else ( echo   [OK] setup.sh copied )

echo.
echo  ====================================================
echo    Done!
echo  ====================================================
echo.
echo   Now connect to your Synology and run the installer:
echo     ssh %SSHUSER%@%HOST% -p %PORT%
echo     bash %RDIR%/setup.sh
echo.
echo   Change connection settings: delete deploy.config
echo   Change SSH password:        delete synology.pass
echo.

:end
echo.
pause
