#!/bin/bash
set -x

# definitions
export AWS_DEFAULT_REGION=us-east-1

region=$1
userid=$2
username=$3
password=$4
ssh_port=$5
hosted_zone_id=$6
domain=$7
volume_id=$8

instance_id=$(curl -s 169.254.169.254/latest/meta-data/instance-id)
ip=$(curl -s 169.254.169.254/latest/meta-data/public-ipv4)

cd /home/ubuntu


# mount ebs volume
aws ec2 attach-volume --volume-id vol-$volume_id --instance-id $instance_id --device /dev/xvdb --region $region
aws ec2 wait volume-in-use --volume-ids vol-$volume_id
device=$(nvme list | grep $volume_id | awk '{print $1}' | xargs)
while [ -z $device ]; do
    sleep 1
    device=$(nvme list | grep $volume_id | awk '{print $1}' | xargs)
done
mkdir /home/$username
mount $device /home/$username


# add user
useradd -u $userid -d /home/$username -s /bin/bash $username
gpasswd -a $username sudo
cp -arpf /home/ubuntu/.ssh/authorized_keys /home/$username/.ssh/authorized_keys
chown $username /home/$username
chgrp $username /home/$username
chown -R $username /home/$username/.ssh
chgrp -R $username /home/$username/.ssh
echo "$username:$password" | chpasswd


# register route53
curl https://raw.githubusercontent.com/SakuraCase/develop-env-ec2/master/dyndns.tmpl -O
sed -e "s/{%IP%}/$ip/g;s/{%domain%}/$domain/g" dyndns.tmpl > change_resource_record_sets.json
aws route53 change-resource-record-sets --hosted-zone-id $hosted_zone_id --change-batch file:///home/ubuntu/change_resource_record_sets.json


# ssh config
curl https://raw.githubusercontent.com/SakuraCase/develop-env-ec2/master/sshd_config.tmpl -O
sed -e s/{%port%}/$ssh_port/g sshd_config.tmpl > sshd_config.init
cp sshd_config.init /etc/ssh/sshd_config
systemctl restart sshd


# install
# cp -p /etc/apt/sources.list /etc/apt/sources.list.bak
# sed -i 's/us-east-1\.ec2\.//g' /etc/apt/sources.list
apt update
apt install -y nodejs
apt install -y npm
npm install -g yarn


cd /
userdel -r ubuntu