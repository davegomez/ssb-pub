#!/bin/bash

cd ~

arch=`uname -i`
dist=`cat /etc/*-release | grep DISTRIB_ID | cut -d "=" -f2`

if [[ $arch == x86_64* ]]; then
  ARCH="amd64"
elif [[ $arch == arm* ]]; then
  if [[ $dist == Raspbian ]]; then
    ARCH="armhf"
  else
    ARCH="arm64"
  fi
fi

# Install docker
sudo apt-get update
sudo apt-get remove docker docker-engine docker.io containerd runc
sudo apt-get install -y \
  apt-transport-https \
  ca-certificates \
  curl \
  gnupg-agent \
  software-properties-common
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo apt-key add -
sudo add-apt-repository \
  "deb [arch=${ARCH}] https://download.docker.com/linux/ubuntu \
  $(lsb_release -cs) \
  stable"
sudo apt update
sudo apt-get install -y docker-ce docker-ce-cli containerd.io

sudo groupadd docker
sudo usermod -aG docker $USER
newgrp docker 

sudo service docker start

#
# Install ssb-pub image
#
docker pull davegomez/ssb-pub

#
# Create sbot container
#
mkdir ~/ssb-pub-data
chown -R 1000:1000 ~/ssb-pub-data

#
# Setup sbot config
#
EXTERNAL=$(dig +short myip.opendns.com @resolver1.opendns.com)
cat > ~/ssb-pub-data/config <<EOF
{
  "connections": {
    "incoming": {
      "net": [
        {
          "scope": "public",
          "host": "0.0.0.0",
          "external": ["${EXTERNAL}"],
          "transform": "shs",
          "port": 8008
        }
      ]
    },
    "outgoing": {
      "net": [
        {
          "transform": "shs"
        }
      ]
    }
  }
}
EOF

#
# Create sbot container
#

# Create ./create-sbot script
cat > ./create-sbot <<EOF
#!/bin/bash

MEMORY_LIMIT=$(($(free -b --si | awk '/Mem\:/ { print $2 }') - 200*(10**6)))

docker run -d --name sbot \
  -v ~/ssb-pub-data/:/home/node/.ssb/ \
  -p 8008:8008 \
  --restart unless-stopped \
  --memory "\$MEMORY_LIMIT" \
  davegomez/ssb-pub
EOF
# Make the script executable
chmod +x ./create-sbot
# Run the script
./create-sbot

# Create ./sbot script
cat > ./sbot <<EOF
#!/bin/sh

docker exec -it sbot sbot "\$@"
EOF

# Make the script executable
chmod +x ./sbot

#
# Setup auto-healer
#
docker pull davegomez/healer
docker run -d --name healer \
  -v /var/run/docker.sock:/tmp/docker.sock \
  --restart unless-stopped \
  davegomez/healer

# Ensure containers are always running
printf '#!/bin/sh\n\ndocker start sbot\n' \
  | tee /etc/cron.hourly/sbot \
  && chmod +x /etc/cron.hourly/sbot
printf '#!/bin/sh\n\ndocker start healer\n' \
  | tee /etc/cron.hourly/healer \
  && chmod +x /etc/cron.hourly/healer
