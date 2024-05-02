# Development Environment (Windows 10+)

## Requirements
### Microsoft Store
- [App installer](https://apps.microsoft.com/detail/9nblggh4nns1?rtc=1&hl=en-us&gl=JP#activetab=pivot:overviewtab)

<br>

### Set ExecutionPolicy
1. 管理者権限で powershell を起動
2. 実行ポリシーの確認
    ```ps
    # デフォルト設定は Restricted となっている
    Get-ExecutionPolicy

    # スコープごとに確認
    Get-ExecutionPolicy -List
    ```
3. 実行ポリシーの変更
    ```ps
    # RemoteSigned に設定
    Set-ExecutionPolicy RemoteSigned
    ```

<br>

### Install PowerShell (latest version)
※ install スプリクトでは、PowerShell 7+ のバージョンが必要  
（Add-Content コマンドで、utf8NoBOM エンコードを使うため）  
```ps
# Install PowerShell
winget install Microsoft.PowerShell
```

<br>

### Setup Windows Terminal
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

1. このリポジトリの Windows ブランチを ZIP としてダウンロード
2. ZIP を解凍
3. 解凍した位置で Terminal を起動

<br>

### Development Environment
基本的なソフトをインストールする
```ps
.\install.ps1
```

<br>

### Setup Git
GitHub アカウントなどの設定を行う
```ps
.\setup_git.ps1
```

<br>

### AstroNvim
```ps
.\astronvim_install.ps1 {User name of GitHub}
```
