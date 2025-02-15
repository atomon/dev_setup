$path = (Convert-Path .)


<#=====================
Download ctrl2cap tools
=====================#>
cd $home/Downloads
curl -O https://download.sysinternals.com/files/Ctrl2Cap.zip
7z e -o* .\Ctrl2Cap.zip


<#===========
Administrator
===========#>
if (!([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole("Administrators")) { Start-Process wt.exe "pwsh -wd $path `"$PSCommandPath`"" -Verb RunAs; exit }


<#==============
Install ctrl2cap
==============#>
cd $home/Downloads/Ctrl2Cap
.\ctrl2cap.exe /install

echo @"

Successful installation! 😎 🎉 
Reboot is required!!
"@

cd $pathS
