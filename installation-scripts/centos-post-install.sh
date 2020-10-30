#!/bin/bash
#
# ParallelCluster post-installation script for CentOS 7

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
        mkdir -p /home/centos/.nextflow
        cat <<EOF > /home/centos/.nextflow/config
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
         chown -R centos.centos /efs /home/centos/.nextflow
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
