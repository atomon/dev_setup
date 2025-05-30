#!/bin/bash

$(which node >&/dev/null && which npm >&/dev/null)
if [[ $? == 0 ]]; then
	echo "✅ Poetry is already installed"
	exit
fi

# Info
echo "💻 Version Info of Node.js to be installed
   NVM: 0.40.3
   Node.js: 24
   npm: 11
==========================================
"

sudo apt install -y curl

# Download and install nvm:
curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.40.3/install.sh | bash

# in lieu of restarting the shell
\. "$HOME/.nvm/nvm.sh"

# download and install Node.js
nvm install 24

# verifies the right Node.js version is in the environment
node -v # should print "v24.1.0".

# verifies the right NPM version is in the environment
npm -v # should print `11.3.0`
