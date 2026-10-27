@echo off
setlocal
title Timetable Finder
cd /d "%~dp0"

rem Starts the Timetable Finder: the project's Neo4j database (when backend\.env points at it),
rem then the backend, then opens http://localhost:3100 in the browser.
rem To stop: close the windows, or press Ctrl+C in them.

where node >nul 2>nul || (
  echo Node.js is not installed. Install the LTS version from https://nodejs.org and run this file again.
  pause
  exit /b 1
)
if not exist "backend\.env" (
  echo The settings file backend\.env is missing. See "Settings" in README.md.
  pause
  exit /b 1
)
if not exist "backend\node_modules\" (
  echo Installing the backend packages. This is needed only once...
  pushd backend
  call npm install --no-audit --no-fund
  popd
)

rem ---- the project's own database (port 17687), only when backend\.env uses it
findstr /R /C:"^NEO4J_URI=.*:17687" "backend\.env" >nul || goto server
call :up 17687 && goto server
echo Starting the database. This takes about a minute...
rem Neo4j 5 needs Java 17 or 21. Neo4j Desktop brings one, so use that when it is there.
for /d %%J in ("%USERPROFILE%\.Neo4jDesktop2\Cache\runtime\zulu17*" "%USERPROFILE%\.Neo4jDesktop2\Cache\runtime\zulu21*") do (
  if exist "%%~J\bin\java.exe" set "JAVA_HOME=%%~J"
)
start "Timetable Finder database - keep this window open" /d "%~dp0local-neo4j" cmd /k "bin\neo4j.bat console"
set /a tries=0
:wait
call :up 17687 && goto server
set /a tries+=1
if %tries% GEQ 60 (
  echo The database did not start within 3 minutes. Its window shows the reason.
  pause
  exit /b 1
)
ping -n 4 127.0.0.1 >nul
goto wait

:server
cd /d "%~dp0backend"
node src\server.js --open
echo.
echo The server has stopped.
pause
exit /b 0

:up
netstat -ano | findstr /R /C:":%1 .*LISTENING" >nul
exit /b %errorlevel%
