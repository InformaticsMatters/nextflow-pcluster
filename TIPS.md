# Nextflow AWS Parallel Cluster Tips

AWS Parallel Cluster has a wide range of configuration options. 
Consult the [pcluster docs] for full details.

## pcluster tips

These operations are executed from the bastion machine as the `centos` user.
you first need to activate the pcluster virtual environment using (replace `<venv-name>`
with the name for the virtual environment that was created:

    . ~/venvs/<venv-name>/bin/activate

In the following replace the <cluster-name> with name of your cluster.

### Shutting down and starting the workers

This shuts down the worker nodes. This is generally not necessary as they shutdown
after a period of in activity, but sometimes it might be needed. 

    pcluster stop <cluster-name>
    
This starts the worker environment (note: nodes are not started until they are needed):

    pcluster start <cluster-name>

### Resizing the compute cluster

1. shutown the workers (see above)
2. edit the pcluster config file and adjust the `instance_type` and/or `max_count`
properties in the `compute_resource` section
3. run `pcluster update <cluster-name>` to update the cluster.
4. start the workers (see above)

See the note below in the Nextflow section on the queue size if your compute cluster has 
more than 100 cores.

## Nextflow tips

Nextflow has a huge number of options handling nearly all needs. 
See the [Nextflow docs] for full details.

Some key points are listed here, but consult the docs for more info.

### Limiting growth of the work dir

By default Nextflow is configured to use `/efs/work` as its work directory
(where intermediate results are located). You will need to delete the contents
of this directory once your workflows are complete to avoid it continually
increasing in size (and incur ever increasing charges!). The location of the
"work dir" can be changed by editing the `/home/centos/.nextflow/config` file
on the master node or creating a local config file named `nextflow.config` in
your current directory.

### Nextflow queue size

By default Nextflow is configured with queue size of 100. If your cluster can
cope with more that 100 concurrent jobs (typically this means you have more
than 100 CPU cores) you will want to increase this value. It is defined in the
Nextflow config file as described above.

### Handling failures in a workflow

Sometimes as step in a workflow can fail for unexplained reasons. By default this 
halts the workflow. To make it more robust consider the `errorStrategy 'retry'` and
`maxRetries 3` options in your nextflow processes.

If a workflow does fail it can usually be resumed from where it left off using the `-resume` 
option. e.g.

    nextflow run main.nf --resume
    
### Monitoring

Nextflow provides some very nice metrics on workflow executions. Use the `-with-trace`, 
`-with-report` and `-with-timeline` options.

### Nextflow scratch directory

To avoid excessive network filesystem access Nextflow can be told to perform its work
(where intermediate files are stored) in directory that is local to the worker node.
To do this ass the `scratch true` directive to your Nextflow process definition in your 
workflow file (the `*.nf` file). Note that doing this limits the possibility of using the `-retry` option.

## Troubleshooting

If your workflows are not starting then the Slurm resource manage may not be running 
correctly or the worker instances may not be starting.

To check the status of Slurm run this command on the master:

    systemctl status slurmctld

To check on status of the slurm nodes and the job queue run these commands from the 
master node: `sinfo`, `squeue`.

Additional information from Nextflow is available from the log file which is named `.nextflow.log`.

Worker nodes may not start as expected. This has been seen when using spot instances.
Check that you are able to start spot requests through the AWS console.
Stopping and starting the worker pool (see above for details) may resolve this.

---

[pcluster docs]: https://docs.aws.amazon.com/parallelcluster/latest/ug/what-is-aws-parallelcluster.html
[Nextflow docs]: https://www.nextflow.io/docs/latest/index.html