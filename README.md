# GOST-V3

A Bash script to install and manage GOST v3 tunneling services.

## Features
- Installs GOST v3 and dependencies.
- Manages services (add, remove, edit, start/stop/restart).
- Supports Foreign and Domestic server modes.

## Usage
Download and run the script interactively:
```bash
wget -O gost_manager.sh https://raw.githubusercontent.com/cygnusleoimirgalileo/GOST-V3/main/gost_manager.sh
chmod +x gost_manager.sh
sudo ./gost_manager.sh
```
On the first run, a shortcut gost will be created. After that, you can run the script with:
```bash
sudo gost-manager
