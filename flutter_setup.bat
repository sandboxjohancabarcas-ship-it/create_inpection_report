@echo off
echo Setting up Flutter from local installation...

REM Set Flutter path from VS Code extension
set FLUTTER_PATH=C:\Users\Cabarcas\flutter\bin

REM Check if flutter.bat exists in VS Code extension
if exist "%FLUTTER_PATH%\flutter.bat" (
    echo Found Flutter at: %FLUTTER_PATH%
    set PATH=%PATH%;%FLUTTER_PATH%
    echo Flutter added to PATH for this session
    echo.
    echo You can now run:
    echo   flutter doctor
    echo   flutter run
    echo   flutter test
    echo.
) else (
    echo Flutter not found in VS Code extension
    echo Checking alternative locations...
    
    REM Check common Flutter installation locations
    if exist "C:\flutter\bin\flutter.bat" (
        set FLUTTER_PATH=C:\flutter\bin
        set PATH=%PATH%;%FLUTTER_PATH%
        echo Found Flutter at: C:\flutter\bin
    ) else (
        echo Flutter not found. Please check VS Code Flutter extension installation.
        echo You may need to restart VS Code after installing Flutter extension.
    )
)

echo Current session ready. You can now use Flutter commands.
echo To make this permanent, add Flutter to your system PATH variables.
pause
