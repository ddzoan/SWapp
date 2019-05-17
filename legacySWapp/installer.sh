#!/bin/bash

# first need to:
# curl https://raw.githubusercontent.com/ddzoan/SWapp/master/installer.sh > installer.sh && PASSWORD=password bash installer.sh

apt-get install git -y
apt-add-repository ppa:brightbox/ruby-ng -y
apt-get update -y
apt-get install ruby2.2 -y

apt-get install ruby2.2-dev build-essential -y
apt-get install zlib1g-dev liblzma-dev -y # for nokogiri
apt-get install libsqlite3-dev -y # needed for sqlite3

apt-get install screen -y

gem install bundler

echo "adding user ddzoan"
useradd --create-home -s /bin/bash -p $(echo $PASSWORD | openssl passwd -1 -stdin) ddzoan
usermod -a -G sudo ddzoan

echo "run stuff as ddzoan"
sudo -u ddzoan bash <<STR
cd /home/ddzoan
git clone https://github.com/ddzoan/SWapp.git swapp
cd swapp

# install gems
bundle install --path vendor/bundle

# create DB
bundle exec rake migrate
STR
