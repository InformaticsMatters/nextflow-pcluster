# Nextflow AWS ParallelCluster Configuration
Material for the formation and use of an AWS (slurm-based) compute cluster.

## Overview
These materials create a compute cluster on AWS running the a [Slurm] workload
manager and sets up [Nextflow] to execute workflows.

The cluster is created using [AWS Parallel Cluster], a tool from AWS that
automates the creation of a number of types of cluster on AWS.

Standard usage of these materials results in creating:

1.  A VPC with public and private subnets (a pre-existing VPC can be used instead)
2.  A single master node in the public subnet
3.  An autoscaling group of worker nodes in the private subnet
4.  A shared EFS volume mounted at `/efs` on all master and worker nodes
5.  Installs [Singularity] on all nodes when they are started
6.  Installs and configures Nextflow on the master node

The installation process is highly configurable and can create variations
of the standard usage. Parallel cluster uses a config file
(`~/.parallelcluster/config` by default) where these
configuration changes can be made.

>   Consult the Parallel Cluster docs for full details.

After you've satisfied the instructions in the **Getting Started** section
below you typically: -

1.  Configure a cluster
2.  Create a cluster
3.  Connect (SSH) to the cluster to the head node to run your Nextflow workflow
4.  Repeat step 3 until done

>   To date we have only tested using a Centos7 as the OS,
    Slurm as the workload manager and a single work queue

## Getting started
Start from a suitable (ideally Python 3.8 or better) virtual environment: -

    $ conda activate nextflow-pcluster
    $ pip install -r requirements.txt --upgrade

### Install jq
[jq] is a convenient JSON query utility, it's useful to install it and some
commands illustrated here rely on it.

### AWS environment variables
Set you user credentials and default region for your intended cluster: -

    $ export AWS_ACCESS_KEY_ID=????
    $ export AWS_SECRET_ACCESS_KEY=??????
    $ export AWS_DEFAULT_REGION=eu-central-1

### Create an AWS user
This user will be the cluster user with policies attached later.
Create a user and collect their name and ID.

    $ CLUSTER_USER=nf-pcluster
    $ CLUSTER_USER_ID=427674407067

### Key-pairs
You will need to install a keypair on the account.
Easily done with the `aws` CLI and `jq` to conveniently extract the
private key block: -

    $ KEYPAIR_NAME=nf-pcluster
    $ aws ec2 create-key-pair --key-name ${KEYPAIR_NAME} \
        | jq -r .KeyMaterial > ~/.ssh/${KEYPAIR_NAME} && \
        chmod 0600 ~/.ssh/${KEYPAIR_NAME} 

### IAM Policies
You will need an IAM user with programmatic access.
The user's policies must include the the those defined in the `iam`
directory, as defined in the AWS [ParallelCluster Policies] documentation.

The following fields in the files need to be replaced with suitable values: -

-   `<AWS ACCOUNT ID>`
-   `<CLUSTERNAME>`
-   `<REGION>`

Given a region, user account ID (of a user with programmatic access you'll
use to create the cluster) and indented cluster name you can render the
policy files (into the project root) using the following command: -

    $ CLUSTER_NAME=nextflow
    $ ./render-policies.sh ${AWS_DEFAULT_REGION} ${CLUSTER_USER_ID} ${CLUSTER_NAME}

You can install each of the policies using the AWS CLI,
typically like this: -
    
    $ aws iam create-policy \
        --policy-name NextflowClusterInstancePolicy \
        --policy-document file://nf-instance-policy.json \
        | jq -r .Policy.Arn \
        | cut -d: -f5
    427674407067
    
    $ aws iam create-policy \
        --policy-name NextflowClusterUserPolicy \
        --policy-document file://nf-user-policy.json

    $ aws iam create-policy \
        --policy-name NextflowClusterOperatorPolicy \
        --policy-document file://nf-operator-policy.json

Keep a record of the initial ID that is generated, we'll use these next.
        
And, again using the AWS CLI, attach the policies to your chosen AWS user,
typically like this...

    $ POLICY_USER_ID=427674407067
    $ aws iam attach-user-policy \
        --policy-arn arn:aws:iam::${POLICY_USER_ID}:policy/NextflowClusterInstancePolicy \
        --user-name ${CLUSTER_USER}
    $ aws iam attach-user-policy \
        --policy-arn arn:aws:iam::${POLICY_USER_ID}:policy/NextflowClusterUserPolicy \
        --user-name ${CLUSTER_USER}
    $ aws iam attach-user-policy \
        --policy-arn arn:aws:iam::${POLICY_USER_ID}:policy/NextflowClusterOperatorPolicy \
        --user-name ${CLUSTER_USER}

### Deploy cluster installation scripts
Part of cluster formation permits the execution of installation scripts
that are pulled from AWS S3 as cluster compute instances are formed. An
example _post-installation_ script that prepares directories, singularity and
a default configuration file for Nextflow can be found in this repository's
`installation-scripts` directory.

Use this script unless you have one of your own.

Upload `installation-scripts/post-install.sh` to an AWS S3 bucket that the
chosen cluster user has access to, e.g.: -

    $ CLUSTER_BUCKET=nf-pcluster
    $ aws s3 cp installation-scripts/post-install.sh \
        s3:///${CLUSTER_BUCKET}/post-install.sh
  
## Configuring the cluster
Here we use the `pcluster` command's interactive wizard to define our cluster.
This simply creates a configuration that is used by a separate `create` step.
Ans example execution of the configuration step is illustrated below,
of course you'd answer the questions to suite your environment: -

    $ pcluster configure

This wizard will prompt you with a number of questions. A typical set
of responses is reproduced for convenience here. Obviously you need to
provide your own responses.

    [...]
    AWS Region ID [eu-central-1]:
    [...] 
    EC2 Key Pair Name [nf-pcluster]:
    [...]
    Scheduler [slurm]:
    [...]
    Operating System [centos7]:
    [...]
    Automate VPC creation? (y/n) [n]: y
    [...]
    The stack has been created
    Configuration file written to ~/.parallelcluster/config
    
With the configuration complete, edit it to provide details of the post
installation script and, in this case details of the EFS volume to use.
Essentially you'll add the following to the configuration
(at `~/.parallelcluster/config`).

Add the following sections: -

    [efs default]
    shared_dir = efs
    encrypted = false
    performance_mode = generalPurpose
    
    [scaling default]
    scaledown_idletime = 10
    
And add this t the end of the existing `[cluster default]` section,
replacing `<CLUSTER_BUCKET>`with the name of your chosen bucket: -

    scaling_settings = default
    efs_settings = default
    post_install = https://<CLUSTER_BUCKET>.s3.amazonaws.com/post-install.sh
    post_install_args = 'singularity'

## Create the cluster
With configuration edited, create the cluster: - 

>   The cluster formation may take 10 to 15 minutes

    $ pcluster create ${CLUSTER_NAME}
    Beginning cluster creation for cluster: nextflow
    [...]
    Creating stack named: parallelcluster-nextflow
    Status: parallelcluster-nextflow - CREATE_COMPLETE                              
    ClusterUser: centos
    MasterPrivateIP: 10.0.0.179

## Connect to the cluster
Use the CLI to connect to the head node and make sure Nextflow is installed
by running the classic _hello_ workflow: -

    $ pcluster ssh ${CLUSTER_NAME} -i ~/.ssh/${KEYPAIR_NAME}
    $ nextflow run hello
    N E X T F L O W  ~  version 20.07.1
    [...]
    [4e/8c5c13] process > sayHello (3) [100%] 4 of 4 ✔
    Ciao world!

    Bonjour world!

    Hola world!

    Hello world!

## Deleting the cluster
Once you're done, if you no longer need the cluster, delete it: -

    $ pcluster delete ${CLUSTER_NAME}
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
