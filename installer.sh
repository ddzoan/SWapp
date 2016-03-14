#!/bin/bash

# first need to:
# curl https://raw.githubusercontent.com/ddzoan/SWapp/master/installer.sh | PASSWORD=password bash

if [ $UID -eq 0 ]; then
  apt-get install git -y
  apt-add-repository ppa:brightbox/ruby-ng -y
  apt-get update -y
  apt-get install ruby2.2 -y

  apt-get install ruby-dev zlib1g-dev liblzma-dev -y # for nokogiri
  apt-get install libsqlite3-dev -y # needed for sqlite3

  gem install bundler

  useradd --create-home -s /bin/bash -p $(echo $PASSWORD | openssl passwd -1 -stdin) ddzoan
  # useradd --create-home -s /bin/bash ddzoan
  usermod -a -G sudo ddzoan

  exec su ddzoan "$0"
fi

cd /home/ddzoan
git clone https://github.com/ddzoan/SWapp.git swapp
cd swapp

# install gems
bundle install

# create DB
rake migrate
