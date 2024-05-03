#!/bin/bash


which poetry >& /dev/null
if [[ $? == 0 ]]; then
	echo "✅ Poetry is already installed"
	exit
fi


# Install pipx ref: https://pipx.pypa.io/stable/installation/
# required ubuntu23.04 or latest
which pipx >& /dev/null
if [[ $? != 0 ]]; then
	sudo apt update && sudo apt install -y pipx && pipx ensurepath
	printf "# Created by \`pipx\` on $(date "+%m-%d-%y %T %Z")\n" >> ~/.bashrc
	printf 'eval "$(register-python-argcomplete pipx)"\n\n' >> ~/.bashrc
	eval "$(cat ~/.bashrc | tail -n +10)"
fi


# Install Poetry ref: https://python-poetry.org/docs/#installation
pipx install poetry && poetry config virtualenvs.in-project true
mkdir -p ~/.local/share/bash-completion && poetry completions bash > $_/poetry
printf "# Created by \`poetry\` on $(date "+%m-%d-%y %T %Z")\n" >> ~/.bashrc
printf 'source ~/.local/share/bash-completion/poetry\n\n' >> ~/.bashrc


# Verify that you can run poetry
poetry --version
if [[ $? == 0 ]]; then
	echo "✨ Sucessful poetry instalation"
else
	echo "❌ ERROR: do not work poetry command \"poetry --version\""
	exit 1
fi
