#!/bin/bash

# language-selector-common language-selector-gnome
sudo apt update
sudo apt install -y language-pack-ja language-pack-ja-base \
	language-pack-gnome-ja language-pack-gnome-ja-base

sudo apt install -y ibus-mozc mozc-utils-gui
gsettings set org.gnome.desktop.input-sources sources "[('ibus', 'mozc-jp')]"

read -p "✅ Do you have custom-keymap file? [y]Yes, [n]No : " flag
if [[ $flag == 'y' ]]; then
	echo "=====================================================
	📢 GUIが起動したら，dev_setup/ubuntu/installer/DB/keymap_switch_en_jp.txt を import させる
		👣 General -> Keymap -> Keymap style -> Customize... -> Edit -> Import from file ...\"
	"
	/usr/lib/mozc/mozc_tool --mode=config_dialog
fi
