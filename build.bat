@echo off
REM Build script for V MCP Server (Windows)

echo Building V MCP Server...

REM Build the server from within the project directory
REM Use .\src\main.v - this works correctly with V's module resolution
v -o v-mcp-server.exe .\src\main.v

if %ERRORLEVEL% EQU 0 (
    echo Build complete! Binary: v-mcp-server.exe
    echo.
    echo Usage:
    echo   set V_REPO_PATH=C:\path\to\v
    echo   v-mcp-server.exe
) else (
    echo Build failed!
    exit /b %ERRORLEVEL%
)

