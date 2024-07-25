#!/bin/bash
eval "$(cat ~/.bashrc | tail -n +10)"

which pyenv >& /dev/null
if [[ $? == 0 ]]; then
	echo "✅ Pyenv is already installed"
	exit
fi


sudo apt install -y curl git


# Install pyenv ref: https://github.com/pyenv/pyenv
## sudo apt install libopencv-dev
sudo apt install -y build-essential libffi-dev libssl-dev zlib1g-dev liblzma-dev libbz2-dev \
libreadline-dev libsqlite3-dev libncursesw5-dev libxml2-dev libxmlsec1-dev tk-dev xz-utils

git clone https://github.com/pyenv/pyenv.git ~/.pyenv
cd ~/.pyenv && src/configure && make -C src
printf "# Created by \`pyenv\` on $(date "+%m-%d-%y %T %Z")\n" >> ~/.bashrc
printf 'export PYENV_ROOT="$HOME/.pyenv"\n' >> ~/.bashrc
printf '[[ -d $PYENV_ROOT/bin ]] && export PATH="$PYENV_ROOT/bin:$PATH"\n' >> ~/.bashrc
printf 'eval "$(pyenv init -)"\n\n' >> ~/.bashrc
eval "$(cat ~/.bashrc | tail -n +10)"


# Verify that you can run pyenv
pyenv --version
if [[ $? == 0 ]]; then
	echo "✨ Sucessful pyenv instalation"
else
	echo "❌ ERROR: do not work pyenv command \"pyenv --version\""
	exit 1
fi
