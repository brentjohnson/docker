# Synopsis
The project is describing approach which was used in implementation of **on demand environment provisioning** using **container technologies** - [docker](https://www.docker.com/).

## Assumptions

It is assumed that there are pre-installed images either on AWS nodes or with docker-registry with below components.

      * JENKINS (CI)
      * STUB (MULE)
      * WEBSPHERE EXTREME SCALE
      * DATABSE 
      * ENDECA (search solution)
      * WEBSPHERE COMMERCE SERVER
      * IBM HTTP SERVER
      * CMS 
      * BATCH JOBS
      * CONTROL M (Jobs Scheduling)
      * SPLUNK (log monitoring)

Additionally there are other components which are required to setup end to end flow and listed below.

      * APACHE PROXY SERVER 
      * DNS SERVER (xip.io)
      * DOCKER INSTALLED ON NODES
      * RANCHER SERVER/AGENTS ON EACH NODES (monitoring of containers)
      * DOCKER SWARM (container clustering)

## Approach

In case of end-to-end scenario, let's start with JIRA tool through which user can request for an environment for his feature stories/fix validation.
The JIRA request would container the information (e.g. branch to build, email ids for notifications, PT name etc...) which would be extracted and used for **ENVOD (environment on demand)**.

A shell script named invoke.sh is being used to handle below operations.

* Validate if JIRA request is as per filter meeting criteria to create ENVOD.
* Validate if branch specified with JIRA request does exist.
* Manage more than one environment and allocation of tcp ports for containers for each nodes.
* Creating shared mounts/folder structure/properties file across components which are related and need the same.
* Tokenization of few hostnames/ports which must differ with each ENVOD requests. It may include DB HOST, DB PORT, JENKINS HOST etc.
* It would generate relevant URLS which would be send to user requesting ENVOD.
* In case of failure, is should stop all the started container linked with Jira request.

Post testing the scenarios of feature story, User would request with another JIRA to tead down the environment mentioning previous JIRA request number.

## Scripts and commands

### SWARM

**Starting Swarm Cluster on any one node**

      docker -H tcp://$(hostname -i):2375 run --rm swarm create

output:
	`5694e00d4e6ec36ac2997d954db6ba41`
      

**Starting Swarm manager on any one node**

      docker -H tcp://$(hostname -i):2375 run -d -p 2376:2375 swarm manage token://5694e00d4e6ec36ac2997d954db6ba41



**Join swarm cluster on each node**

      docker -H tcp://$(hostname -i):2375 run -d swarm join --addr=$(hostname -i):2375 token://5694e00d4e6ec36ac2997d954db6ba41



**Swarm Nodes Info** 

      docker -H tcp://<SWARM_MANAGER_HOST>:2376 info

### RANCHER

Details to be provided...

### Using Weave, Swarm and Docker to manage container network 	

Details to be provided...

### Get GUI apps from docker running using SSH-TUNNELING 

Follow the [link](https://github.com/aku163/docker/blob/master/GUI.md)
		

