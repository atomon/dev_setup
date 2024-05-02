#!/bin/bash

check_installed() {
	ssh -T git@github.com || [[ $? == 1 ]] || exit 1
}

check_installed && echo "already installed" && exit 0

mkdir -p ~/.ssh/github && cd $_

# generate pub-pri key
ssh-keygen -t ed25519 -f id_rsa

echo "publish key"
ssh-keygen -l -f id_rsa.pub

echo "📢 Please copy the following line (ssh key) and add it to GitHub"
cat id_rsa.pub

echo "" && read -p "✅ Added yourt SSH key to GitHub? y[Yes], [n]No : " flag
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
