#!/bin/bash

# Extend Command Histry
sed -i 's/HISTFILESIZE=2000/HISTFILESIZE=20000/g' ~/.bashrc
echo "export HISTTIMEFORMAT='%F %T  '" >> ~/.bashrc
eval "$(cat ~/.bashrc | tail -n +10)"

mkdir -p ~/Apps

# AutoStart App setting
mkdir -p ~/.config/autostart
cp ./installer/DB/gnome-terminal.desktop ~/.config/autostart/gnome-terminal.desktop
vivaldi --version && cp ./installer/DB/vivaldi.desktop ~/.config/autostart/vivaldi.desktop

# bash completion
sudo apt -y install bash-completion

# Create bash config
if [ ! -f ~/.bash_aliases ]; then touch ~/.bash_aliases; fi

# Set Aliases
echo "alias reload='exec $SHELL -l'" >>~/.bash_aliases

# Set keyboard shortcuts
# ref: https://unix.stackexchange.com/questions/174683/custom-global-keybindings-in-cinnamon-via-gsettings
sudo apt install -y dconf-editor
gsettings set org.gnome.settings-daemon.plugins.media-keys custom-keybindings "[ \
  '/org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/custom0/', \
  '/org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/custom1/', \
  '/org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/custom2/', \
  '/org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/custom3/']"
gsettings set org.gnome.settings-daemon.plugins.media-keys.custom-keybinding:/org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/custom0/ name 'sleep'
gsettings set org.gnome.settings-daemon.plugins.media-keys.custom-keybinding:/org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/custom0/ command 'systemctl suspend'
gsettings set org.gnome.settings-daemon.plugins.media-keys.custom-keybinding:/org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/custom0/ binding '<Super>s'
gsettings set org.gnome.settings-daemon.plugins.media-keys.custom-keybinding:/org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/custom1/ name 'reboot'
gsettings set org.gnome.settings-daemon.plugins.media-keys.custom-keybinding:/org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/custom1/ command 'reboot'
gsettings set org.gnome.settings-daemon.plugins.media-keys.custom-keybinding:/org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/custom1/ binding '<Super>r'
gsettings set org.gnome.settings-daemon.plugins.media-keys.custom-keybinding:/org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/custom2/ name 'shutdown'
gsettings set org.gnome.settings-daemon.plugins.media-keys.custom-keybinding:/org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/custom2/ command 'shutdown -h now'
gsettings set org.gnome.settings-daemon.plugins.media-keys.custom-keybinding:/org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/custom2/ binding '<Super>u'
gsettings set org.gnome.settings-daemon.plugins.media-keys.custom-keybinding:/org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/custom3/ name 'logout'
gsettings set org.gnome.settings-daemon.plugins.media-keys.custom-keybinding:/org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/custom3/ command 'gnome-session-quit --no-prompt'
gsettings set org.gnome.settings-daemon.plugins.media-keys.custom-keybinding:/org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/custom3/ binding '<Super>e'

# Caps2Ctrl
# ref: https://linux.just4fun.biz/?Ubuntu/Caps-Lock%E3%82%AD%E3%83%BC%E3%82%92Ctrl%E3%82%AD%E3%83%BC%E3%81%AB%E3%81%99%E3%82%8B%E6%96%B9%E6%B3%95
sudo sed -i 's/XKBOPTIONS=""/XKBOPTIONS="ctrl:nocaps"/g' /etc/default/keyboard

# Hardware clock is define as local clock
sudo timedatectl set-local-rtc true
