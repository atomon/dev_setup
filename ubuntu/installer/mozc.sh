#!/bin/bash

# language-selector-common language-selector-gnome

sudo apt install -y language-pack-ja language-pack-ja-base \
	language-pack-gnome-ja language-pack-gnome-ja-base

sudo apt install -y ibus-mozc
gsettings set org.gnome.desktop.input-sources sources "[('ibus', 'mozc-jp')]"

echo "📢 GUIが起動したら，DB/keymap_switch_en_jp.txt を import させる
   👣 General -> Keymap -> Keymap style -> Customize... -> Edit -> Import from file ...\"
"
/usr/lib/mozc/mozc_tool --mode=config_dialog
