@echo off
title 2026 Men's FIH Hockey World Cup AI Dashboard
echo ===================================================
echo Starting Hockey Intelligence Shiny Application...
echo ===================================================
cd /d "%~dp0"

set RSCRIPT="C:\Program Files\R\R-4.4.2\bin\Rscript.exe"

if exist %RSCRIPT% (
    %RSCRIPT% -e "shiny::runApp('app', host='127.0.0.1', port=3838, launch.browser=TRUE)"
) else (
    Rscript -e "shiny::runApp('app', host='127.0.0.1', port=3838, launch.browser=TRUE)"
)

pause
