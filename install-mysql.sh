# Download and Install the Latest Updates for the OS
apt-get update && apt-get upgrade -y
 
#export DEBIAN_FRONTEND=noninteractive
# Set the Server Timezone to CST
echo "Asia/Taipei" > /etc/timezone
dpkg-reconfigure -f noninteractive tzdata
 
# Enable Ubuntu Firewall and allow SSH & MySQL Ports
#ufw enable
#ufw allow 22
#ufw allow 3306
 
# Install essential packages
apt-get -y install zsh htop
 
# Install MySQL Server in a Non-Interactive mode. Default root password will be "testlab"
echo "mysql-server-5.5 mysql-server/root_password password testlab" | sudo debconf-set-selections
echo "mysql-server-5.5 mysql-server/root_password_again password testlab" | sudo debconf-set-selections
apt-get -y install mysql-server
 
 
# Run the MySQL Secure Installation wizard
#mysql_secure_installation
 
sed -i 's/127\.0\.0\.1/0\.0\.0\.0/g' /etc/mysql/my.cnf
mysql -uroot -p -e 'USE mysql; UPDATE `user` SET `Host`="%" WHERE `User`="root" AND `Host`="localhost"; DELETE FROM `user` WHERE `Host` != "%" AND `User`="root"; FLUSH PRIVILEGES;'
 
service mysql restart

echo deb http://archive.ubuntu.com/ubuntu trusty-backports main universe | sudo tee /etc/apt/sources.list.d/backports.list
apt-get update
apt-get install haproxy -t trusty-backports

add-apt-repository ppa:vbernat/haproxy-1.5
apt-get update
apt-get install haproxy