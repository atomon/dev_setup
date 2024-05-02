#!/bin/bash
# $ ./install.sh -i python

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
        --all                         install all\n
		--dry                         will show list to install (do not install)
EOF

# Argument Parser
ArgumentParser(){
	ARGS=$1; shift

	install=()
	all=false
	dry=false

	while [ $# -gt 0 ]; do
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

			*)
				printf "\033[33m[ERROR] Usage: install.sh [-i] [-a]\n"
				exit 1
		esac
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
		./installer/${install_priority[$pkg]}.sh && installed+=($pkg)
	fi
done
printf "\n"


# Result step
printf "✨✨✨ Installed package:\n"
printf '\t%s\n' "${installed[@]}"


echo "🚪 Logout after 10 seconds"
sleep 10s
gnome-session-quit --no-prompt
