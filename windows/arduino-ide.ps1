# for Windows (host)
## setup for connect USB on wsl
winget install dorssel.usbipd-win
usbipd list
usbipd bind --busid <budid(ex: 9-3)>
usbipd attach --wsl --busid <busid>

wsl --install
wsl --list --online
wsl --set-default Ubuntu
# for WSL (guest)
sudo apt update && sudo apt install -y libnss3 libatk1.0-0 libatk-bridge2.0-0 libcups2-dev libgtk-3-0 libasound2 libsecret-1-0 libfuse2 nodejs npm python3-pip
pip install pyserial
mkdir -p ~/Apps/arduino-ide-2.3.2 && cd $_
curl -LO https://downloads.arduino.cc/arduino-ide/arduino-ide_2.3.2_Linux_64bit.AppImage
sudo chmod 755 arduino-ide_2.3.2_Linux_64bit.AppImage
alias arduino=~/Apps/arduino-ide-2.3.2/arduino-ide_2.3.2_Linux_64bit.AppImage
cat << 'EOS' | sudo tee /etc/fonts/local.conf
<?xml version="1.0"?>
<!DOCTYPE fontconfig SYSTEM "fonts.dtd">
<fontconfig>
    <dir>/mnt/c/Windows/Fonts</dir>
</fontconfig>
<!-- Created by bash script from https://astherier.com/blog/2021/07/windows11-wsl2-wslg-japanese/ -->
EOS

sudo apt update && sudo apt install -y nautilus
