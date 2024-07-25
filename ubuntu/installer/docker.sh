#!/bin/bash


which docker
if [[ $? == 0 ]]; then
	echo "✅ Docker is already installed"
	exit 0
fi


# ref: https://docs.docker.com/engine/install/ubuntu/#install-using-the-convenience-script
curl -o- https://get.docker.com -o get-docker.sh | bash  # (option) --dry-run {show the script}

# To create the docker group and add your user
sudo groupadd docker
sudo usermod -aG docker $USER


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
