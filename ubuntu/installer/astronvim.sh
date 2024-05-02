#!/bin/bash

################################################
# # ./astronvim.sh <username of github (option)>
# ./astronvim.sh gituser
#
# username: for astronvim_config
################################################


setup_github_ssh () {
	sudo chmod 755 ./github_ssh.sh && $_
	ssh -T git@github.com || echo "Error: setup github ssh" && exit 1
}


# Install Requirement pkg
sudo apt install -y build-essential cmake ripgrep xsel fuse cargo git
sudo chmod 755 ./utils/nodejs.sh && exit_code_nodejs=$_
sudo chmod 755 ./python.sh && exit_code_python=$_


# Install font
git clone --depth 1 https://github.com/ryanoasis/nerd-fonts.git ./cache/nerd-fonts
sudo chmod 755 ./cache/nerd-fonts/install.sh && $_ && rm -rf ./cache


# Install Neovim
mkdir -p ~/Apps/nvim && nvim_dir=$_ && cd $nvim_dir
curl -LO https://github.com/neovim/neovim/releases/latest/download/nvim.appimage
sudo chmod u+x ./nvim.appimage
if [[ ./nvim.appimage == 0 ]]; then
	sudo ln -s $nvim_dir/nvim.appimage /usr/bin/nvim
else
	sudo ./nvim.appimage --appimage-extract 
	sudo ln -s $nvim_dir/squashfs-root/usr/bin/nvim /usr/bin/nvim
fi


# Install AstroNvim
if [ -d "$HOME/.config/nvim" ]; then mv ~/.config/nvim ~/.config/nvim.bak; fi
if [[ $1 == "" ]]; then
	git clone --depth 1 https://github.com/AstroNvim/template ~/.config/nvim
else
	# Check github connection using ssh
	ssh -T git@github.com || [[ $? == 1 ]] || setup_github_ssh || exit 1
	git clone git@github.com:$1/astronvim_config.git ~/.config/nvim
rm -rf ~/.config/nvim/.git

# Install user setting for astronvim (Version 3 or earlier)
# if [[ $1 != "" ]]; then
#	git clone git@github.com:$1/astronvim_config.git ~/.config/nvim/lua/user
# fi

echo "alias v='nvim'" >> ~/.bash_aliases
n --version && echo "✨ sucessful AstroVim installation"
