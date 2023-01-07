#!/bin/bash

clear
echo ""
echo "=========================================================================="
echo "|                                                                        |"
echo "|    full-stack-proxy-nginx-grav-for-everyone-with-docker-compose     |"
echo "|                        by Erdal ALTIN                                  |"
echo "|                                                                        |"
echo "=========================================================================="
sleep 2

# Uninstall old versions
echo "Older versions of Docker were called docker, docker.io, or docker-engine. If these are installed, uninstall them"

sudo apt-get remove docker docker-engine docker.io containerd runc

echo ""
echo "Done ✓"
echo "============================================"

# install start
sudo apt-get update
sudo apt-get install ca-certificates curl gnupg lsb-release
sudo mkdir -p /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu $(grep -Po 'UBUNTU_CODENAME=\K[^;]*' /etc/os-release) stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
sudo apt-get update

Installed=`sudo apt-cache policy docker-ce | sed -n '2p' | cut -c 14-`
Candidate=`sudo apt-cache policy docker-ce | sed -n '3p' | cut -c 14-`

if [[ "$Installed" != "$Candidate" ]]; then 
	sudo apt-get install docker-ce docker-ce-cli containerd.io
elif [[ "$Installed" == "$Candidate" ]]; then
	echo ""
	echo 'docker currently version already installed.'
fi


echo ""
echo "Done ✓"
echo "============================================"

##########
# Run Docker without sudo rights
##########
echo ""
echo ""
echo "============================================"
echo "| Running Docker without sudo rights..."
echo "============================================"
echo ""
sleep 2

sudo groupadd docker
sudo usermod -aG docker ${USER}
# su - ${USER} &

echo ""
echo "Done ✓"
echo "============================================"

##########
# Install Docker Compose
##########
echo ""
echo ""
echo "============================================"
echo "| Installing Docker Compose v2.12.2..."
echo "============================================"
echo ""
sleep 2

sudo mkdir -p /usr/local/lib/docker/cli-plugins
sudo curl -SL "https://github.com/docker/compose/releases/download/v2.12.2/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/lib/docker/cli-plugins/docker-compose
sudo chmod +x /usr/local/lib/docker/cli-plugins/docker-compose

# permission for Docker daemon socket
sudo chmod 666 /var/run/docker.sock

echo ""
echo "Done ✓"
echo "============================================"

##########
# Setup project variables
##########
echo ""
echo ""
echo "============================================"
echo "| Please enter project related variables..."
echo "============================================"
echo ""
sleep 2

# set your domain name
domain_name=""
read -p 'Enter Domain Name(e.g. : example.com): ' domain_name
[ -z $domain_name ] && domain_name="NULL"
host -N 0 $domain_name 2>&1 > /dev/null
while [ $? -ne 0 ]
do
	echo "Try again"
	read -p 'Enter Domain Name(e.g. : example.com): ' domain_name
	[ -z $domain_name ] && domain_name="NULL"
	host -N 0 $domain_name 2>&1 > /dev/null
done
echo "Ok."

# set parameters in env.example file
email=""
regex="^[a-zA-Z0-9\._-]+\@[a-zA-Z0-9._-]+\.[a-zA-Z]+\$"
read -p 'Enter Email Address for letsencrypt ssl(e.g. : email@domain.com): ' email
while [ -z $email ] || [[ ! $email =~ $regex ]]
do
	echo "Try again"
	read -p 'Enter Email Address for letsencrypt ssl(e.g. : email@domain.com): ' email
	sleep 1
done
echo "Ok."

local_timezone_regex="^[a-zA-Z0-9/+-_]{1,}$"
read -p 'Enter container local Timezone(default : America/Los_Angeles, to see the other timezones, https://docs.diladele.com/docker/timezones.html): ' local_timezone
: ${local_timezone:=America/Los_Angeles}
while [[ ! $local_timezone =~ $local_timezone_regex ]]
do
	echo "Try again (can only contain numerals 0-9, basic Latin letters, both lowercase and uppercase, positive, minus sign and underscore)"
	read -p 'Enter container local Timezone(default : America/Los_Angeles, to see the other local timezones, https://docs.diladele.com/docker/timezones.html): ' local_timezone
	sleep 1
	: ${local_timezone:=America/Los_Angeles}
done
local_timezone=${local_timezone//[\/]/\\\/}
echo "Ok."

read -p "Apply changes (y/n)? " choice
case "$choice" in
  y|Y ) echo "Yes! Proceeding now...";;
  n|N ) echo "No! Aborting now..."; exit 0;;
  * ) echo "Invalid input! Aborting now..."; exit 0;;
esac

cp env.example .env

sed -i 's/example.com/'$domain_name'/' .env
sed -i 's/email@domain.com/'$email'/' .env
sed -i "s@directory_path@$(pwd)@" .env
sed -i 's/local_timezone/'$local_timezone'/' .env

if [ -x "$(command -v docker)" ] && [ "$(docker compose version)" ]; then
	# Firstly: create external volume
	docker volume create --driver local --opt type=none --opt device=`pwd`/certbot --opt o=bind certbot-etc > /dev/null
	# installing Grav and the other services
	docker compose up -d & export pid=$!
	echo "Grav and the other services installing proceeding..."
	echo ""
	wait $pid
	if [ $? -eq 0 ]
	then
		# installing portainer
		docker volume create portainer_data > /dev/null
		docker compose -f portainer-docker-compose.yml -p portainer up -d & export pid=$!
		echo ""
		echo "portainer installing proceeding..."
		wait $pid
		if [ $? -ne 0 ]; then
			echo "Error! could not installed portainer" >&2
			exit 1
		else
			echo ""
			until [ -n "$(sudo find ./certbot/live -name '$domain_name' 2>/dev/null | head -1)" ]; do
				echo "waiting for Let's Encrypt certificates for $domain_name"
				sleep 5s & wait ${!}
				if sudo [ -d "./certbot/live/$domain_name" ]; then break; fi
			done
			echo "Ok."
			until [ ! -z `docker ps -q -f "status=running" --no-trunc | grep $(docker compose ps -q proxy)` ]; do
				echo "waiting starting proxy container"
				sleep 2s & wait ${!}
				if [ ! -z `docker ps -q -f "status=running" --no-trunc | grep $(docker compose ps -q proxy)` ]; then break; fi
			done			
			echo ""
			echo "Reloading proxy ssl configuration"
			docker container restart proxy > /dev/null 2>&1
			echo "Ok."
			echo ""
			echo "completed setup"
			echo ""
			echo "Website: https://$domain_name"
			echo "Portainer: https://$domain_name:9001"
			echo ""
			echo "Ok."
		fi
	else
		echo ""
		echo "Error! could not installed Grav and the other services with docker compose" >&2
		exit 1
	fi
else
	echo ""
	echo "not found docker and/or docker compose, Install docker and/or docker compose" >&2
	exit 1
fi