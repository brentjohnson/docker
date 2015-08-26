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
