basxConnect Installer Script
============================

Homepage: https://connect.basx.org/

Issues:   https://github.com/basxsoftwareassociation/basxconnect/issues

Requires: bash, curl, sudo (if not root), tar

This script installs basxConnect on your Linux system. You have various options, to install a development environment, or to install a production environment.

	$ curl https://get.basxconnect.solidcharity.com | bash -s devenv --url=test.basxconnect.example.org
	 or
	$ wget -qO- https://get.basxconnect.solidcharity.com | bash -s devenv --url=test.basxconnect.example.org

The syntax is:

	bash -s [devenv|prod]

available options:

     --git_url=<http git url>
            default is: --git_url=https://github.com/basxsoftwareassociation/basxconnect_demo.git
     --branch=<branchname>
            default is: --branch=main
     --url=<outside url>
            default is: --url=localhost
     --behindsslproxy=<true|false>
            default is: --behindsslproxy=true
     --adminemail=<email address of admin>

This should work on Fedora 33/34 and CentOS 8 Stream and Debian 10 (Buster) and Debian 11 (Bullseye) and Ubuntu Focal (20.04).

Please open an issue if you notice any bugs.

Alternative
===========

Instead of using this script, you can also get the basxConnect Demo Repository with git, and use the Makefile:

for Fedora:

    sudo dnf install git make
    git clone https://github.com/basxsoftwareassociation/basxconnect_demo && cd basxconnect_demo
    make quickstart_fedora
    make runserver

for Debian:

    sudo apt-get install git make
    git clone https://github.com/basxsoftwareassociation/basxconnect_demo && cd basxconnect_demo
    make quickstart_debian
    make runserver

Now you can visit this link: http://127.0.0.1:8000/
