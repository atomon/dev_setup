#!/bin/bash


sudo chmod 755 ./installer/utils/python/uv.sh && $_ && exit_code_uv=$?


# Verify
exit_code=$((exit_code_uv))
if [[ $exit_code == 0 ]]; then
	echo "✨✨ Sucessful Python env instalation"
else
	echo "❌ ERROR: Do not install"
	exit 1
fi
