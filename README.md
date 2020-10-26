# Nextflow AWS ParallelCluster Configuration
Material for the formation and use of an AWS (slurm-based) compute cluster.

## Overview
These materials create a compute cluster on AWS running the a [Slurm] workload
manager and sets up [Nextflow] to execute workflows.

The cluster is created using [AWS Parallel Cluster], a tool from AWS that
automates the creation of a number of types of cluster on AWS.

Standard usage of these materials results in creating:

-   A VPC with public and private subnets (a pre-existing VPC can be used instead)
-   A single master node in the public subnet
-   An autoscaling group of worker nodes in the private subnet
-   A shared EFS volume mounted at `/efs` on all master and worker nodes
-   A node post installation script that
    -   Installs [Singularity] on all nodes when they are started
    -   Installs and configures Nextflow on the master node

The installation process is highly configurable and can create variations
of the standard usage. Parallel Cluster creates a config file
where these configuration changes can be made.

>   Consult the Parallel Cluster docs for full details.

After you've satisfied the instructions in the **Getting Started** section
below you typically: -

1.  Configure a cluster
2.  Create a cluster
3.  Connect (SSH) to the cluster head node and run your Nextflow workflow
4.  Repeat step 3 until done

## Getting started
Start from a suitable (ideally Python 3.8 or better) virtual environment: -

    $ conda create -n nextflow-pcluster python=3.8
    [...]
    
    $ conda activate nextflow-pcluster
    $ pip install -r requirements.txt --upgrade

### Install jq
[jq] is a convenient JSON query utility, it's useful to install it as some
commands illustrated here rely on it.

    $ jq --version
    jq-1.6

### Key-pairs
As an AWS user with general administrative access, set the user credentials
and default region environment variables for your intended cluster: -

    $ export AWS_ACCESS_KEY_ID=????
    $ export AWS_SECRET_ACCESS_KEY=??????
    $ export AWS_DEFAULT_REGION=eu-central-1

You will need to install a keypair on the account. if you do not have one
or would like to create once specifically for the cluster this can be
easily done with the `aws` CLI and `jq` to conveniently extract the
private key block: -

    $ KEYPAIR_NAME=nf-pcluster
    $ aws ec2 create-key-pair --key-name ${KEYPAIR_NAME} \
        | jq -r .KeyMaterial > ~/.ssh/${KEYPAIR_NAME} && \
        chmod 0600 ~/.ssh/${KEYPAIR_NAME} 

### IAM User and Policies
Using the AWS console (or CLI) create a user you want to use with the cluster
with access type **Programmatic access** and set the name
(`nf-pcluster` in this example) and your AWS ID here (replace the user ID with
your AWS user ID): -

    $ CLUSTER_USER=nf-pcluster
    $ CLUSTER_USER_ID=427674407067

We now create **Policies** in AWS and then attach them to the cluster user.

>   The user's policies must include the the those defined in the `iam`
    directory, as defined in the AWS [ParallelCluster Policies] documentation.

>   Copies of the policies exist in this repository along with a shell-script
    to rapidly adapt them for the user and cluster you're going to create.

Given a region, user account ID and a name you want to use to refer to your
cluster you can render the repository's copy of the reference policy files 
using the following command: -

    $ CLUSTER_NAME=nextflow
    $ ./render-policies.sh ${AWS_DEFAULT_REGION} ${CLUSTER_USER_ID} ${CLUSTER_NAME}

Now install each of the policies using the AWS CLI. The policy names
you choose must be unique for your account: -
    
    $ aws iam create-policy \
        --policy-name NextflowClusterInstancePolicy \
        --policy-document file://nf-instance-policy.json
    
    $ aws iam create-policy \
        --policy-name NextflowClusterUserPolicy \
        --policy-document file://nf-user-policy.json

    $ aws iam create-policy \
        --policy-name NextflowClusterOperatorPolicy \
        --policy-document file://nf-operator-policy.json

     
Now, again using the AWS CLI, attach the policies to your chosen AWS user: -

    $ aws iam attach-user-policy \
        --policy-arn arn:aws:iam::${CLUSTER_USER_ID}:policy/NextflowClusterInstancePolicy \
        --user-name ${CLUSTER_USER}
        
    $ aws iam attach-user-policy \
        --policy-arn arn:aws:iam::${CLUSTER_USER_ID}:policy/NextflowClusterUserPolicy \
        --user-name ${CLUSTER_USER}
        
    $ aws iam attach-user-policy \
        --policy-arn arn:aws:iam::${CLUSTER_USER_ID}:policy/NextflowClusterOperatorPolicy \
        --user-name ${CLUSTER_USER}

### Upload installation scripts
Part of cluster formation permits the execution of installation scripts
that are pulled from AWS S3 as cluster compute instances are formed. Example
_post-installation_ scripts that prepare directories, singularity and
a default configuration file for Nextflow can be found in this repository's
`installation-scripts` directory.

Use one of these scripts unless you have one of your own.

>   At the time of writing there are post-installation scripts for amazon
    (Amazon Linux 2) and centos (CentOS 7).

>   For this example we're going to create a cluster based on the
    **Amazon Linux 2** machine image.

Create an S3 bucket and upload the post-installation script for your
chosen image to it (the bucket's called `nf-pcluster` in this example).
Here we ensure that the file's `acl` (Access Control List)
permits `public-read`: -

    $ CLUSTER_BUCKET=nf-pcluster
    $ CLUSTER_OS=amazon
    $ aws s3 cp installation-scripts/${CLUSTER_OS}-post-install.sh \
        s3://${CLUSTER_BUCKET}/${CLUSTER_OS}-post-install.sh \
        --acl public-read

## Creating a cluster configuration
With the preparation work done we're all set to configure and create a cluster.

We use the `pcluster configure` command's interactive wizard to define our
cluster. This command creates a configuration file that is used by a
separate `create` step.

>   An example execution of the configuration step is illustrated below,
    of course you'll answer the questions in a way that satisfies
    your environment.

>   To date we have only tested using a Centos7 and Amazon Linux 2 as the OS,
    Slurm as the workload manager and a single work queue

The wizard will prompt you with a number of questions. A typical set
of responses for a minimal cluster with auto-generated VPC is reproduced for
convenience below. Here, the configuration is saved to the local file
`config`.

Remove any existing configuration file if it exists...

    $ rm config
    
Then run the configuration wizard: -

    $ pcluster configure -c ./config
    [...]
    AWS Region ID [eu-central-1]:
    [...] 
    EC2 Key Pair Name [nf-pcluster]:
    [...]
    Scheduler [slurm]:
    [...]
    Operating System [alinux2]:
    [...]
    Minimum cluster size (instances) [0]:
    Maximum cluster size (instances) [10]: 2
    Master instance type [t2.micro]: t3a.medium
    Compute instance type [t2.micro]: m4.large
    Automate VPC creation? (y/n) [n]: y
    Network Configuration [Master in a public subnet and compute fleet in a private subnet]: 
    [...]
    Beginning VPC creation. Please do not leave the terminal until the creation is finalized
    [...]
    The stack has been created
    Configuration file written to [...]/config

>   If you're creating a VPC the configuration may take a few minutes.
    
Once complete, edit the resultant configuration file (in `./config`).

We need to provide details of the post-installation script and, in our case,
an EFS volume for shared storage between the cluster instances and a timer
to shutdown idle instances.

Add the following new sections: -

    [efs default]
    shared_dir = efs
    encrypted = false
    performance_mode = generalPurpose
    
    [scaling default]
    scaledown_idletime = 10
    
And add this to the existing `[cluster default]` section,
replacing `<CLUSTER_BUCKET>` and `<CLUSTE_OS>` with the name of your chosen
post-installation bucket: -

    scaling_settings = default
    efs_settings = default
    post_install = https://<CLUSTER_BUCKET>.s3.amazonaws.com/<CLUSTER_OS>-post-install.sh

## Create the cluster
With configuration edited, create the cluster: - 

    $ pcluster create -c ./config ${CLUSTER_NAME}
    Beginning cluster creation for cluster: nextflow
    [...]
    Creating stack named: parallelcluster-nextflow
    Status: parallelcluster-nextflow - CREATE_COMPLETE                              
    ClusterUser: centos
    MasterPrivateIP: 10.0.0.179

>   It may take take 10 to 15 minutes before the cluster formation is complete

## Connect to the cluster
Your cluster's created (well the _head node_ is). You can now use the CLI to
connect to the head node using the SSH key you created earlier. Here we just
make sure Nextflow is correctly installed by running the classic _hello_
workflow, which will create compute instances to run the workflow processes: -

    $ pcluster ssh ${CLUSTER_NAME} -i ~/.ssh/${KEYPAIR_NAME}
    [...]
    
    centos@ip-0-0-0-0 ~]$ nextflow run hello
    N E X T F L O W  ~  version 20.07.1
    [...]
    [4e/8c5c13] process > sayHello (3) [100%] 4 of 4 ✔
    Ciao world!

    Bonjour world!

    Hola world!

    Hello world!

    Completed at: 20-Oct-2020 15:06:36
    Duration    : 4m 46s
    CPU hours   : (a few seconds)
    Succeeded   : 4

>   Initial execution of Nextflow will take some time as
    compute instances need to be instantiated (compute instances are created
    on-demand and, in our configuration, retired automatically when idle
    for 10 minutes) as well as the download of Nextflow dependent modules
    and conversion of the required Docker container image to Singularity. 

Congratulations! You can now run Slurm-based Nextflow workflows!

>   To execute our [fragmentation workflow] you may need the private copy of
    the keypair used to create the cluster in the head-node's
    `~/.ssh/${KEYPAIR_NAME}` directory. This will allow you to create the
    database server (a separate EC2 instance) using the keypair you used to
    create the cluster, remembering to set the head node's file permissions
    correctly (i.e. `chmod 0600 ~/.ssh/${KEYPAIR_NAME}`)

>   An alternative (fast) SSH connection mechanism, armed with the
    Master's address and private key-pari, is
    `ssh -i ~/.ssh/nf-pcluster centos@<MASTER_ADDR>`.

## Deleting the cluster
Once you're done, if you no longer need the cluster, delete it: -

    $ pcluster delete -c ./config ${CLUSTER_NAME}
    Deleting: nextflow
    [...]    
    Cluster deleted successfully.

>   We've noticed that tearing-down the cluster may not always be successful
    (observed October 2020) and manual intervention in the AWS CloudFormation
    console was required. It is always worth checking the AWS CloudFormation
    console to make sure the stack responsible for the cluster has been
    deleted.

Tearing down the cluster does not delete the cluster's VPC. If you allowed
`pcluster` to create the VPC automatically you will need to
remove this yourself using the AWS console (or you can leave it and re-use
it next time).

---

[aws parallel cluster]: https://docs.aws.amazon.com/parallelcluster/index.html
[fragmentation workflow]: https://github.com/InformaticsMatters/fragmentor
[jq]: https://stedolan.github.io/jq/
[nextflow]: https://www.nextflow.io/
[parallelcluster policies]: https://docs.aws.amazon.com/parallelcluster/latest/ug/iam.html#parallelclusteruserpolicy-minimal-user
[singularity]: https://sylabs.io/docs/
[slurm]: https://slurm.schedmd.com
