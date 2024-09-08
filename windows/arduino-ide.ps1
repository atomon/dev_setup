# for Windows (host)
## setup for connect USB on wsl
https://github.com/dorssel/usbipd-win/releases/download/v4.3.0/usbipd-win_4.3.0.msi
usbipd list
usbipd bind --busid <budid(ex: 9-3)>
usbipd attach --wsl --busid <busid>

# for WSL (guest)
sudo apt update && sudo apt install -y libnss3 libatk1.0-0 libatk-bridge2.0-0 libcups2-dev libgtk-3-0 libasound2 libsecret-1-0
pip install pyserial
