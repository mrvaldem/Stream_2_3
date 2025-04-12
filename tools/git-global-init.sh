#!/bin/bash

# for current user

git config --global user.name "Your Name"
git config --global user.email your@email

# global

git config --global core.quotePath false

# https://git-scm.com/book/en/v2/Git-Basics-Git-Aliases

git config --global alias.co checkout
git config --global alias.br branch
git config --global alias.ci commit
git config --global alias.st status

git config --global alias.unstage "reset HEAD --"
git config --global alias.last "log -1 HEAD"

# for Linux and MacOS
# git config --global core.autocrlf input
# git config --global core.safecrlf true

git config --global http.postBuffer 1048576000

# do it only for administrator mode

# sudo git config --system core.longpaths true
