<#======================
powershell version check
======================#>
if ( $Host.Version.Major -lt 7 ) {
    echo "Required 7 or latest of PowerShell major verion"
    exit 1
}

<#============
Work directory
============#>
$path = (Convert-Path .)


<#===========
Administrator
===========#>
if (!([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole("Administrators")) { Start-Process wt.exe "pwsh -wd $path `"$PSCommandPath`"" -Verb RunAs; exit }

<#=========
Set Aliases
=========#>
New-Item -Path $PROFILE -ItemType File -Force
Add-Content $PROFILE @"
Function GO_GitHub {cd C:$env:HOMEPATH\Documents\Github}`r`n
Set-Alias ping Test-NetConnection
Set-Alias chmod icacls
Set-Alias reboot Restart-Computer
Set-Alias github GO_GitHub
"@ -Encoding utf8NoBOM


<#==========================
Install Git and Unix command
==========================#>
winget install Git.Git
$env:PATH += ";C:\Program Files\Git\usr\bin"


<#================
Install nerd-fonts
================#>
git clone --depth 1 https://github.com/ryanoasis/nerd-fonts.git $env:HOMEPATH\Documents\Github\nerd-fonts
cd $env:HOMEPATH\Documents\Github\nerd-fonts
.\install.ps1 CascadiaCode


<#=========
Install App
=========#>
winget install CrystalDewWorld.CrystalDiskInfo
winget install CrystalDewWorld.CrystalDiskMark
winget install Microsoft.VisualStudioCode
winget install SlackTechnologies.Slack
winget install Discord.Discord
winget install Vivaldi.Vivaldi
winget install KiCad.KiCad
winget install 7zip.7zip
$env:PATH += ";C:\Program Files\7-Zip"


<#====================================================
Install Visual Studio

Downloadsフォルダに、vsconfigファイルを用意しておく
vsconfigは、一度手動でインストーラを実行してexportする
2回目以降が楽になる
====================================================#>
# winget install Microsoft.VisualStudio.2022.Community
winget install Microsoft.VisualStudio.2022.BuildTools --override "--config $path\DB\cpp_dotnet_tool.vsconfig"
$env:PATH += @"
;C:\Program Files (x86)\Microsoft Visual Studio\2022\BuildTools\MSBuild\Current\Bin
;C:\Program Files (x86)\Microsoft Visual Studio\2022\BuildTools\VC\Tools\MSVC\14.39.33519\bin\Hostx64\x64
;C:\Program Files (x86)\Microsoft Visual Studio\2022\BuildTools\Common7\IDE\CommonExtensions\Microsoft\CMake\CMake\bin
;C:\Program Files (x86)\Microsoft Visual Studio\2022\BuildTools\Common7\IDE\CommonExtensions\Microsoft\CMake\Ninja
;C:\Program Files (x86)\Microsoft Visual Studio\2022\BuildTools\VC\Auxiliary\Build
"@
# vcvars64.bat


<#==================
Install nodejs (npm)
==================#>
winget install OpenJS.NodeJS
$env:PATH += ";" + $env:APPDATA + "\npm"


<#==========================
Install C++ Compiler (Mingw)

管理者権限必要
==========================#>
cd $env:HOMEPATH\Downloads
curl.exe -LO https://github.com/niXman/mingw-builds-binaries/releases/download/13.2.0-rt_v11-rev1/x86_64-13.2.0-release-win32-seh-msvcrt-rt_v11-rev1.7z
7z.exe x x86_64-13.2.0-release-win32-seh-msvcrt-rt_v11-rev1.7z
mv .\mingw64 'C:\Program Files\'
$env:PATH += ";C:\Program Files\mingw64\bin"


<#================================================
Install Make

WARNING: It may not be the latest
https://gnuwin32.sourceforge.net/packages/make.htm
================================================#>
curl.exe -LO https://sourceforge.net/projects/gnuwin32/files/make/3.81/make-3.81.exe
.\make-3.81.exe


<#===============
Install pyenv-win
===============#>
Invoke-WebRequest -UseBasicParsing -Uri "https://raw.githubusercontent.com/pyenv-win/pyenv-win/master/pyenv-win/install-pyenv-win.ps1" -OutFile "./install-pyenv-win.ps1"; &"./install-pyenv-win.ps1"
pyenv install 3.12.1
pyenv global 3.12.1


<#============
Install Poetry
============#>
winget install Python.Python.3.12
(Invoke-WebRequest -Uri https://install.python-poetry.org -UseBasicParsing).Content | python -
$env:PATH += ";" + $env:APPDATA + "\Python\Scripts"
poetry config virtualenvs.in-project true


<#============
Install Server
============#>
npm i -g zx
winget install tailscale.tailscale


<#=========
Install WSL
=========#>
wsl --install
winget install Docker.DockerCLI
winget install Docker.DockerDesktop
winget install -e --id Kubernetes.kubectl
cd $env:HOMEPATH\Downloads 
curl.exe -LO https://github.com/moby/buildkit/releases/download/v0.12.5/buildkit-v0.12.5.windows-amd64.tar.gz
7z.exe x .\buildkit-v0.12.5.windows-amd64.tar.gz
7z.exe x .\buildkit-v0.12.5.windows-amd64.tar
mkdir -p 'C:\Program Files\buildkit\'
mv .\bin 'C:\Program Files\buildkit\'
rm -r .\buildkit-v0.12.5.windows-amd64.tar


<#===========================
Setup Windows Terminal Config
===========================#>
cp $path\DB\terminal_config.json $env:LOCALAPPDATA\Packages\Microsoft.WindowsTerminal_8wekyb3d8bbwe\LocalState\


<#============
Set Enviroment
============#>
$env:PATH += ";C:\Program Files\buildkit\bin"
[Environment]::SetEnvironmentVariable("PATH", $env:PATH, "User")


echo @"

Successful installation! 😎 🎉 
Reboot is required!!
"@

$flag = Read-Host "Do you want to reboot immediately? Yes[y], No[n]"
cd $path

if ( $flag -eq "y" )
{
    reboot
}
