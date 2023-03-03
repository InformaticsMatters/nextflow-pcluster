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

# Install appraiser 1.0.0 (the new singularity)

# # Basic development tools
# yum groupinstall -y 'Development Tools'
# # Ensure EPEL repository is available
# yum install -y epel-release
# # Install RPM packages for dependencies
# yum install -y \
#    libseccomp-devel \
#    squashfs-tools \
#    cryptsetup \
#    wget git
# 
# # Install Go
# export VERSION=1.17.6 OS=linux ARCH=amd64 && \
#     wget https://dl.google.com/go/go$VERSION.$OS-$ARCH.tar.gz && \
#     tar -C /usr/local -xzvf go$VERSION.$OS-$ARCH.tar.gz && \
#     rm go$VERSION.$OS-$ARCH.tar.gz
# export PATH=/usr/local/go/bin:$PATH
# 
# # Get apptainer
# export VERSION=1.0.0 && # adjust this as necessary \
#     wget https://github.com/apptainer/apptainer/releases/download/v${VERSION}/apptainer-${VERSION}.tar.gz && \
#     tar -xzf apptainer-${VERSION}.tar.gz && \
#     cd apptainer-${VERSION}
# # Build apptainer/singularity…
# ./mconfig && \
#     make -C builddir && \
#     make -C builddir install
