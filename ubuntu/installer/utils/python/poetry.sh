#!/bin/bash
eval "$(cat ~/.bashrc | tail -n +10)"

which poetry >& /dev/null
if [[ $? == 0 ]]; then
	echo "✅ Poetry is already installed"
	exit
fi


# Dependent Package
sudo chmod 755 ./installer/utils/python/pyenv.sh && $_


# Install pipx ref: https://pipx.pypa.io/stable/installation/
which pipx >& /dev/null
if [[ $? != 0 ]]; then
	uname_v=$(uname -v)
	majar_v=$(echo ${tes%%.*} | awk -F~ '{print $2}')

	if [[ majar_v < 23 ]]; then
		python3 -m pip install --user pipx
		python3 -m pipx ensurepath
	else
		# required ubuntu23.04 or latest
		sudo apt update && sudo apt install -y pipx && pipx ensurepath
	fi
fi

printf "# Created by \`pipx\` on $(date "+%m-%d-%y %T %Z")\n" >> ~/.bashrc
printf 'eval "$(register-python-argcomplete pipx)"\n\n' >> ~/.bashrc
eval "$(cat ~/.bashrc | tail -n +10)"


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
