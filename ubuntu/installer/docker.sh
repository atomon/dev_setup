#!/bin/bash


which docker
if [[ $? == 0 ]]; then
	echo "✅ Docker is already installed"
	exit 0
fi

orig_path=$(pwd)
mkdir -p ./cache/docker && cd $_


# ref: https://docs.docker.com/engine/install/ubuntu/#install-using-the-convenience-script
curl -fsSL https://get.docker.com -o get-docker.sh
sudo sh ./get-docker.sh  # (option) --dry-run {show the script}
cd $orig_path

# To create the docker group and add your user
sudo groupadd docker
sudo usermod -aG docker $USER


# activate the changes to groups
newgrp docker << END
echo 'This is running as group $(id -gn)'
END
# or log out and log back


# Verify that you can run docker
sudo docker run hello-world
if [[ $? == 0 ]]; then
	echo "✨ Sucessful docker instalation"
else
	echo "❌ ERROR: do not work docker command \"docker run hello-world\""
	exit 1
fi


# Uninstall  ref: https://docs.docker.com/engine/install/ubuntu/#uninstall-docker-engine
# sudo apt-get purge docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin docker-ce-rootless-extras
# sudo rm -rf /var/lib/docker
# sudo rm -rf /var/lib/containerd
