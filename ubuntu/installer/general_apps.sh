#!/bin/bash
set -e

sudo apt update && sudo apt install -y curl wget vim git gnome-sushi

# Install apps by snap
sudo snap install slack --classic
sudo snap install discord

# Install vscode
which code >& /dev/null
if [[ $? != 0 ]]; then
	sudo curl https://packages.microsoft.com/keys/microsoft.asc -o /etc/apt/keyrings/microsoft.asc
	echo deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/microsoft.asc] https://packages.microsoft.com/repos/vscode stable main  | sudo tee /etc/apt/sources.list.d/microsoft_vscode.list
	sudo apt update && sudo apt install -y code
fi

# Install vivaldi
which vivaldi >& /dev/null
if [[ $? != 0 ]]; then
	sudo curl -fSsL https://repo.vivaldi.com/archive/linux_signing_key.pub -o /etc/apt/keyrings/vivaldi.asc
	echo deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/vivaldi.asc] https://repo.vivaldi.com/archive/deb/ stable main | sudo tee /etc/apt/sources.list.d/vivaldi.list
	sudo apt update && sudo apt install -y vivaldi-stable
fi

# Chech installed
$(which slack && which discord && which vivaldi)
if [[ $? == 0 ]]; then
	printf "✨ Installed all apps!!\n"
else
	printf "\033[33m[ERROR] do not found apps\n" && exit 1
