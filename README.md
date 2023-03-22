# Nextflow AWS ParallelCluster Configuration
Material for the formation and use of an v3 ParallelCluster (slurm-based) compute
environment.

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

    $ python -m venv venv
 
    $ source venv/bin/activate
    (venv) $ pip install --upgrade pip
    (venv) $ pip install -r requirements.txt --upgrade
    
    $ aws --version
    aws-cli/2.9.1 Python/3.11.0 Darwin/21.6.0 source/x86_64 prompt/off

    $ jq --version
    jq-1.5

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

    $ CLUSTER_ACCOUNT_ID=000000000000

We now create **Policies** in AWS and then attach them to the role.

>   The [ParallelCluster policies] for v3 are numerous and complex
    but we've extracted what we found to be essential and placed them
    in the project `iam` directory.

>   Copies of the policies exist in this repository along with a shell-script
    to rapidly adapt them for the user and cluster you're going to create.

>   The `EVERYTHING-policy` is a combination of all the other policy files.
    Which might be useful if you reach an IAM policy limit.

Given a region (like `eu-central-1`), user account ID, cluster name and a role name
you can render the repository's copy of the reference policy files 
using the following command: -

    $ ./render-policies.sh \
        ${AWS_DEFAULT_REGION} \
        ${CLUSTER_ACCOUNT_ID}

Now install each of the policies using the AWS CLI. The policy names
you choose must be unique for your account: -
    
    $ aws iam create-policy \
        --policy-name NextflowClusterInstancePolicy \
        --policy-document file://v3-instance-policy.json
    
    $ aws iam create-policy \
        --policy-name NextflowClusterUserPolicy \
        --policy-document file://v3-user-policy.json

    $ aws iam create-policy \
        --policy-name NextflowClusterOperatorPolicy \
        --policy-document file://v3-operator-policy.json

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
cluster.

>   Here we're using a pre-created EFS filesystem
    (see Amazon's [Creating EFS] documentation)
    rather than relying in ParallelCluster to do this for us. By doing this
    we can preserve workflow data between cluster instantiations.

Here's a typical configuration file we end up with (with redacted data).
Rather than use `pcluster configure` you can simply craft your own file.
In the following we are using a pre-assigned EFS, one created using the AWS
console: -

```yaml
Region: eu-central-1
Image:
  Os: alinux2
Tags:
  - Key: Dept
    Value: 'XYZ'
SharedStorage:
- Name: cluster-one
  StorageType: Efs
  MountDir: efs
  EfsSettings:
    FileSystemId: fs-00000000000000
HeadNode:
  InstanceType: t3a.large
  Networking:
    SubnetId: subnet-00000000000000000
    ElasticIp: false
  Ssh:
    KeyName: im-pc3
  CustomActions:
    OnNodeConfigured:
      Script: https://im-aws-parallel-cluster.s3.amazonaws.com/amazon-post-install.sh
Scheduling:
  Scheduler: slurm
  SlurmSettings:
    ScaledownIdletime: 15
  SlurmQueues:
    - Name: compute
      CapacityType: SPOT
      ComputeResources:
        - Name: cluster-one
          InstanceType: c6a.4xlarge
          MinCount: 1
          MaxCount: 25
          Efa:
            Enabled: false
      CustomActions:
        OnNodeConfigured:
          Script: https://im-aws-parallel-cluster.s3.amazonaws.com/amazon-post-install.sh
      Networking:
        SubnetIds:
        - subnet-00000000000000000
```

## Create the cluster
With configuration edited you can create the cluster: - 

    $ CLUSTER_NAME=cluster-one
    $ pcluster create-cluster -c ./config.yaml -n ${CLUSTER_NAME}

And list clusters with: -

    $ pcluster list-clusters

>   Allow 10 to 15 minutes for cluster formation to finish

## Mounting a pre-configured EFS on the bastion
Assuming you've created a suitable EFS (see Amazon's [Creating EFS] documentation)
you can mount it on the bastion with the following commands,
replacing `???` with values relevant to you: -

    $ sudo yum install -y amazon-efs-utils
    $ sudo yum -y install nfs-utils
    $ sudo service nfs start

    $ sudo mkdir /efs
    $ sudo mount -t nfs \
        -o nfsvers=4.1,rsize=1048576,wsize=1048576,hard,timeo=600,retrans=2,noresvport \
        fs-????????????.efs.????.amazonaws.com:/ \
        /efs

>   Refer to the [EFS] documentation for further details.

## Connect to the cluster
Your cluster's created (well the _head node_ is). You can now use the CLI to
connect to the head node using the SSH key you created earlier. Here we just
make sure Nextflow is correctly installed by running the classic _hello_
workflow, which will create compute instances to run the workflow processes.

Assuming you've put your private key file in `~/.ssh/id_rsa` you can connect
with: -

    $ pcluster ssh -n ${CLUSTER_NAME}
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

    $ pcluster delete-cluster -n ${CLUSTER_NAME}

>   Be careful with this command - it does not ask "Are you sure?".

>   We've noticed that tearing-down the cluster may not always be successful
    (observed October 2020) and manual intervention in the AWS CloudFormation
    console was required. It is always worth checking the AWS CloudFormation
    console to make sure the stack responsible for the cluster has been
    deleted.

## A custom cluster image
ParallelCLuster's [ImageBuilder] is a tool to create custom images (AMIs) that you
can use as the basis of your cluster's head and compute instances. This is especially
useful if you find you're installing a lot of custom packages, which can slow down
the formation of new compute nodes. By creating a custom image with all your
application packages you can reduce the time taken for new nodes to become available.

To do this you simply put your package configuration into a shell-script and store this
in an Amazon S3 bucket. You then refer to this script in the ImageBuilder YAML-based
configuration file.

We've put our ParallelCluster v3 configuration file, which installs nextflow and
singularity) into our public S3 bucket. We can then create a simple image builder
file that refers to this script to create a custom image.

Ours looks like this...

```yaml
---
# A ParallelCluster v3 ImageBuilder configuration.
# Used to compile custom images.
#
# This file is a TEMPLATE file, replace the `000[...]000` IDs with
# values suitable for your environment.
#
# See https://docs.aws.amazon.com/parallelcluster/latest/ug/building-custom-ami-v3.html
Build:
  InstanceType: c6a.4xlarge
  # A Parent Image to bass this one one.
  # Here we're using a suitable Amazon Linux.
  # You can use 'pcluster list-official-images' to find some.
  ParentImage: ami-00000000000000000
  # If you don't have a 'default VPC'
  # you will need to provide a Subnet (and a SecurityGroup)
  SubnetId: subnet-00000000000000000
  SecurityGroupIds:
  - sg-00000000000000000
  # Components to add to the image.
  # Here we're running our custom script (on S3)
  # that installs nextflow and apptainer (singularity)
  Components:
  - Type: script
    Value: s3://im-aws-parallel-cluster/imagebuilder-amazon.sh
  # Allow the builder to access S3
  Iam:
    AdditionalIamPolicies:
    - Policy: arn:aws:iam::aws:policy/AmazonS3ReadOnlyAccess
  # Other stuff...
  UpdateOsPackages:
    Enabled: true
``` 

>   You can find a copy of the ImageBuilder YAML file in the `imagebuilder` directory
    of this repository.
    
Then, if the above configuration is placed in the file `imagebuilder-nextflow.yaml`
we can run the image builder and create a custom image: -

    $ pcluster build-image \
        --image-configuration imagebuilder-nextflow.yaml \
        --image-id nextflow \
        --region eu-central-1

Building an Image building can take a substantial length of time (an hour or so)
but you can track image build status using the following command: -

    $ pcluster describe-image --image-id nextflow --region eu-central-1

When the `imageBuildStatus` from the above command is `BUILD_COMPLETE` you should
also find the image AMI under `ec2AmiInfo -> amiId`.

You can now use this AMI in your cluster configuration and remove the
corresponding `CustomActions`, which are no longer required, by placing the AMI
in the `Image` block of your cluster configuration: -

```yaml
Image:
  Os: alinux2
  CustomAmi: ami-00000000000000000
```

Now, clusters built using this configuration should become available a little more
quickly.

---

[administratoraccess]: https://docs.aws.amazon.com/IAM/latest/UserGuide/access_policies_managed-vs-inline.html#aws-managed-policies
[aws parallel cluster]: https://docs.aws.amazon.com/parallelcluster/index.html
[creating efs]: https://docs.aws.amazon.com/efs/latest/ug/gs-step-two-create-efs-resources.html
[documentation for the configuration file]: https://docs.aws.amazon.com/parallelcluster/latest/ug/cluster-configuration-file-v3.html
[efs]: https://docs.aws.amazon.com/efs/latest/ug/mounting-fs.html
[fragmentation workflow]: https://github.com/InformaticsMatters/fragmentor
[image builder]: https://docs.aws.amazon.com/parallelcluster/latest/ug/building-custom-ami-v3.html
[jq]: https://stedolan.github.io/jq/
[nextflow]: https://www.nextflow.io/
[parallelcluster policies]: https://docs.aws.amazon.com/parallelcluster/latest/ug/iam-roles-in-parallelcluster-v3.html
[singularity]: https://sylabs.io/docs/
[slurm]: https://slurm.schedmd.com
