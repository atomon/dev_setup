#!/bin/bash

sudo snap install slack --classic
sudo snap install discord

# Install vivaldi
curl -fSsL https://repo.vivaldi.com/archive/linux_signing_key.pub | sudo gpg --dearmor | sudo tee /etc/apt/keyrings/vivaldi.gpg >/dev/null
echo deb [arch=amd64 signed-by=/etc/apt/keyrings/vivaldi.gpg] https://repo.vivaldi.com/archive/deb/ stable main | sudo tee /etc/apt/sources.list.d/vivaldi.list
sudo apt update && sudo apt install -y vivaldi-stable

# Chech installed
which slack && which discord && which vivaldi && echo "✨ Installed all apps!!"
