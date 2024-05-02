#!/bin/bash


which poetry >& /dev/null
if [[ $? == 0 ]]; then
	echo "✅ Poetry is already installed"
	exit
fi


# Install pipx ref: https://pipx.pypa.io/stable/installation/
which pipx >& /dev/null
if [[ $? != 0 ]]; then
	sudo apt update && sudo apt install pipx && pipx ensurepath
	printf "# Created by \`pipx\` on $(date "+%m-%d-%y %T %Z")\n" >> ~/.bashrc
	printf 'eval "$(register-python-argcomplete3 pipx)"\n\n' >> ~/.bashrc
	eval "$(cat ~/.bashrc | tail -n +10)"
fi


# Install Poetry ref: https://python-poetry.org/docs/#installation
pipx install poetry && poetry config virtualenvs.in-project true
poetry completions bash >> ~/.local/share/bash-completion/poetry
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
