<#==============
Install posh-git
==============#>
PowerShellGet\Install-Module posh-git -Scope CurrentUser -Force
Add-Content $PROFILE @"
Import-Module posh-git
`$GitPromptSettings.DefaultPromptBeforeSuffix.Text = '``n'
`$GitPromptSettings.DefaultPromptPath.ForegroundColor = 0xFFA500
`$GitPromptSettings.DefaultPromptWriteStatusFirst = `$true
`$GitPromptSettings.DefaultPromptAbbreviateHomeDirectory = `$true
"@ -Encoding utf8NoBOM


<#======================
Setup Git and GitHub SSH
======================#>
echo "`r`nSetup Git and GitHub SSH"
[string] $name = Read-Host "Enter your user name of GitHub"
[string] $email = Read-Host "Enter your email of GitHub"

git --version
git config --global user.name $name
git config --global user.email $email
git config --global color.ui auto
git config --global core.quotepath false
mkdir -p ~/.ssh/github
cd ~/.ssh/github
ssh-keygen -t ed25519 -f id_rsa
ssh-keygen -l -f id_rsa.pub

[string] $flag = "n"
while ( $flag -ne "y" )
{
    echo "`r`nCopy the below SSH key and add it to GitHub"

    cat id_rsa.pub
    $flag = Read-Host "Added your SSH key to GitHub? [y]Yes, [n]No"
}

echo "Host github.com`r`n  HostName github.com`r`n  User git`r`n  IdentityFile ~/.ssh/github/id_rsa`r`n  TCPKeepAlive yes`r`n  IdentitiesOnly yes" >> ~/.ssh/config
ssh -T git@github.com


echo @"

Successful installation! 😎 🎉 
"@
