# Nextflow AWS ParallelCluster Configuration
Material for the formation and use of an AWS (slurm-based) compute cluster.

You'll need: -

-   Python
-   [jq]
-   An AWS user with an [AdministratorAccess] managed policy

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
5.  Delete the cluster to avoid AWS charges 

## Getting started
Start from a suitable virtual environment
(ideally Python 3.8 host or better): -

    $ python -m venv ~/.venv/nextflow-pcluster
 
    $ source ~/.venv/nextflow-pcluster/bin/activate
    (nextflow-pcluster) $ pip install --upgrade pip
    (nextflow-pcluster) $ pip install -r requirements.txt --upgrade
    
    $ aws --version
    aws-cli/1.18.170 Python/3.7.6 Darwin/19.6.0 botocore/1.19.10

    $ jq --version
    jq-1.6

### EC2 key-pair
If you have an existing SSH keypair on the AWS account you can skip this step.

If you do not have a pre-existing keypair, as an AWS user with
*AdministratorAccess*, set the user credentials and default region environment
variables for your intended cluster: -

    $ export AWS_ACCESS_KEY_ID=????
    $ export AWS_SECRET_ACCESS_KEY=??????
    $ export AWS_DEFAULT_REGION=eu-central-1

...and create a keypair on the account, which can be easily done
with the `aws` CLI and `jq` to conveniently extract and write the
private key block: -

    $ KEYPAIR_NAME=nextflow-pcluster
    $ aws ec2 create-key-pair --key-name ${KEYPAIR_NAME} \
        | jq -r .KeyMaterial > ~/.ssh/${KEYPAIR_NAME} && \
        chmod 0600 ~/.ssh/${KEYPAIR_NAME} 

### IAM Role and Policies
Using the AWS console (or CLI) create a **Role** for use with the cluster.
This will typically be an **EC2** role. Later we'll be attaching policies to
this role. For now you do not need to add any additional policies.
Just continue to **Create role** and give it a name (like `nextflow-pcluster`).

...and set some convenient variables, that we'll use later.
Namely the created user name and your AWS account ID: -

    $ CLUSTER_ROLE_NAME=nextflow-pcluster
    $ CLUSTER_ACCOUNT_ID=000000000000

We now create **Policies** in AWS and then attach them to the role.

>   The role's policies must include those defined in the `iam`
    directory, as defined in the AWS [ParallelCluster Policies] documentation.

>   Copies of the policies exist in this repository along with a shell-script
    to rapidly adapt them for the user and cluster you're going to create.

Given a region, user account ID, cluster name and a role name
you can render the repository's copy of the reference policy files 
using the following command: -

    $ CLUSTER_NAME=nextflow
    $ ./render-policies.sh \
        ${AWS_DEFAULT_REGION} \
        ${CLUSTER_ACCOUNT_ID} \
        ${CLUSTER_NAME} \
        ${CLUSTER_ROLE_NAME}

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

Now, again using the AWS CLI, attach the policies to your chosen AWS role: -

    $ aws iam attach-role-policy \
        --policy-arn arn:aws:iam::${CLUSTER_ACCOUNT_ID}:policy/NextflowClusterInstancePolicy \
        --role-name ${CLUSTER_ROLE_NAME}
        
    $ aws iam attach-role-policy \
        --policy-arn arn:aws:iam::${CLUSTER_ACCOUNT_ID}:policy/NextflowClusterUserPolicy \
        --role-name ${CLUSTER_ROLE_NAME}
        
    $ aws iam attach-role-policy \
        --policy-arn arn:aws:iam::${CLUSTER_ACCOUNT_ID}:policy/NextflowClusterOperatorPolicy \
        --role-name ${CLUSTER_ROLE_NAME}

### Upload installation scripts
Part of cluster formation permits the execution of installation scripts
that are pulled from AWS S3 as cluster compute instances are created. Example
_post-installation_ scripts that prepare directories, singularity and
a default configuration file for Nextflow can be found in this repository's
`installation-scripts` directory.

Note that you might want to further customise the file that gets created at
`/home/centos/.nextflow/config`.

Use one of these scripts unless you have one of your own.

>   At the time of writing there are post-installation scripts for amazon
    (Amazon Linux 2) and centos (CentOS 7).

>   For this example we're going to create a cluster based on the
    **Amazon Linux 2** machine image.

Create an S3 bucket and upload the post-installation script for your
chosen image to it (the bucket's called `nf-pcluster` in this example).
Here we ensure that the file's `acl` (Access Control List)
permits `public-read`: -

    $ CLUSTER_BUCKET=nextflow-pcluster
    $ CLUSTER_OS=amazon
    $ aws s3 cp installation-scripts/${CLUSTER_OS}-post-install.sh \
        s3://${CLUSTER_BUCKET}/${CLUSTER_OS}-post-install.sh \
        --acl public-read

## Creating a cluster configuration user
From here we will be running the `pcluster` command-line utility
to configure and manage the actual cluster. All we've done so far is
prepare the ground for the formation of the cluster.

If you have an AWS IAM User with *AdministratorAccess* and you are happy
to use that user then there's nothing more to do except move on to the next
section - **Creating a cluster configuration**.

>   You will still need a user with *AdministratorAccess* in this step.

But, if you do not want to use a user with *AdministratorAccess* to
create the cluster then you need to create a new user and attach suitable
policies.

Firstly, in the AWS console, create a new user with **Programmatic access**.
Something like `nextflow-pcluster` (or select an existing user)
 
>   There is no need to add any policies to the user but you must record
    the newly assigned **Access key ID** and **Secret access key** before
    closing the final window. If you forget you can always create another
    access key later.

Now, attach the previously rendered **NextflowClusterUserPolicy** policy
to our user: -

    $ CLUSTER_USER_NAME=nextflow-pcluster

    $ aws iam attach-user-policy \
        --policy-arn arn:aws:iam::${CLUSTER_ACCOUNT_ID}:policy/NextflowClusterUserPolicy \
        --user-name ${CLUSTER_USER_NAME}

The user's credentials rather than an admin user's credentials
can now be used in the next step to configure the cluster.

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

Firstly, set the AWS credentials for your chosen user. These will be the
credentials for either a user with *AdministratorAccess* privileges or the
user you created in the previous section. Set the appropriate credentials: -

    $ export AWS_ACCESS_KEY_ID=????
    $ export AWS_SECRET_ACCESS_KEY=??????
    $ export AWS_DEFAULT_REGION=eu-central-1

>   From this point you're running the `pcluster` commands as either a new user
    with limited policies or as a user with *AdministratorAccess*.
 
Remove any existing configuration file if it exists...

    $ rm config
    
Then run the configuration wizard: -

    $ pcluster configure -c ./config
    [...]
    AWS Region ID [eu-central-1]:
    [...] 
    EC2 Key Pair Name [nextflow-pcluster]:
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
    [...]
    Network Configuration [Master in a public subnet and compute fleet in a private subnet]: 
    [...]
    Beginning VPC creation. Please do not leave the terminal until the creation is finalized
    [...]
    The stack has been created
    Configuration file written to [...]/config

>   If you're creating a VPC the configuration may take a few minutes.
    
Once complete, edit the resultant configuration file.

You can refer to the aws [documentation for the configuration file]. 

We need to provide details of the post-installation script, role and,
in our case, an EFS volume for shared storage between the cluster instances
and a timer to shutdown idle instances.

Add the following new sections to the end of the `config` file: -

```ini
[efs default]
shared_dir = efs
encrypted = false
performance_mode = generalPurpose

[scaling default]
scaledown_idletime = 10
```
    
And add the following to the existing `[cluster default]` section,
replacing `<CLUSTER_BUCKET>`, `<CLUSTER_OS>` and `<CLUSTER_ROLE_NAME>`
with the values you used: -

```ini
scaling_settings = default
efs_settings = default
post_install = https://<CLUSTER_BUCKET>.s3.amazonaws.com/<CLUSTER_OS>-post-install.sh
ec2_iam_role = <CLUSTER_ROLE_NAME>
```

If you want to use **Spot** instances instead of **OnDemand** (the default)
then add the following to the `queue compute` section: -

```ini
compute_type = spot
```

...and then consider whether you need to add `spot_price` setting to the
`cluster default` section, which sets the maximum Spot price for the
ComputeFleet. If you do not specify a value, you are charged the Spot price,
capped at the On-Demand price.

## Create the cluster
With configuration edited you can create the cluster: - 

    $ pcluster create -c ./config ${CLUSTER_NAME}
    Beginning cluster creation for cluster: nextflow
    [...]
    Creating stack named: parallelcluster-nextflow
    Status: parallelcluster-nextflow - CREATE_COMPLETE                              
    ClusterUser: ec2-user
    MasterPrivateIP: 10.0.0.179

>   Allow 10 to 15 minutes for cluster formation to finish

## Connect to the cluster
Your cluster's created (well the _head node_ is). You can now use the CLI to
connect to the head node using the SSH key you created earlier. Here we just
make sure Nextflow is correctly installed by running the classic _hello_
workflow, which will create compute instances to run the workflow processes: -

    $ pcluster ssh ${CLUSTER_NAME} -i ~/.ssh/${KEYPAIR_NAME}
    [...]
    
    centos@ip-0-0-0-0 ~]$ nextflow run hello
    [...]
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
    and conversion of any required Docker container images to Singularity. 

Congratulations! You can now run Slurm-based Nextflow workflows!

>   To execute our [fragmentation workflow] you may need the private copy of
    the keypair used to create the cluster in the Master node's
    `~/.ssh/${KEYPAIR_NAME}` directory. This will allow you to create the
    database server (a separate EC2 instance) using the keypair you used to
    create the cluster, remembering to set the Master node's file permissions
    correctly (i.e. `chmod 0600 ~/.ssh/${KEYPAIR_NAME}`)

>   An alternative (non-config) SSH connection mechanism, armed with the
    Master's address and private key-pair, is
    `ssh -i ~/.ssh/nextflow-pcluster <USER>@<MASTER_ADDR>` where `<USER>` is
    is `ec2-user` for an Amazon Linux 2 master and `centos` for Centos.

## Deleting the cluster
Once you're done, if you no longer need the cluster, delete it: -

    $ pcluster delete -c ./config ${CLUSTER_NAME}
    Deleting: nextflow
    [...]    
    Cluster deleted successfully.

>   Be careful with this command - it does not ask "Are you sure?".

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

[administratoraccess]: https://docs.aws.amazon.com/IAM/latest/UserGuide/access_policies_managed-vs-inline.html#aws-managed-policies
[aws parallel cluster]: https://docs.aws.amazon.com/parallelcluster/index.html
[documentation for the configuration file]: https://docs.aws.amazon.com/parallelcluster/latest/ug/configuration.html
[fragmentation workflow]: https://github.com/InformaticsMatters/fragmentor
[jq]: https://stedolan.github.io/jq/
[nextflow]: https://www.nextflow.io/
[parallelcluster policies]: https://docs.aws.amazon.com/parallelcluster/latest/ug/iam.html#parallelclusteruserpolicy-minimal-user
[singularity]: https://sylabs.io/docs/
[slurm]: https://slurm.schedmd.com
