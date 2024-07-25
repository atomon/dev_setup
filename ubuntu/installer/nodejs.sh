#!/bin/bash

$(which node >&/dev/null && which npm >&/dev/null)
if [[ $? == 0 ]]; then
	echo "✅ Poetry is already installed"
	exit
fi

# Info
echo "💻 Version Info of Node.js to be installed
   NVM: 0.39.7
   Node.js: 20
   npm: 10
==========================================
"

sudo apt install -y curl

# installs NVM (Node Version Manager)
curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.39.7/install.sh | bash
eval "$(cat ~/.bashrc | tail -n +10)"

# download and install Node.js
nvm install 20

# verifies the right Node.js version is in the environment
node -v # should print `v20.12.2`

# verifies the right NPM version is in the environment
npm -v # should print `10.5.0`

which node && which npm
if [[ $? == 0 ]]; then
	echo "✨ sucessful nodejs installation"
else 
	exit 1
fi
