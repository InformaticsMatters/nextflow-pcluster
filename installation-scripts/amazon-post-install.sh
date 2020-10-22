#!/bin/bash
#
# ParallelCluster post-installation script for Amazon Linux 2

echo "post-install script has $# arguments"
for arg in "$@"
do
    echo "arg: ${arg}"
done

. "/etc/parallelcluster/cfnconfig"

case "${cfn_node_type}" in
    MasterServer)
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
    container = 'busybox:latest'
}
singularity {
    enabled = true
    cacheDir = '/efs/singularity-cache'
    autoMounts = true
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
# (MasterServer and ComputeFleet)

# Install Singularity
yum -y install singularity
