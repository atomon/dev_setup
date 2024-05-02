<#=======
Parameter

$name: user name of GitHub
=======#>
Param([parameter(mandatory=$true)][string] $name)


<#=============
Install ripgrep
=============#>
winget install BurntSushi.ripgrep.MSVC


<#===============================
Install Python

python-lspで必要
WARNING: It may not be the latest
===============================#>
winget install Python.Python.3.12


<#=================================
neovim setup

requirement
- git
- c compiler
- make
- npm
- nerd-fonts
- ripgrep
fontは、win terminal の設定から変更
=================================#>
winget install Neovim.Neovim
git clone --depth 1 https://github.com/AstroNvim/AstroNvim $env:LOCALAPPDATA\nvim
git clone https://github.com/$name/astronvim_config.git $env:LOCALAPPDATA\nvim\lua\user
Add-Content $PROFILE "Set-Alias v nvim" -Encoding utf8NoBOM


echo @"

Successful installation! 😎 🎉 
"@
