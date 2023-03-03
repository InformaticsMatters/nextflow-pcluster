#!/bin/bash
#
# ParallelCluster v3 post-installation script for Amazon Linux 2

echo "post-install script has $# arguments"
for arg in "$@"
do
    echo "arg: ${arg}"
done

. "/etc/parallelcluster/cfnconfig"

case "${cfn_node_type}" in
    HeadNode)
        # epel-release to allow for things like the installation of pip
        yum install -y epel-release

        # Install and configure NTP
        yum install -y ntp
        systemctl start ntpd
        systemctl enable ntpd

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
    ;;

    ComputeFleet)
    ;;

    *)
    ;;
esac

# Common node actions
# (HeadNode and ComputeFleet)

# Install appraiser (the new singularity)
yum -y update
amazon-linux-extras install epel
curl -L -o /etc/yum.repos.d/devel:kubic:libcontainers:stable.repo https://download.opensuse.org/repositories/devel:/kubic:/libcontainers:/stable/CentOS_7/devel:kubic:libcontainers:stable.repo
yum -y install yum-plugin-copr
yum -y copr enable lsm5/container-selinux
yum -y install apptainer
