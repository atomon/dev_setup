#!/bin/bash
# $ ./install.sh -i python

if [[ ! -d installer ]]; then
	printf "\033[33m[ERROR] \e[39mPlease execute it in \`install.sh\` folder, did you mean:\n"
	printf "  command \`cd $( cd -- "$(dirname "$0")" >/dev/null 2>&1 ; pwd -P ) && ./install.sh -h\`\n"
	exit 1
fi

# label=Path
declare -A install_priority=(
	["general_apps"]=general_apps
	["ubuntu_setting"]=ubuntu_setting
	["mozc"]=mozc
	["github_ssh"]=github_ssh
	["pyenv"]=utils/python/pyenv
	["poetry"]=utils/python/poetry
	["python"]=python
	["docker"]=docker
	["nodejs"]=nodejs
	["astronvim"]=astronvim
)

read -r -d '' _help_option << EOF
Usage:  install.sh [OPTIONS]

Options:
	-h, --help                        show command help
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
				echo "List of available tags"
				for pkg in ${!install_priority[@]}; do
					printf "\t$pkg\n"
				done
				exit 0;;

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


# Dry step
if [[ $dry == true ]]; then
	for pkg in ${!install_priority[@]}; do
		find_name $pkg $install_list
		if [[ ($? == 0 || $all == true) ]]; then
			printf "./installer/${install_priority[$pkg]}.sh\n"
		fi
	done
	exit 0
fi


# Install step
installed=()
for pkg in ${!install_priority[@]}; do
	find_name $pkg $install_list
	if [[ ($? == 0 || $all == true) ]]; then
		sudo chmod 755 ./installer/${install_priority[$pkg]}.sh
		$_ && installed+=($pkg)
	fi
done
printf "\n"


# Result step
printf "✨✨✨ Installed package:\n"
printf '\t%s\n\n' "${installed[@]}"


read -p "✅ Restart now? [y]Yes, [n]No : " flag
if [[ $flag == 'y' ]]; then
	echo "🚪 Logout after 3 seconds"
	sleep 3s
	gnome-session-quit --no-prompt
fi
