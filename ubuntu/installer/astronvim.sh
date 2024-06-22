#!/bin/bash

################################################
# # ./astronvim.sh <username of github (option)>
# ./astronvim.sh gituser
#
# username: for astronvim_config
################################################
which nvim
if [[ $? == 0 ]]; then
	echo "✅ Neovim is already installed"
	exit 0
fi

# Install Requirement pkg
sudo apt install -y build-essential cmake ripgrep xsel fuse3 cargo git
sudo chmod 755 ./utils/nodejs.sh && exit_code_nodejs=$_
sudo chmod 755 ./python.sh && exit_code_python=$_


# Install font
git clone --depth 1 https://github.com/ryanoasis/nerd-fonts.git ./cache/nerd-fonts
sudo chmod 755 ./cache/nerd-fonts/install.sh && $_ CascadiaCode


# Install Neovim
orig_path=$(pwd)
mkdir -p ~/Apps/nvim && nvim_dir=$_ && cd $nvim_dir
curl -LO https://github.com/neovim/neovim/releases/latest/download/nvim.appimage
sudo chmod u+x ./nvim.appimage && $_ --version
if [[ $? == 0 ]]; then
	sudo ln -s $nvim_dir/nvim.appimage /usr/bin/nvim
else
	sudo ./nvim.appimage --appimage-extract >& /dev/null && sudo ln -s $nvim_dir/squashfs-root/usr/bin/nvim /usr/bin/nvim
fi
cd $orig_path


# Install AstroNvim
if [ -d "$HOME/.config/nvim" ]; then mv ~/.config/nvim ~/.config/nvim.bak; fi
git clone --depth 1 https://github.com/AstroNvim/template ~/.config/nvim
rm -rf ~/.config/nvim/.git


# Install user setting for astronvim (Version 3 or earlier)
# if [[ $1 != "" ]]; then
#	git clone git@github.com:$1/astronvim_config.git ~/.config/nvim/lua/user
# fi


echo "alias v='nvim'" >> ~/.bash_aliases
eval "$(cat ~/.bashrc | tail -n +10)"
nvim --version
if [[ $? == 0 ]]; then
	echo "✨ sucessful AstroVim installation"
else 
	exit 1
fi
