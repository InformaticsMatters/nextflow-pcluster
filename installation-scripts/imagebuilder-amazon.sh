#!/bin/bash
#
# ParallelCluster v3 ImageBuilder script for Amazon Linux 2

# epel-release to allow for things like the installation of pip
yum install -y epel-release

# Install and configure NTP
yum install -y ntp
systemctl start ntpd
systemctl enable ntpd

# Install nextflow
D=$PWD
cd /usr/local/bin
curl -s https://get.nextflow.io | bash
chmod 755 nextflow
cd $D
mkdir -p /efs/singularity-cache
mkdir -p /efs/work
mkdir -p /home/ec2-user/.nextflow
cat <<EOF > /home/ec2-user/.nextflow/config
workDir = '/efs/work'
process {
    executor = 'slurm'
    container = 'centos:7'
}
singularity {
    enabled = true
    cacheDir = '/efs/singularity-cache'
    autoMounts = true
}
executor {
    // default queue size is 100. Increase if >100 cores available
    queueSize = 100
}
EOF
chown -R ec2-user.ec2-user /efs /home/ec2-user/.nextflow

# Install apptainer (the new singularity)
yum -y update
amazon-linux-extras install epel
curl -L -o /etc/yum.repos.d/devel:kubic:libcontainers:stable.repo https://download.opensuse.org/repositories/devel:/kubic:/libcontainers:/stable/CentOS_7/devel:kubic:libcontainers:stable.repo
yum -y install yum-plugin-copr
yum -y copr enable lsm5/container-selinux
yum -y install apptainer
