#!/bin/bash


sudo chmod 755 ./installer/utils/python/pyenv.sh && $_ && exit_code_pyenv=$?
sudo chmod 755 ./installer/utils/python/poetry.sh && $_ && exit_code_poetry=$?


# Verify
exit_code=$((exit_code_pyenv+exit_code_poetry))
if [[ $exit_code == 0 ]]; then
	echo "✨✨ Sucessful Python env instalation"
else
	echo "❌ ERROR: Do not install"
	exit 1
fi
