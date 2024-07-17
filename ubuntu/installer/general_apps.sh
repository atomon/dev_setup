#!/bin/bash
set -e

sudo apt update && sudo apt install -y curl wget vim git

# Install apps by snap
sudo snap install code --classic
sudo snap install slack --classic
sudo snap install discord

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
