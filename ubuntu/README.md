# Setup Linux

## Installation
[Download the zip from your browser](https://github.com/atomon/dev_setup/archive/refs/heads/main.zip) or clone it from the git command as follows
```bash
$ sudo apt update
$ sudo apt install -y git
$ git clone https://github.com/atomon/dev_setup.git
```

Authorization
```bash
$ cd dev_setup/ubuntu
$ sudo chmod +x ./install.sh
```

## Usage command
**All pkgs**:
- Install all packages
```bash
$ ./install.sh --all
```

**one or more pkgs**:
- Install one or more packages
```bash
$ ./install.sh -i general_apps python
```
