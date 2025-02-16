#!/bin/bash


which uv >& /dev/null
if [[ $? == 0 ]]; then
	echo "✅ uv is already installed"
	exit
fi


## Install uv
curl -LsSf https://astral.sh/uv/install.sh | sh
echo "source $HOME/.local/bin/env" >> ~/.bashrc
eval "$(cat ~/.bashrc | tail -n +10)"

## Enable shell autocompletion
echo 'eval "$(uv generate-shell-completion bash)"' >> ~/.bashrc

# Verify that you can run uv
uv --version
if [[ $? == 0 ]]; then
	echo "✨ Sucessful uv instalation"
else
	echo "❌ ERROR: do not work uv command \"uv --version\""
	exit 1
fi
