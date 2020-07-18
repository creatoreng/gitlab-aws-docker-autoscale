# Gitlab AWS with Autoscaling Docker Machines
> Ansible playbook to configure AWS resources for Gitlab runners and autoscaling
docker build machines.

### Features
* Provisions a VPC, public and private subnets, and EC2 instances.
* Autoscaling build machines.
* Automatic management of Gitlab runners & runner registration.
* One or more machine instance type and configuration for flexible
(and cost-effective) build machines.
* Build machines spawned in private subnet with TLS encryption to runner.
* Store build artifacts or cache in S3.

### Disclaimer
This repository is a simplification of our production environment. We tested
that it stands up a hello-world build system. We hope that your application will
work by just modifying the configuration variables; but really, think of this
more as a template. Fork it, tweak it, break it, build it. We don't maintain it.

# Overview

### VPC topology
The VPC is configured with public and private subnets. The public subnet
allows servers with public IP address that can be accessed
directly from the internet.

The private subnet hosts services that do not have
public IP addresses and are not directly accessible from the internet. Services
in the private subnet are accessible only from within the subnet.

![VPC Topology](vpc-topology.svg)

We recommend configuring a third subnet for VPN, allowing more secure access
to the private subnet. The VPN subnet would be configured for client VPN and/or
site-to-site VPN clients to join the VPC. This template opts for easier
out-of-the-box capability; see comments where security can be improved by opting
to limit communication to within the private subnet only.

### Gitlab CI/CD
Gitlab is a version control, issue tracking and continuous integration /
continuous development tool for software developers.

This template is a generalization of our robotics CI/CD workflow. We manually
configured a project in Gitlab to mirror our code repository in
Github. Webhooks, also manually configured, send events to Gitlab when code
is pushed or on creation of a pull request. Gitlab reads a configuration file
from the repository, `.gitlab-ci.yml`,
to determine the build pipeline jobs to execute, and whether
or not the jobs should be run based on certain conditions such as branch or
commit message. Gitlab communicates a 'status check' back to Github to indicate
whether a branch or pull request passed build and tests, allowing Github
to protect a branch against merge/pull requests that fail build or tests.

A gitlab _runner_ is a persistent server that waits for a signal from Gitlab to
begin a build. The gitlab runner then spawns new, powerful on-demand compute
instances to run the build. When the build is complete, the expensive on-demand
build machines terminate, and the runner persists to wait for the next build.

Gitlab has very similar functionality to Github with respect to version control
and issue tracking. The key advantage of Gitlab is that it supports
enterprise-hosted custom autoscaling build servers, whereas Github's action
support is in its infancy. Github is moving fast with their action services in
Azure and when more feature complete it is an attractive alternative to Gitlab.

The Ansible scripts in this repository provision persistent servers in Amazon
EC2 and register them as runners with Gitlab. The runners themselves are
lightweight and run on inexpensive instances.

Gitlab autoscaling runners use _docker-machine_ to spawn new EC2 build machines
on-demand. These instances can be as powerful as you want, with CPU and
and memory resources that fit your needs. As more developers spawn builds
manually, through pull requests, or keywords in commit messages, the Gitlab
autoscale runner spawns new build machines in EC2. This allows multiple
developers to leverage cloud building without waiting in a queue. After a
build machine has been idle for a while, it automatically terminates.

#### Gitlab metrics and session servers
Gitlab runners start HTTP servers to report on build metrics and
to provide a real-time 'debug' (terminal) console to running machines. Gitlab
cloud assumes these servers are available on public IP addresses.

If your runners don't have public IP addresses, the debug and session servers
aren't accessible from the Gitlab project website.

The metrics server should work for any clients within the VPC. The session
server requires information about the job and a session key, which may require
a proxy relay from Gitlab cloud; this is left as future work.

# Install Provisioning Tools on your Machine

### Prerequesites
* Ubuntu 16.04 or later
* python3 installed as default interpreter, or you will need to modify the steps
below to invoke python3 for Ansible commands
* AWS access keys
* Gitlab project (hosted in Gitlab, or mirroring GitHub or BitBucket)
* Docker Hub login credentials

### Install the latest Ansible
```sh
sudo apt-get install software-properties-common
sudo apt-add-repository --yes --update ppa:ansible/ansible
sudo apt-get install ansible
```

### Install libraries needed by Ansible modules invoked in this repository
```sh
sudo apt-get install --upgrade -y virtualenv python3-pip python3-setuptools
pip3 install --upgrade boto3 boto botocore
```

### Install AWS-CLI, used by Ansible to configure some services
```sh
pushd /tmp
wget https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip
unzip awscli-exe-linux-x86_64.zip
sudo ./aws/install
rm -rf awscli-exe-linux-x86_64.zip ./aws
popd
```

# Configure and Provision

### Add secret group variables
Ansible requires access keys for AWS, Gitlab, and Docker. The easiest and least
secure storage of these keys is in the variable file `group_vars/all/secrets.yml`.
A better method is to store in shell environment variables. An even better
solution is to use git-crypt to encrypt secrets in your repository and grant
access to users as needed.

This template uses AWS, Gitlab and Docker credentials
stored in `group_vars/all/secrets.yml`.

### Generate ssh keypairs for runners
Generate a unique ssh-keypair for the EC2 runner instances.
```sh
mkdir files
ssh-keygen -f files/gitlab-build
```

### Customize your configuration
This is where you do you. Review and modify all variables in `group_vars/all`.

### Run the Ansible provisioning script
The Ansible scripts in this repository are idempotent, and may be safely
run while cloud services are running.
```sh
ansible-playbook playbook.yml
```

# Debuging

### gitlab runner SSH access
Find the public IP address of the runner EC2 instance from the AWS console.
Then, use the SSH keypair you previously generated to SSH into the machine:
```sh
ssh -i files/gitlab-build ubuntu@[instance IP]
```

### gitlab-runner log
On the gitlab-runner instance, tail the gitlab-runner log:
```sh
journalctl -u gitlab-runner.service -f
```

### gitlab-machine SSH access
The autoscale build machines spawned by the gitlab-runner automatically generate
SSH keypairs, which are not stored in this repository. To investigate docker
machines, first query the docker machine service on the autoscale gitlab runner:
```sh
sudo -i docker-machine ls
```
> Note the -i flag of the sudo command, which runs the command in the user
environment of the root user, which is the user gitlab-runner uses to run
docker-machine commands

Gitlab web console shows the build output of runners and machines, which is
usually sufficient for debugging a build failure. If for some reason you need to
access the build machine directly, first find the hostname of the docker
machine and then use the docker-machine SSH command on the runner to use the
automatically generated keypair to start an SSH session.

> Here be dragons, if you're doing this you're probably doing it wrong: these
are ephemeral build machines that are spawned and terminated on-the-fly. You
should be able to find everything you need from the Gitlab web interface or the
logs of the gitlab-runner that spawned the machine.

```sh
sudo -i docker-machine ls
sudo -i docker-machine ssh [machine identifier from previous command]
```

# Configure your Project Repository and Build
### Configure Gitlab
If you got this far, you have persistent runners in EC2 registered with
your Gitlab project and capable of spawning docker-machine workers.
Well done. It's up to you to configure and run your pipeline.

* See: [Autoscaling GitLab Runner on AWS EC2](https://docs.gitlab.com/runner/configuration/runner_autoscale_aws/)

### Deploy to S3 (optional)
The gitlab-machine instance is associated by instance profile to an IAM role
with permission to write to an S3 bucket. In your project source repository,
add the following job to your `.gitlab-ci.yml`:
```yaml
deploy:s3:
  stage: deploy
  image: registry.gitlab.com/gitlab-org/cloud-deploy/aws-base:latest
  variables:
    GIT_STRATEGY: none
  script:
    - export DEPLOY_TARBALL="$CI_PROJECT_NAME-$CI_COMMIT_REF_SLUG.tar.gz"
    - export ARTIFACT_DEST="s3://your-bucket-name/$CI_COMMIT_REF_SLUG/$DEPLOY_TARBALL"

    # create artifact tarball
    - tar -czf $DEPLOY_TARBALL .

    # configure AWS CLI
    - aws configure set region us-east-1 # TODO: configure for your region
    - aws configure set credential_source Ec2InstanceMetadata
    - aws configure list  # aws-cli now uses instance profile credentials

    # upload artifact tarball to s3
    - aws s3 cp --acl private $DEPLOY_TARBALL $ARTIFACT_DEST
  tags:
    - docker
```

### Use S3 for Gitlab build cache
Build instances have `put` permissions on the S3 bucket for artifacts. You can
also use this bucket for build cache, but you will need to add `get` permissions,
which you can easily add by modifying the instance IAM role.
Then, follow Gitlab documentation for caching in S3:
[Gitlab Distributed Runners Caching](https://docs.gitlab.com/runner/configuration/autoscale.html#distributed-runners-caching)

# Next Steps & Future Work
* Secure your VPC
    * Add a VPN subnet and VPN services.
    * Don't assign public IP addresses to EC2 instances in the private subnet.
    * Remove the security group rules for public ICMP & SSH access.
    * The S3 artifact bucket is accessible only within the VPC. Adjust to your needs.
* Audit & terminate orphan docker machines
    * Automatically audit docker-machine instances spawned by gitlab runners. After
changing configuration, or failure/restart of a runner, docker instances can be
orphaned leading to expensive and useless EC2 instances.
    * One such way to to this
is to query current runners and machines and compare to appropriately tagged
EC2 instances, and terminate instances not associated with a runner.
* Stream gitlab-runner and machine syslog & console messages to a log aggregator
so build feedback is visible beyond the Gitlab web interface.
* Store gitlab-runner and machine syslog and console messages to build artifacts
so compiler and build system output is stored with artifacts.
* docker-machine TLS certs are generated in a brute-force way: start an instance
as the gitlab-runner user and overwrite the certificate folder. It's nasty.
Instead, set up a private certificate authority, generate and sign keys for the
docker-machine instances, and pass the keys when spawning instances. I found an
Ansible script that does this, but I haven't the colspace to include.

# References
### Gitlab
* Gitlab: [Autoscaling GitLab Runner on AWS EC2](https://docs.gitlab.com/runner/configuration/runner_autoscale_aws/)
* Gitlab: [Installing GitLab on Amazon Web Services (AWS)](https://docs.gitlab.com/ee/install/aws/#creating-an-iam-ec2-instance-role-and-profile)
* jtyr: [Ansible playbook to install a docker gitlab runner](https://github.com/jtyr/ansible-docker_gitlab_runner)
* Hackernoon: [Configuring GitLab CI on AWS EC2 Using Docker](https://hackernoon.com/configuring-gitlab-ci-on-aws-ec2-using-docker-7c359d513a46)
* Lothat Shulz: [GitHub Action Self Hosted Runners on AWS (incl. Spot instances)](https://www.lotharschulz.info/2019/12/09/github-action-self-hosted-runners-on-aws-incl-spot-instances/)
* riemers: [Ansible role to install gitlab runner](https://github.com/riemers/ansible-gitlab-runner)
* DataBiosphere: [Gitlab CI Autoscaling Setup](https://github.com/DataBiosphere/toil/wiki/Gitlab-CI-Autoscaling-Setup)
* GhostLyrics: [http://ghostlyrics.net/building-and-deploying-a-c-library-with-gitlab.html](http://ghostlyrics.net/building-and-deploying-a-c-library-with-gitlab.html)
### AWS
* devops-recipes: [Provision Amazon Web Services VPC using Ansible](https://github.com/devops-recipes/prov_aws_vpc_ansible	)
* AWS: [Best practices for managing AWS access keys](https://docs.aws.amazon.com/general/latest/gr/aws-access-keys-best-practices.html)
* [Introducing AWS Client VPN to Securely Access AWS and On-Premises Resources
](https://aws.amazon.com/blogs/networking-and-content-delivery/introducing-aws-client-vpn-to-securely-access-aws-and-on-premises-resources/)
* [VPC with public and private subnets and AWS Site-to-Site VPN access](https://docs.aws.amazon.com/vpc/latest/userguide/VPC_Scenario3.html)
* [Centralized DNS management of hybrid cloud with Amazon Route 53 and AWS Transit Gateway](https://aws.amazon.com/blogs/networking-and-content-delivery/centralized-dns-management-of-hybrid-cloud-with-amazon-route-53-and-aws-transit-gateway/)
