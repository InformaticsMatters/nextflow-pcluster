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
-   Installs [Singularity] on all nodes when they are started
-   Installs and configures Nextflow on the master node

The installation process is highly configurable and can create variations
of the standard usage. Parallel cluster uses a config file
(`~/.parallelcluster/config` by default) where these
configuration changes can be made.

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
As an AWS user with general administrative access, set you user credentials
and default region for your intended cluster: -

    $ export AWS_ACCESS_KEY_ID=????
    $ export AWS_SECRET_ACCESS_KEY=??????
    $ export AWS_DEFAULT_REGION=eu-central-1

You will need to install a keypair on the account.
Easily done with the `aws` CLI and `jq` to conveniently extract the
private key block: -

    $ KEYPAIR_NAME=nf-pcluster
    $ aws ec2 create-key-pair --key-name ${KEYPAIR_NAME} \
        | jq -r .KeyMaterial > ~/.ssh/${KEYPAIR_NAME} && \
        chmod 0600 ~/.ssh/${KEYPAIR_NAME} 

### IAM User and Policies
Using the AWS console (or CLI) create a user with access type
**Programmatic access** and collect the name (`nf-pcluster` here), ID,
access key and secret key.

Set some convenient environment variables, ones we rely on in the following
examples: -

    $ CLUSTER_USER=nf-pcluster
    $ CLUSTER_USER_ID=427674407067

We now create and attach suitable policies to the user.

The user's policies must include the the those defined in the `iam`
directory, as defined in the AWS [ParallelCluster Policies] documentation.

>   Copies of the policies exist in this repository along with a shell-script
    to rapidly adapt them for the user and cluster you're going to create.

Given a region, user account ID (of a user with programmatic access you'll
use to create the cluster) and indented cluster name you can render the
policy files (into the project root) using the following: -

    $ CLUSTER_NAME=nextflow
    $ ./render-policies.sh ${AWS_DEFAULT_REGION} ${CLUSTER_USER_ID} ${CLUSTER_NAME}

You can install each of the policies using the AWS CLI: -
    
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
that are pulled from AWS S3 as cluster compute instances are formed. An
example _post-installation_ script that prepares directories, singularity and
a default configuration file for Nextflow can be found in this repository's
`installation-scripts` directory.

Use this script unless you have one of your own.

Create an S3 bucket and upload `installation-scripts/post-install.sh`
to it (the bucket's called `nf-pcluster` in this example) ensuring that the
file's `acl` (Access Control List) permits `public-read`: -

    $ CLUSTER_BUCKET=nf-pcluster
    $ aws s3 cp installation-scripts/post-install.sh \
        s3://${CLUSTER_BUCKET}/post-install.sh \
        --acl public-read
  
## Creating a cluster configuration
We're all set to configure and create our cluster now.

We use the `pcluster configure` command's interactive wizard to define our
cluster. This command simply creates a configuration that is used by a
separate `create` step.

>   An example execution of the configuration step is illustrated below,
    of course you'll answer the questions in a way to suite your environment.

>   To date we have only tested using a Centos7 as the OS,
    Slurm as the workload manager and a single work queue

The wizard will prompt you with a number of questions. A typical set
of responses is reproduced for convenience here. Here, the configuration is
saved to the local file `config`: -

    $ pcluster configure -c ./config
    [...]
    AWS Region ID [eu-central-1]:
    [...] 
    EC2 Key Pair Name [nf-pcluster]:
    [...]
    Scheduler [slurm]:
    [...]
    Operating System [centos7]:
    [...]
    Minimum cluster size (instances) [0]:
    Maximum cluster size (instances) [10]: 2
    Master instance type [t2.micro]:
    Compute instance type [t2.micro]: m4.large
    Automate VPC creation? (y/n) [n]: y
    Network Configuration [Master in a public subnet and compute fleet in a private subnet]: 
    [...]
    Beginning VPC creation. Please do not leave the terminal until the creation is finalized
    [...]
    The stack has been created
    Configuration file written to ~/.parallelcluster/config

>   If you're creating a VPC configuration will take a few minutes.
    
With the configuration complete, edit the resultant configuration file
(saved locally in `./config`). We need to provide details of the post
installation script and, in our case, EFS for shared storage between the
cluster instances.

Add the following sections: -

    [efs default]
    shared_dir = efs
    encrypted = false
    performance_mode = generalPurpose
    
    [scaling default]
    scaledown_idletime = 10
    
And add this to the existing `[cluster default]` section,
replacing `<CLUSTER_BUCKET>`with the name of your chosen bucket: -

    scaling_settings = default
    efs_settings = default
    post_install = https://<CLUSTER_BUCKET>.s3.amazonaws.com/post-install.sh

## Create the cluster
With configuration edited, create the cluster: - 

    $ pcluster create -c ./config ${CLUSTER_NAME}
    Beginning cluster creation for cluster: nextflow
    [...]
    Creating stack named: parallelcluster-nextflow
    Status: parallelcluster-nextflow - CREATE_COMPLETE                              
    ClusterUser: centos
    MasterPrivateIP: 10.0.0.179

>   The cluster formation may take 10 to 15 minutes

## Connect to the cluster
Your cluster's created (well the _head node_ is). You can now use the CLI to
connect to the head node using the SSH key you created earlier and make sure
Nextflow is correctly installed by running the classic _hello_ workflow,
which will create compute instances to run the workflow processes: -

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
    on-demand and, based on our configuration, retired automatically when idle
    for 10 minutes) as well as the download of Nextflow dependent modules
    and conversion of the required process container image to Singularity. 

Congratulations! You can now run Slurm-based Nextflow workflows!

## Deleting the cluster
Once you're done, if you no longer need the cluster, delete it: -

    $ pcluster delete -c ./config ${CLUSTER_NAME}
    Deleting: nextflow
    [...]    
    Cluster deleted successfully.

---

[aws parallel cluster]: https://docs.aws.amazon.com/parallelcluster/index.html
[jq]: https://stedolan.github.io/jq/
[nextflow]: https://www.nextflow.io/
[parallelcluster policies]: https://docs.aws.amazon.com/parallelcluster/latest/ug/iam.html#parallelclusteruserpolicy-minimal-user
[singularity]: https://sylabs.io/docs/
[slurm]: https://slurm.schedmd.com
