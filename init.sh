#!/bin/bash
set -x

# definitions
export AWS_DEFAULT_REGION=us-east-1

region=$1
username=$2
password=$3
ssh_port=$4
hosted_zone_id=$5
domain=$6
volume_id=$7

instance_id=$(curl -s 169.254.169.254/latest/meta-data/instance-id)
ip=$(curl -s 169.254.169.254/latest/meta-data/public-ipv4)

cd /home/ec2-user

# mount ebs volume
aws ec2 attach-volume --volume-id $volume_id --instance-id $instance_id --device /dev/xvdb --region $region
aws ec2 wait volume-in-use --volume-ids $volume_id
until [ -e /dev/xvdb ]; do
    sleep 1
done
sudo mkdir /home/$username
sudo mount /dev/xvdb /home/$username

# add user
sudo useradd -d /home/$username -s /bin/bash $username
sudo usermod -aG wheel $username
sudo cp -arpf /home/ec2-user/.ssh/authorized_keys /home/$username/.ssh/authorized_keys
sudo chown $username /home/$username
sudo chgrp $username /home/$username
sudo chown -R $username /home/$username/.ssh
sudo chgrp -R $username /home/$username/.ssh
echo "$username:$password" | sudo chpasswd

# register route53
curl https://raw.githubusercontent.com/SakuraCase/develop-env-ec2/master/dyndns.tmpl -O
sed -e "s/{%IP%}/$ip/g;s/{%domain%}/$domain/g" dyndns.tmpl > change_resource_record_sets.json
aws route53 change-resource-record-sets --hosted-zone-id $hosted_zone_id --change-batch file:///home/ec2-user/change_resource_record_sets.json

# ssh config
curl https://raw.githubusercontent.com/SakuraCase/develop-env-ec2/master/sshd_config.tmpl -O
sed -e s/{%port%}/$ssh_port/g sshd_config.tmpl > sshd_config.init
sudo cp sshd_config.init /etc/ssh/sshd_config
sudo systemctl restart sshd


echo fs.inotify.max_user_watches=524288 | sudo tee -a /etc/sysctl.conf
sudo sysctl -p

# install
sudo yum update -y
curl -sL https://rpm.nodesource.com/setup_13.x | sudo bash -
sudo yum install -y gcc-c++ make
sudo yum install -y nodejs
sudo npm install -g yarn
sudo yum -y install git
