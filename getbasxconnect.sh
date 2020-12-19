#!/usr/bin/env bash
#
#                  BasxConnect Installer Script
#
#   Homepage: https://www.basx.org/basxconnect
#   Issues:   https://github.com/basxsoftwareassociation/basxconnect/issues
#   Requires: bash, curl, sudo (if not root), tar
#
# This script installs BasxConnect on your Linux system.
# You have various options, to install a development environment,
# or to install a production environment.
#
#	$ curl https://get.basxconnect.solidcharity.com | bash -s devenv --url=test.basxconnect.example.org
#	 or
#	$ wget -qO- https://get.basxconnect.solidcharity.com | bash -s devenv --url=test.basxconnect.example.org
#
# The syntax is:
#
#	bash -s [devenv|prod]
#
# available options:
#     --git_url=<http git url>
#            default is: --git_url=https://github.com/basxsoftwareassociation/basxconnect_demo.git
#     --branch=<branchname>
#            default is: --branch=test
#     --url=<outside url>
#            default is: --url=localhost
#     --behindsslproxy=<true|false>
#            default is: --behindsslproxy=true
#     --adminemail=<email address of admin>
#
# This should work on Fedora 32/33 and CentOS 8 and Debian 10 (Buster) and Ubuntu Focal (20.04).
# Please open an issue if you notice any bugs.

[[ $- = *i* ]] && echo "Don't source this script!" && return 10

export GIT_URL=https://github.com/basxsoftwareassociation/basxconnect_demo.git
export BRANCH=test
export DBMSType=sqlite
export URL=localhost
export BEHIND_SSL_PROXY=true
export DJANGO_SUPERUSER_USERNAME="admin"
export DJANGO_SUPERUSER_PASSWORD="CHANGEME"
export DJANGO_SUPERUSER_EMAIL="admin@example.org"

setup_nginx()
{
	nginx_conf_path="/etc/nginx/conf.d/basxconnect.conf"

	# let the default nginx server run on another port
	sed -i "s/listen\(.*\)80/listen\181/g" /etc/nginx/nginx.conf
	if [ -f /etc/nginx/sites-enabled/default ]; then
		sed -i "s/listen\(.*\)80/listen\181/g" /etc/nginx/sites-enabled/default
	fi

	cat > $nginx_conf_path <<FINISH
server {
    listen 8000;
    server_name localhost;

    location /static/ {
        alias $SRC_PATH/static/;
    }

    location / {
        proxy_set_header Host \$http_host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_pass http://unix:/run/django/app.socket;
        proxy_read_timeout 1200;
    }
}
FINISH

	# nginx is part of group django, and has read permission on /home/django
	usermod -G nginx,django nginx
	chmod g+rx $USER_HOME

	systemctl start nginx
	systemctl enable nginx
}

generatepwd()
{
	dd bs=1024 count=1 if=/dev/urandom status=none | tr -dc 'a-zA-Z0-9#?_' | fold -w 32 | head -n 1
}

setup_service()
{
	# install basxconnect service file
	systemdpath="/usr/lib/systemd/system"
	if [ ! -d $systemdpath ]; then
		# Ubuntu Bionic, and Debian Stretch
		systemdpath="/lib/systemd/system"
	fi
	cat > $systemdpath/basxconnect.service <<FINISH
[Unit]
Description=Django with unicorn
After=mariadb.service

[Service]
User=django
Group=django
WorkingDirectory=$SRC_PATH
ExecStart=$SRC_PATH/.venv/bin/gunicorn --workers 4 --threads 4 --bind unix:/run/django/app.socket --timeout 1200 wsgi

RuntimeDirectory=django
KillSignal=SIGINT
Restart=always
Type=notify
StandardError=syslog
NotifyAccess=all

[Install]
WantedBy=multi-user.target
FINISH

	systemctl enable basxconnect
	systemctl start basxconnect
}

setup_basxconnect()
{
	export USER_HOME=/home/django
	export SRC_PATH=$USER_HOME/basxconnect

	groupadd django
	useradd --shell /bin/bash --home $USER_HOME --create-home -g django django

	if [ ! -d $SRC_PATH ]
	then
		git clone --depth 50 $GIT_URL -b $BRANCH $SRC_PATH
		#if you want a full repository clone:
		#git config remote.origin.fetch +refs/heads/*:refs/remotes/origin/*
		#git fetch --unshallow
	fi
	cd $SRC_PATH

	python3 -m venv .venv || exit -1
	source .venv/bin/activate
	pip install -r requirements.txt || exit -1

	if [[ "$DBMSType" == "mysql" ]]; then
		pip install mysqlclient || exit -1
	fi

	if [[ "$install_type" == "devenv" ]]; then
		# for code formatting
		pip install black || exit -1

		# for working with the latest packages
		cd ..
		git clone https://github.com/basxsoftwareassociation/htmlgenerator.git || exit -1
		git clone https://github.com/basxsoftwareassociation/bread.git || exit -1
		git clone https://github.com/basxsoftwareassociation/basxconnect.git || exit -1
		cd -
		pip install -e ../htmlgenerator
		pip install -e ../bread
		pip install -e ../basxconnect
	fi

	if [[ "$install_type" == "prod" ]]; then
		pip install gunicorn || exit -1
		python manage.py collectstatic || exit -1
		python manage.py compress --force || exit -1
		cat >> $SRC_PATH/basxconnect/settings/production.py  <<FINISH
ALLOWED_HOSTS = ["$URL"]
#DEBUG = True
#if you are behind a reverse proxy, that does the https encryption:
#SECURE_SSL_REDIRECT = False
#SECURE_PROXY_SSL_HEADER = ('HTTP_X_FORWARDED_PROTO', 'https')
FINISH

		if [[ "$BEHIND_SSL_PROXY" == "true" ]]; then
			sed -i "s/#SECURE_SSL_REDIRECT/SECURE_SSL_REDIRECT/g" $SRC_PATH/basxconnect/settings/production.py
		fi
	fi

	# generate translation .po files from the .mo files
	python manage.py compilemessages || exit -1
}

setup_dbms()
{
	if [[ "$DBMSType" == "mysql" ]]; then
		cat >> $SRC_PATH/basxconnect/settings/local.py <<FINISH
DATABASES = {
    'default': {
        'ENGINE': 'django.db.backends.mysql',
        'OPTIONS': {
            'read_default_file': '$USER_HOME/my.cnf',
        },
    }
}
FINISH

		# TODO: Fedora kommt auch mit /etc/my.cnf zurecht??? oder braucht es /etc/mysql.cnf?
		cat >> $USER_HOME/my.cnf <<FINISH
[client]
database = basxconnect
user = basxconnect
password = "$MYSQL_PWD"
default-character-set = utf8
FINISH

		cat > $SRC_PATH/tmp_setup_mysql.sh <<FINISH
create database basxconnect;
grant all privileges on basxconnect.* to basxconnect@localhost identified by '$MYSQL_PWD';
FINISH

		mysql -u root --password="$MYSQL_ROOT_PWD" < $SRC_PATH/tmp_setup_mysql.sh || exit -1
		rm $SRC_PATH/tmp_setup_mysql.sh
	fi

	python manage.py migrate || exit -1
	python manage.py createsuperuser --noinput || exit -1
}

install_fedora()
{
	packagesToInstall="perl-Image-ExifTool graphviz-devel python3-devel gcc git"
	if [[ "$install_type" == "prod" ]]; then
		packagesToInstall=$packagesToInstall" nginx"
	fi
	if [[ "$DBMSType" == "mysql" ]]; then
		packagesToInstall=$packagesToInstall" mariadb-server mariadb-devel"
	elif [[ "$DBMSType" == "sqlite" ]]; then
		packagesToInstall=$packagesToInstall" sqlite"
	fi
	dnf -y install $packagesToInstall || exit -1
}

install_centos()
{
	yum -y install epel-release || exit -1
	sed -i "s/^enabled=0/enabled=1/" /etc/yum.repos.d/CentOS-PowerTools.repo || exit -1
	packagesToInstall="perl-Image-ExifTool graphviz-devel python3-devel gcc git"
	if [[ "$install_type" == "prod" ]]; then
		packagesToInstall=$packagesToInstall" nginx"
	fi
	if [[ "$DBMSType" == "mysql" ]]; then
		packagesToInstall=$packagesToInstall" mariadb-server mariadb-devel"
	elif [[ "$DBMSType" == "sqlite" ]]; then
		packagesToInstall=$packagesToInstall" sqlite"
	fi
	yum -y install $packagesToInstall || exit -1
}

install_debian()
{
	packagesToInstall="libimage-exiftool-perl libgraphviz-dev python3-venv python3-dev virtualenv gcc git pkg-config"
	if [[ "$install_type" == "prod" ]]; then
		packagesToInstall=$packagesToInstall" nginx"
	fi
	if [[ "$DBMSType" == "mysql" ]]; then
		packagesToInstall=$packagesToInstall" mariadb-server libmariadbclient-dev"
	elif [[ "$DBMSType" == "sqlite" ]]; then
		packagesToInstall=$packagesToInstall" sqlite"
	fi
	apt-get -y install $packagesToInstall || exit -1
}

install_ubuntu()
{
	packagesToInstall="libimage-exiftool-perl libgraphviz-dev python3-venv python3-dev virtualenv gcc git pkg-config"
	if [[ "$install_type" == "prod" ]]; then
		packagesToInstall=$packagesToInstall" nginx"
	fi
	if [[ "$DBMSType" == "mysql" ]]; then
		packagesToInstall=$packagesToInstall" mariadb-server libmariadbclient-dev"
	elif [[ "$DBMSType" == "sqlite" ]]; then
		packagesToInstall=$packagesToInstall" sqlite"
	fi
	apt-get -y install $packagesToInstall || exit -1
}


install()
{
	trap 'echo -e "Aborted, error $? in command: $BASH_COMMAND"; trap ERR; exit 1' ERR
	install_type="$1"

	export DBPWD="`generatepwd`"

	while [ $# -gt 0 ]; do
		case "$1" in
			--git_url=*)
				export GIT_URL="${1#*=}"
				;;
			--branch=*)
				export BRANCH="${1#*=}"
				;;
			--url=*)
				export URL="${1#*=}"
				;;
			--behindsslproxy=*)
				export BEHIND_SSL_PROXY="${1#*=}"
				;;
			--adminemail=*)
				export DJANGO_SUPERUSER_EMAIL="${1#*=}"
				;;
		esac
		shift
	done

	# Valid install type is required
	if [[ "$install_type" != "devenv" && "$install_type" != "prod" ]]; then
		echo "You must specify the install type:"
		echo "  devenv: install a development environment for basxconnect"
		echo "  prod: install a production server with basxconnect"
		return 9
	fi

	if [[ "$install_type" == "prod" ]]; then
		DBMSType="mysql"
	fi

	# you need to run as root
	if [[ "`whoami`" != "root" ]]; then
		echo "You need to run this script as root, or with sudo"
		exit 1
	fi

	#########################
	# Which OS and version? #
	#########################

	unameu="$(tr '[:lower:]' '[:upper:]' <<<$(uname))"
	if [[ $unameu == *LINUX* ]]; then
		install_os="linux"
	else
		echo "Aborted, unsupported or unknown os: $uname"
		return 6
	fi

	if [ -f /etc/os-release ]; then
		. /etc/os-release
		OS=$NAME
		VER=$VERSION_ID

		if [[ "$OS" == "CentOS Linux" ]]; then OS="CentOS"; OS_FAMILY="Fedora"; fi
		if [[ "$OS" == "Red Hat Enterprise Linux Server" ]]; then OS="CentOS"; OS_FAMILY="Fedora"; fi
		if [[ "$OS" == "Fedora" ]]; then OS="Fedora"; OS_FAMILY="Fedora"; fi
		if [[ "$OS" == "Debian GNU/Linux" ]]; then OS="Debian"; OS_FAMILY="Debian"; fi
		if [[ "$OS" == "Ubuntu" ]]; then OS="Ubuntu"; OS_FAMILY="Debian"; fi

		if [[ "$OS" != "CentOS"
			&& "$OS" != "Fedora"
			&& "$OS" != "Debian"
			&& "$OS" != "Ubuntu"
			]]; then
			echo "Aborted, Your distro is not supported: " $OS
			return 6
		fi

		if [[ "$OS_FAMILY" == "Fedora" ]]; then
			if [[ "$VER" != "32" && "$VER" != "33" && "$VER" != "8" ]]; then
				echo "Aborted, Your distro version is not supported: " $OS $VER
				return 6
			fi
		fi
		if [[ "$OS_FAMILY" == "Debian" ]]; then
			if [[ "$VER" != "10" && "$VER" != "20.04" ]]; then
				echo "Aborted, Your distro version is not supported: " $OS $VER
				return 6
			fi
		fi
	else
		echo "Aborted, Your distro could not be recognised."
		return 6
	fi

	if [[ "$OS" == "Fedora" ]]; then
		install_fedora
	elif [[ "$OS" == "CentOS" ]]; then
		install_centos
	elif [[ "$OS" == "Debian" ]]; then
		install_debian
	elif [[ "$OS" == "Ubuntu" ]]; then
		install_ubuntu
	fi

	if [[ "$DBMSType" == "mysql" ]]; then
		if [ -z $MYSQL_ROOT_PWD ]; then
			export MYSQL_ROOT_PWD="`generatepwd`"
			echo "generated mysql root password: $MYSQL_ROOT_PWD"
			systemctl start mariadb
			systemctl enable mariadb
			mysqladmin -u root password "$MYSQL_ROOT_PWD" || exit 1
			systemctl restart mariadb
		fi

		MYSQL_PWD="`generatepwd`"
	fi

	#####################################
	# Setup the development environment #
	#####################################
	if [[ "$install_type" == "devenv" ]]; then

		setup_basxconnect

		setup_dbms

		chown -R django:django $USER_HOME

		# display information to the developer
		echo "Start developing in $SRC_PATH as user django, and use the following commands:"
		echo "    source .venv/bin/activate"
		echo "    python manage.py runserver"
		echo "login with user admin and password CHANGEME, and please change the password immediately."
	fi

	####################################
	# Setup the production environment #
	####################################
	if [[ "$install_type" == "prod" ]]; then

		setup_basxconnect

		setup_dbms

		setup_service

		# configure nginx
		setup_nginx

		chown -R django:django $USER_HOME

		systemctl restart basxconnect
		systemctl restart nginx

		echo "Go and check your instance at $URL:8000"
		echo "login with user admin and password CHANGEME, and please change the password immediately."
	fi
}


install "$@"
