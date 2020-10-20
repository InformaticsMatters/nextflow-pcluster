#!/bin/bash

echo "post-install script has $# arguments"
for arg in "$@"
do
    echo "arg: ${arg}"
done

. "/etc/parallelcluster/cfnconfig"

case "${cfn_node_type}" in
    MasterServer)
        D=$PWD
        cd /usr/local/bin
	curl -s https://get.nextflow.io | bash
        chmod 755 nextflow
        cd $D
        mkdir /efs/singularity-cache
        mkdir /efs/work
        mkdir /home/centos/.nextflow
        cat <<EOF > /home/centos/.nextflow/config
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
         chown -R centos.centos /efs /home/centos/.nextflow
    ;;
    *)
    ;;
esac

yum -y install "${@:2}"
