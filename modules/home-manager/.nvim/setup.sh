#!/usr/bin/env bash

# Install Cargo
curl https://sh.rustup.rs -sSf | sh

# Instal NPM
sudo dnf install nodejs

# Additional Copilot commands
git clone https://github.com/github/copilot.vim.git ~/.vim/pack/github/start/copilot.vim
