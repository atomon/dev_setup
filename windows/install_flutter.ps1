<#===================
Enable developer mode
===================#>
echo "Turn ON, Developer Mode"
start ms-settings:developers


<#==================
Download flutter SDK
==================#>
cd $home/Downloads
curl -O  https://storage.googleapis.com/flutter_infra_release/releases/stable/windows/flutter_windows_3.29.0-stable.zip
Expand-Archive –Path $env:USERPROFILE\Downloads\flutter_windows_3.29.0-stable.zip -Destination $env:USERPROFILE\dev\


 <#=====================
 Add enviroment variable
 =====================#>
$env:PATH = "$env:USERPROFILE\dev\flutter\bin;$env:PATH"
[Environment]::SetEnvironmentVariable("PATH", $env:PATH, "User")

git config --global --add safe.directory C:/Users/ryouh/dev/flutter

<#=================
Validate Enviroment
=================#>
flutter doctor
