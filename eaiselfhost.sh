#!/bin/bash
#
# EAI mail "toaster"
# March 2025
#
# Copyright 2025 Standcore LLC

# Redistribution and use in source and binary forms, with or without
# modification, are permitted provided that the following conditions
# are met:

# 1. Redistributions of source code must retain the above copyright
# notice, this list of conditions and the following disclaimer.

# 2. Redistributions in binary form must reproduce the above copyright
# notice, this list of conditions and the following disclaimer in the
# documentation and/or other materials provided with the distribution.

# THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS
# "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT
# LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR
# A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT
# HOLDER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT,
# INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING,
# BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS
# OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED
# AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT
# LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY
# WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE
# POSSIBILITY OF SUCH DAMAGE.

# installation log goes here
LOGFILE=/tmp/install-log
TARFILE=eaifiles.tar
TARSRC=https://github.com/icann/eaiselfhost/raw/refs/heads/main/eaifiles.tar

# idn2 doesn't work reliably with any other encoding
export LANG=en_US.UTF-8

# all commands are expected to succeed
set -e

# command options
dodns=true
docert=true
dovecot=true
addmbox=false
debug=false

for i
do case "$i" in
  nodns) dodns=false ;;
  nocert) docert=false ;;
  nodovecot) dovecot=false ;;
  addmbox) addmbox=true ;;
  -d) debug=true ;;
  *) echo "Unknown flag $i"; exit 1
  esac
done

# which system
case "$(uname -v)" in
  *Debian*) isdebian=true isubuntu=false ;;
  *Ubuntu*) isdebian=false isubuntu=true ;;
  *) echo -n "Unknown operating system, giving up: "; uname -v
    exit 1
esac
$isdebian && echo Installing on debian.
$isubuntu && echo Installing on Ubuntu.

# this has to be run as root
case "$(id -u)" in
  0) ;;
  *) echo "This script must be run as the superuser.  Enter the sudo password to enable superuser."
     exec sudo -i bash $PWD/$0 $*
     exit 1 ;;
esac

# now running as root
# copy files to /root if need be
if [ ! -s $TARFILE ]
then
    if [ -s /tmp/$TARFILE ]	# already stashed there
    then
	cp /tmp/$TARFILE .
    else
	# get tarfile and put it where we can find it
	echo "=== fetch auxilary files in $TARFILE"
	if wget $TARSRC
	then
	    cp $TARFILE /tmp
	else
	    echo "Error: cannot fetch $TARFILE, giving up"
	    exit 1
	fi
    fi
fi

# aux files in this directory
mkdir -p files
(cd files; tar xf ../$TARFILE)
RF=/root/files

# add mailbox to existing system
if $addmbox
then
   # mail name should already exist
   mname=$(sed -Ene '/^Domain/s/Domain\s*//p' /etc/opendkim.conf)
   if [ ! "$mname" ]
   then
       echo Mail system not set up yet, stopping.
       exit 1
   fi
   exec sh $RF/addmbox $RF $mname
fi

# script to edit a file in place
# sedfile filename <<EOF
# sed commands
#EOF

sedfile ()
{
    cat $2 > /tmp/sed-ins
    sed -f /tmp/sed-ins -i.old $1
}

# yorn "question" defaultletter
yorn()
{
	while echo -n "$1 ($2) "
	do
		read ans
		[ -z "$ans" ] && ans="$2"
		case "$ans" in
		     	[Yy]*)	return 0 ;;
			[Nn]*)	return 1 ;;
		esac
	done
}

# do apt-get install and stash results
aginst()
{
    for i
    do
	echo === install $i
	echo === install $i >> $LOGFILE
        if ! apt-get -y -q install $i < /dev/null >> $LOGFILE 2>&1
	then
	    echo "??? installation of $i failed, giving up"
	    exit 1
	fi
    done
}

# get idn2 for decoding IDN labels
# python modules for the scripts
EARLYPACKAGES="idn2
python3-dnspython
python3-idna
python3-requests
"

# order of packages matters
PACKAGES="postfix
opendkim
opendkim-tools
spamass-milter
spamassassin
spamd
"

if $dovecot
then
PACKAGES="$PACKAGES
dovecot-core
dovecot-imapd
dovecot-pop3d
roundcube-sqlite3
roundcube
apache2
certbot
python3-certbot-apache
"
fi

echo "Installing initial software"
echo ""
# snapshots are usually out of date
echo "Before we can install new software, we need to upgrade any preinstalled software.
The upgrade process usually produces a great deal of output.  It may show pages
telling you that the system needs to be restarted.  If it does, press Enter to
continue.  You can restart the system after installation is complete."
printf "Press Enter to proceed "; read x

echo "=== update software catalog"
apt-get -q -y update
echo "=== upgrade preinstalled packages"
apt-get -q -y upgrade
aginst $EARLYPACKAGES

while :
do
    hn="$(hostname -f)"

    case "$hn" in
     xn--*|*.xn--*) printf "This computer's domain name is %s (%s)\n" $hn $(idn2 -d $hn) ;;
     *) printf "This computer's domain name is %s\n" $hn ;;
    esac

    if yorn "Is that the correct name you wish to use for this computer?" y
    then
      break 2
    else
      echo -n "Enter the correct full domain name using A-labels: "
      read hn
      case "$hn" in *.*) ;;
      *) echo "Name must be a full name of at least two dot-separated labels.  Try again."
         continue ;;
      esac

      hostnamectl hostname "$hn"
      # edit it into the hostname file
      sedfile /etc/hosts <<EOF
/^127.0.1.1/c\\
127.0.1.1	${hn%%.*}

EOF
# full hostname for ubuntu
      echo $hn > /etc/hostname
#      echo ${hn%%.*} > /etc/hostname
    fi
done
   
if yorn "Do you want to use the same domain name for your mail addresses?" y
then
   mailname=$hn
else
   while :
   do
     printf "Enter the domain name to use for mail addresses: "
     read mn
     case "$mn" in *.*) ;;
      *) echo "Mail name must be a full name of at least two dot-separated labels.  Try again."
         continue ;;
      esac
      break
   done
   # turn into a-label
   mailname=$(idn2 $mn)
fi

umailname="$(idn2 -d $mailname)"
echo "Mail domain is $mailname ($umailname)"

# check for DNS records
echo ""
echo "Check for DNS records"
echo ""

if $dodns
then
  if python3 $RF/checkdns.py $mailname $hn
  then
	echo "DNS set up correctly, continuing"
  else
	echo "This mail server will not work until the DNS is set up,
so you should stop, make the DNS changes, and then rerun this script."
    if yorn "Do you want to continue anyway, even though the server will not work?" n
    then
      docert=false # won't work if the signing server can't connect to us
      echo "Continuing, but will not try to get a signed TLS certificate."
    else
      echo "Make the DNS changes, then run this script again."
      exit 1
    fi
  fi
else
  echo "Skipped DNS checks."
fi

echo ""
echo "Installing mail packages"
echo ""

debconf-set-selections <<EOF
postfix postfix/mailname string $hn
postfix postfix/main_mailer_type string 'Internet Site'
# Other destinations to accept mail for (blank for none):
postfix	postfix/destinations	string	localhost
#
# Database type to be used by roundcube:
roundcube-core  roundcube/database-type select  sqlite3
# Configure database for roundcube with dbconfig-common?
roundcube-core	roundcube/dbconfig-install	boolean	true
# IMAP server(s) used with RoundCube:
roundcube-core	roundcube/hosts	string	localhost:143
EOF

aginst $PACKAGES

# does mailuser exist?
if grep -q '^mailuser:' /etc/passwd
then
  echo Using existing mailuser for mailboxes
else
  useradd -m -c "virtual mail user" -U mailuser
  echo Creating mailuser account for mailboxes
fi

# get mailuser info for script edits
eval $(awk -F: '/^mailuser/ { printf "muid=%d mgid=%d mdir=%s\n",$3,$4,$6 } ' /etc/passwd )

echo "
Updating mail configuration
"

cd /etc/postfix

sedfile main.cf <<EOF
# virtual domain only
/^mydestination/c\\
mydestination = localhost

# turn off self-generated certs
/smtpd_tls_cert_file/s/^/# /
/smtpd_tls_key_file/s/^/# /

EOF

# add new config lines
cat >>/etc/postfix/main.cf <<EOF
# local virtual stuff
smtputf8_enable = yes
virtual_mailbox_domains = $mailname, $umailname
virtual_mailbox_base = $mdir
virtual_mailbox_maps = hash:/etc/postfix/vmailbox
virtual_uid_maps = static:$muid
virtual_gid_maps = static:$mgid

# opendkim and spamassassin
smtpd_milters = inet:localhost:8891, unix:spamass/spamass.sock
non_smtpd_milters = inet:localhost:8891
# milter macros useful for spamass-milter
milter_connect_macros = j {daemon_name} v {if_name} _
milter_data_macros = j i {auth_type} {daemon_name} v {if_name} _
milter_rcpt_macros = j {auth_type} {daemon_name} v {if_name} _

EOF
if $dovecot
then
cat >>/etc/postfix/main.cf <<EOF
# dovecot auth
smtpd_sasl_type = dovecot
smtpd_sasl_path = private/auth
#smtpd_sasl_mechanism_filter = login, plain

EOF
fi

# enable submission
sedfile master.cf <<EOF
/#submission /,/smtpd_reject_unlisted_recipient/s/^#//
/#submissions /,/smtpd_reject_unlisted_recipient/s/^#//
/smtpd_tls_auth_only/s/=yes/=no/
# for roundcube, allow login without tls
/smtpd_tls_security_level/s/=.*/=may/
EOF

# create or update
python3 $RF/makeboxes.py -l --maildirs $RF/maildirlist $mailname

echo Creating mailbox directories
while read md
do
    mkdir -p $md/new $md/cur $md/tmp
done < $RF/maildirlist

# be sure they all balong to mailuser
chown -R mailuser:mailuser /home/mailuser/mailboxes

# make postfix mailbox DB
postmap /etc/postfix/vmailbox >>$LOGFILE

# make DKIM certs and start opendkim on port 8891
DKDIR=/etc/dkimkeys
if [ -s $DKDIR/s1.private -a -s $DKDIR/s1.txt ]
then
	echo DKIM key already installed.
else
	echo === Create DKIM keys
	# 1024 bits is short, but the string is much easier to copy
	# than a 2048 bit key
	opendkim-genkey --domain=$mailname --selector=s1 --directory=$DKDIR --append-domain --bits=1024

	sedfile /etc/opendkim.conf << EOF
# our signing domains and selector and key
/^#Domain/c\\
Domain	$mailname

/^#Selector/c\\
Selector	s1

/^#KeyFile/c\\
KeyFile		$DKDIR/s1.private

# listen on local 8891
/^Socket/s/^/#/
/^#Socket.*8891@localhost/s/^#//

EOF
fi
# restart with updated config
systemctl restart opendkim >>$LOGFILE
postfix reload >>$LOGFILE

# should check if key already installed
echo ""
echo "You must add this DKIM record to your DNS if you have not already.  Copy it to a safe place before proceeding"
echo ""

cat $DKDIR/s1.txt
echo ""
echo -n "Press Enter when you have copied those records to add to your DNS: "; read x

if $dovecot
then
  : keep going
else
  echo Postfix installed, installation complete.
  echo 0
fi

# adjust dovecot settings
cd /etc/dovecot
#sedfile dovecot.conf <<EOF
#EOF

sedfile conf.d/10-mail.conf <<EOF
# all mail belongs to mailuser
/^#mail_uid/a\\
mail_uid = mailuser

/^#mail_gid/a\\
mail_gid = mailuser

# maildir mailboxes
/^mail_location/c\\
mail_location = maildir:~/Maildir

EOF

sedfile conf.d/10-auth.conf <<EOF
# turn on auth password
/#!include auth-passwdfile.conf.ext/s/^#//
EOF

sedfile conf.d/10-master.conf <<EOF
# enable socket for Postfix to login for SMTP AUTH
/unix_listener.*spool.postfix/,/}/s/#//
EOF

# read settings
systemctl reload dovecot

# start apache server

echo === configure web server
# just in case, turn on php which requres mpm_prefork
a2dismod mpm_event >>$LOGFILE
a2enmod mpm_prefork >>$LOGFILE

# figure out which PHP there is
PHPVER=$(basename /etc/apache2/mods-available/php8*.conf .conf)
a2enmod $PHPVER >>$LOGFILE


# enable SSL
a2enmod ssl >>$LOGFILE

# set roundcube as document root
for f in /etc/apache2/sites-available/*.conf
do
   sedfile $f <<EOF
/DocumentRoot/c\\
# use roundcube as the main web server\\
	DocumentRoot /var/lib/roundcube/public_html

/ServerName/c\\
	ServerName $hn

EOF
done

# link in and enable roundcube in case not there yet
(cd /etc/apache2/conf-available; ln -sf /etc/roundcube/apache.conf roundcube.conf)
a2enconf roundcube >>$LOGFILE

echo Start web server.
systemctl restart apache2 >>$LOGFILE

# set up SSL cert
if $docert
then
  # do not do this if already done
  if [ -d /etc/letsencrypt/live/$hn ]
  then
    echo TLS certificates already installed.
  else
    echo Get signed TLS certificate for web server.
    certbot -v -n --apache --agree-tos --email postmaster@$hn --domains $hn run >>$LOGFILE 2>&1
    systemctl reload apache2 >>$LOGFILE

    echo Install TLS certificate into mail server.
    # get certbot cert and key file names
    cert=$(sed -ne 's/SSLCertificateFile *//p' /etc/apache2/sites-enabled/*)
    key=$(sed -ne 's/SSLCertificateKeyFile *//p' /etc/apache2/sites-enabled/*)

    # patch certbot cert into postfix config
    postfix tls deploy-server-cert $cert $key >>$LOGFILE 2>&1
    postfix reload >>$LOGFILE

    # patch cert into dovecot config
    sedfile /etc/dovecot/conf.d/10-ssl.conf << EOF
/^ssl_cert *=/c\\
ssl_cert = <$cert

/^ssl_key *=/c\\
ssl_key = <$key

EOF
    dovecot reload >>$LOGFILE

    # make postfix and dovecot reload rotated certbot keys
    printf '#!/bin/sh\n\npostfix reload\ndovecot reload\n' > /etc/letsencrypt/renewal-hooks/deploy/postfix
    chmod +x /etc/letsencrypt/renewal-hooks/deploy/postfix
  fi
else
  # no cert, turn on fake ones
  a2ensite default-ssl >>$LOGFILE
  sed -i.nocert -e '/smtpd_tls_cert_file/s/^# *//' -e '/smtpd_tls_key_file/s/^# *//' /etc/postfix/main.cf
  postfix reload >>$LOGFILE
  systemctl reload apache2 >>$LOGFILE
  echo Using self-signed certs
fi

echo ""
echo === System should be running.
$docert && echo Try the webmail at https://$hn
echo The DKIM key record is at $DKDIR/s1.txt
echo The postfix mailbox map is at /etc/postfix/vmailbox
echo The dovecot password file is at /etc/dovecot/users
echo In case of trouble, see installation log file at $LOGFILE
