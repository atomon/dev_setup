# Startup
wsl --version
if ( $? -eq $true ) { cp 'C:\ProgramData\Microsoft\Windows\Start Menu\Programs\WSL.lnk' "$env:APPDATA\Microsoft\Windows\Start Menu\Programs\Startup" }
