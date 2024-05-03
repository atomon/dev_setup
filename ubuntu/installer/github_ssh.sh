#!/bin/bash

check_installed() {
	ssh -T git@github.com
	if [[ $? == 1 ]]; then
		return 0
	else
		return 1
	fi
}
check_installed && echo "already installed" && exit 0


sudo apt install -y openssh-client


# generate pub-pri key
mkdir -p ~/.ssh/github
ssh-keygen -t ed25519 -f ~/.ssh/github/id_rsa

echo "publish key"
ssh-keygen -l -f ~/.ssh/github/id_rsa.pub

echo ""
echo -e "\e[1m\e[92m📢 Please copy the following line (ssh key) and add it to GitHub\e[39m"
cat ~/.ssh/github/id_rsa.pub

echo "" && echo -e "Registration URL: \e[45mhttps://github.com/settings/keys\e[49m"
read -p "✅ Added yourt SSH key to GitHub? [y]Yes, [n]No : " flag
if [ $flag != 'y' ]; then
	rm -r ~/.ssh/github && echo "delete ~/.ssh/github"
	exit 1
fi

echo "Host github.com
  HostName github.com
  User git
  IdentityFile ~/.ssh/github/id_rsa
  TCPKeepAlive yes
  IdentitiesOnly yes" >>~/.ssh/config

check_installed || (echo "❌ [ERROE] Do not Connect!!" && exit 1)
echo "✨ Connect to GitHub!!"
