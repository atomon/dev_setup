# Development Environment (Windows 10+)

## Requirements
#### Microsoft Store
- [App installer](https://apps.microsoft.com/detail/9nblggh4nns1?rtc=1&hl=en-us&gl=JP#activetab=pivot:overviewtab) (v1.8 or latest)

<br>

## Setup Dependencies
#### Set ExecutionPolicy
1. The first step, Open terminal (PowerShell) in adminitrater mode.
2. Check execution policy
    ```ps
    # Default is Restricted
    Get-ExecutionPolicy

    # Check each scope
    Get-ExecutionPolicy -List
    ```
3. Change execution policy
    ```ps
    # Set RemoteSigned
    Set-ExecutionPolicy RemoteSigned
    ```

<br>

#### Install Git
```bash:
winget install Git.Git
```

#### Install PowerShell (latest version)
※ Install sprict require PowerShell 7+ version  
（Add-Content コマンドで、utf8NoBOM エンコードを使うため）  
```ps
# Install PowerShell
winget install Microsoft.PowerShell
```

<br>

#### Install Windows Terminal
Windows Terminal の設定から 最新の PowerShell が起動するように設定する  
`settings.json` を読み込んで，ショートカットを設定する
```
# Install Windows Terminal
winget install Microsoft.WindowsTerminal

# Windows Terminal で実行
echo $PSVersionTable
```

## Installation
> [!NOTE]
>コマンドは，Windows Terminal（PowerShell 7+）で実行する

#### Clone repository
```bash:
mkdir -p $home/Documents/Github && cd $home/Documents/Github
git clone https://github.com/atomon/dev_setup.git && cd dev_setup/windows
```

<br>

#### Development Environment
基本的なソフトをインストールする
```ps
.\install.ps1
```

<br>

#### Setup Git
GitHub アカウントなどの設定を行う
```ps
.\setup_git.ps1
```

<br>

#### AstroNvim
```ps
.\install_astronvim.ps1
git clone https://github.com/atomon/astronvim_config_v4.git $env:LOCALAPPDATA\nvim
```

<br>

## Troubleshooting
- winget
  - if there is a `Failed when opening source(s); try the 'source reset' command if the problem persists`, update App Installer from Microsoft Store
