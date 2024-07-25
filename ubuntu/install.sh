#!/bin/bash
# $ ./install.sh -i python

if [[ ! -d installer ]]; then
	printf "\033[33m[ERROR] \e[39mPlease execute it in \`install.sh\` folder, did you mean:\n"
	printf "  command \`cd $( cd -- "$(dirname "$0")" >/dev/null 2>&1 ; pwd -P ) && ./install.sh -h\`\n"
	exit 1
fi

# label=Path
declare -A pkg_list=(
	["1-general_apps"]=general_apps
	["2-ubuntu_setting"]=ubuntu_setting
	["3-mozc"]=mozc
	["4-github_ssh"]=github_ssh
	["5-pyenv"]=utils/python/pyenv
	["6-poetry"]=utils/python/poetry
	["7-python"]=python
	["8-docker"]=docker
	["9-nodejs"]=nodejs
	["10-astronvim"]=astronvim
)
pkg_key_list=$(printf '%s\n' "${!pkg_list[@]}" | sort -n | xargs)


read -r -d '' _help_option << EOF
Usage:  install.sh [OPTIONS]

Options:
	-h, --help                        show command help
	-l, --list                        List of available pkgs
	-i, --install string string ...   Name of patckage to install
	    --all                         install all
	    --dry                         will show list to install (do not install)\n
EOF

# Argument Parser
ArgumentParser(){
	ARGS=$1; shift

	install=()
	all=false
	dry=false
	quiet=""

	while (( $# >= 0 )); do
		
		case "$1" in
 
			-h|--help)
				printf "$_help_option"
				exit 0;;
 
			-i|--install)
				while [[ ! $2 =~ "-" && $# > 0 ]]; do
					install+=($2)
					shift
				done
				shift;;

			--all)
				all=true
				shift;;

			--dry)
				dry=true
				shift;;
				
			-l|--list)
				echo "List of available pkgs"
				for pkg_key in ${pkg_key_list[@]}; do
					printf "\t${pkg_key#*-} \n"
				done
				exit 0;;

			-q|--quiet)
				quiet=' > /dev/null'
				shift;;

			*)
				printf "\033[33m[ERROR] Usage: install.sh [-h] [-i] [--all]\n"
				exit 1;;
		esac
		[[ $# == 0 ]] && break
	done

	eval "$ARGS=(
		["install"]=\"${install[@]}\"
		["all"]=$all
		["dry"]=$dry
		["quiet"]=\"${quiet}\"
	)"
}


# To check if it exists or not
find_name(){
	target=$1; shift
	if ! printf '%s\n' "$@" | grep -qx $target; then
		return 1
	fi
	return 0
}


#####################################################
# Main Script
#####################################################
declare -A args;
ArgumentParser args $@

install_list=${args["install"]}
all=${args["all"]}
dry=${args["dry"]}
quiet=${args["quiet"]}


# Dry step
if [[ $dry == true ]]; then
	printf "Install Packages List\n"
	for pkg_key in ${pkg_key_list[@]}; do
		pkg_name=${pkg_key#*-}

		find_name $pkg_name $install_list
		if [[ ($? == 0 || $all == true) ]]; then
			printf "  $pkg_name  -->  ./installer/${pkg_list[$pkg_key]}.sh\n"
		fi
	done
	exit 0
fi


# Install step
installed=()
for pkg_key in ${pkg_key_list[@]}; do
	pkg_name=${pkg_key#*-} 

	find_name $pkg_name $install_list
	if [[ ($? == 0 || $all == true) ]]; then
		printf "Installing $pkg_name\n"
		sudo chmod 755 ./installer/${pkg_list[$pkg_key]}.sh
		eval $_ ${quiet} && installed+=(${pkg_name%\n})
	fi
done
printf "\n"


# Result step
printf "✨✨✨ Installed package:\n"
printf '\t%s\n' "${installed[@]}"
printf '\n'


read -p "✅ Logout-Login now? [y]Yes, [n]No : " flag
if [[ $flag == 'y' ]]; then
	echo "🚪 Logout after 3 seconds"
	sleep 3s
	gnome-session-quit --no-prompt
fi
