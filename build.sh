#!/bin/bash
set -ex
PM36=../project-m36
cabal run site -- build
git --work-tree=$PM36 --git-dir=$PM36/.git checkout gh-pages
rsync -avuz _site/ ~/Dev/project-m36/
echo Please commit in $PM36