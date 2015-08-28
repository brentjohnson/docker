#!/bin/bash

#Setting Umask values
umask +rwx

#Get current date, time and epoch seconds
D1=$(date +%d/%b/%Y)
T1=$(date +%H:%M:%S)
E1=`date +%s`

#Function: to get build time
getTime(){
	Dcurrent=$(date +%d/%b/%Y)
	Tcurrent=$(date +%H:%M:%S)
	Ecurrent=`date +%s`
	let DIFF=$Ecurrent-$E1

	hours=$((DIFF / 3600))
	DIFF=$((DIFF % 3600))
	minutes=$((DIFF / 60))
	DIFF=$((DIFF % 60))
	echo --------------------------------------------------------------------------------------------------
	echo ========= Script started at $D1 $T1 GMT =========
	echo ========= Script completed at $Dcurrent $Tcurrent GMT =========
	echo ========= "Script took ${hours}H:${minutes}M:${DIFF}S" =========
}

#Function : Usage
Usage(){
	echo --------------------------------------------------------------------------------------------------
	echo "Please provide all the parameters. Make sure the branch/sha is correct"
	echo --------------------------------------------------------------------------------------------------
	echo "Usage: $0 <JIRAID> <branch or sha> <TAG> <PT_FILE> <RepoValidate?> <invokeip>"
	echo "  $0 INFRA-111 team_api latest homepage.jmx Y 52.18.124.146"
	echo "  $0 INFRA-111 36340628e1979fb78c0f1fa4d30b9b233c05056e latest homepage.jmx N 52.18.124.146"
	getTime
	exit 1
}

#Validation : Based on apache config, execute the script
if ! [ -f /etc/httpd/conf/extra/environment.template ];then
	echo --------------------------------------------------------------------------------------------------
	echo "Please run the script from the server where Apache needs to be started for Application URLS."
	getTime
	exit 1
fi

if [ $# -lt 6 ];then
	Usage
else
	#Assign : parmeters
	release=$1
	_BRANCH_=$2
	TAG=$3
	_FILE_=$4
	repovalidate=$5
	invokerip=$6
	_EMAIL_=$7
	registryName="registry.shopping:80"
	BINDIR="/opt/shop-envod"
	#MD is script kept in /bin with below content
	# docker -H tcp://<PRIVATE_IP_OF_AWS>:2376 $@
	RUNCMD="MD run -d -e TERM=xterm -v ${BINDIR}:${BINDIR} --privileged=true"

	mkdir -p ${BINDIR}/out
	cat /dev/null > ${BINDIR}/out/${release}_garbage.txt
	chmod -R 777 ${BINDIR}/
fi

#Pull images from registry

#Jira ID validation
${BINDIR}/binaries/atlassian-cli-3.9.0/jira.sh --action getIssueList -s http://jira.domain.com -u ${JIRA_USER} -p ${JIRA_PASS} --filter envod --columns KEY| grep -o ${release} > /dev/null 2>&1
if ! [ "$?" == "0" ];then
		echo --------------------------------------------------------------------------------------------------
		echo "JIRAID : $release does not exist."
		Usage
fi

#Branch validation
branchValidate(){
for eachRepo in cache commerce content controlm dataload msjobs search
do
	git ls-remote --heads "https://github.com/DigitalInnovation/shop-${eachRepo}.git" | grep ${_BRANCH_} > /dev/null 2>&1
	if ! [ "$?" == "0" ];then
		echo --------------------------------------------------------------------------------------------------
		echo "Branch/sha: ${_BRANCH_} does not exist for ${eachRepo}."
		Usage
	fi
done
}
if [ "${repovalidate}" == "Y" ];then
branchValidate
fi
#Function: Cleanup of containers
cleanup(){
	release_containers=$(MD ps -a | grep -i ${release} | grep -v grep | awk '{print $NF}' | sed 's/^\(.*\)'"${release}"'\(.*\)$/'"${release}"'\2/g' | tr "\n" " ")
	if [ "$release_containers" == "" ];then
		echo --------------------------------------------------------------------------------------------------
		echo "None of the containers are running on either of nodes."
		getTime
		exit 1
	fi
	echo --------------------------------------------------------------------------------------------------
	echo "Stopping below containers..."
	MD stop ${release_containers} 2> /dev/null
	echo --------------------------------------------------------------------------------------------------
	echo "Cleaning up below containers..."
	MD rm ${release_containers} 2> /dev/null
	sed -i '/'"${release}"'=/d' release_file > /dev/null 2>&1
	echo --------------------------------------------------------------------------------------------------
	echo "Cleaning up shared directories and ${release} temp files..."
	rm -rfv /shared-dir/${release} ${BINDIR}/out/*${release}* ${BINDIR}/*${release}*
	rm -vf /etc/httpd/conf/extra/${release}.conf
	/etc/httpd/bin/httpd -k restart
	echo ============================================
	echo Environment $release could not be forked out.
	echo ============================================
	getTime
	exit 1
}


#Validation: already running instance of environment
if ! [ -f ./release_file ];then
	cat /dev/null > ${BINDIR}/release_file ; chmod 777 ${BINDIR}/release_file
elif [ "$(grep ${release} release_file)" != "" ];then
	echo --------------------------------------------------------------------------------------------------
	echo "Release ## $release ## stack is might already be running."
	echo "Use destroy script and re-invoke the stack build again. Exiting..."
	getTime
	exit 1
fi

#Check free release number with environment provisioning
for i in {0..9}
do
	relNo=$(cut -d "=" -f2 release_file | sort -u| grep $i)
	if [ "$relNo" == "" ];then
		R=$i
		break;
	fi
done

if [ "$R" == "" ];then
	echo --------------------------------------------------------------------------------------------------
	echo "No further release stack can be forked out. Exiting..."
	getTime
	exit 1
fi

echo ${release}=${R}>>${BINDIR}/release_file

for i in {0..9}
do
	for j in {0..9}
	do
		declare "P$i$j=30${R}$i$j"
	done
done

##################################################
#Creating folder structure and permission to xml files
dos2unix *.sh *.txt
echo --------------------------------------------------------------------------------------------------
echo Creating structure for author...
echo --------------------------------------------------------------------------------------------------
sh folderCreationScript.sh ${release} dockerauth
echo --------------------------------------------------------------------------------------------------
echo Creating structure for live...
echo --------------------------------------------------------------------------------------------------
sh folderCreationScript.sh ${release} docker
echo --------------------------------------------------------------------------------------------------

for path in $(ls -d /shared-dir/${release}/nas*/wcsConfig/*cl)
do
	cp ${BINDIR}/*.xml ${path}/
	chmod 777 ${path}/*.xml
done

#Creating splunkdir for logs
mkdir -p /shared-dir/${release}/splunklogs
##################################################

#1 ------------ DATABASE CONTAINER AUTHOR------------
# P01:1521
echo --------------------------------------------------------------------------------------------------
echo "Starting DB AUTH container..."
echo --------------------------------------------------------------------------------------------------
${RUNCMD} -e constraint:node==<NODE_WHERE_CONTAINER_WOULD_BE_RUNNING> -p $P01:1521 -p $P69:80 --name ${release}_dbauth -h dbauth.domain.com ${registryName}/dbauth:${TAG} /usr/sbin/sshd -D
	if [ "$?" != "0" ];then
		cleanup
	fi
dbauth_node=$(MD inspect -f '{{.Node.Name}}' ${release}_dbauth )
echo --------------------------------------------------------------------------------------------------

#1 ------------ DATABASE CONTAINER LIVE ------------
# P02:1521
echo "Starting DB LIVE container..."
echo --------------------------------------------------------------------------------------------------
${RUNCMD} -e constraint:node==<NODE_WHERE_CONTAINER_WOULD_BE_RUNNING> -p $P02:1521 -p $P70:80 --name ${release}_dblive -h dblive.domain.com ${registryName}/dblive:${TAG} /usr/sbin/sshd -D
	if [ "$?" != "0" ];then
		cleanup
	fi
dblive_node=$(MD inspect -f '{{.Node.Name}}' ${release}_dblive )
echo --------------------------------------------------------------------------------------------------

#2 ------------ MQ CONTAINER ------------
# P03:22, P04:22222
#echo --------------------------------------------------------------------------------------------------

#3 ------------ JENKINS CONTAINER ------------
# P52:22, P53:8080, P54=variable
echo "Starting Jenkins container..."
echo --------------------------------------------------------------------------------------------------
${RUNCMD} -e constraint:node==<NODE_WHERE_CONTAINER_WOULD_BE_RUNNING> -p $P52:22 -p $P53:8080 -p $P54:$P54 --name ${release}_jenkins -h jenkins.domain.com ${registryName}/jenkins:${TAG} /usr/sbin/sshd -D
if [ "$?" != "0" ];then
	cleanup
fi
jenkins_node=$(MD inspect -f '{{.Node.Name}}' ${release}_jenkins )
echo --------------------------------------------------------------------------------------------------
#4 ---------- MULE CONTAINER ------------
# P08:22, P09:8888, P10:8887
echo "Starting mule container..."
echo --------------------------------------------------------------------------------------------------
${RUNCMD} -e constraint:node==<NODE_WHERE_CONTAINER_WOULD_BE_RUNNING> -p $P08:22 -p $P09:8887 -p $P10:8888 --name ${release}_mule -h mule.domain.com ${registryName}/mule:${TAG}  /usr/sbin/sshd -D
if [ "$?" != "0" ];then
	cleanup
fi
mule_node=$(MD inspect -f '{{.Node.Name}}' ${release}_mule )
echo --------------------------------------------------------------------------------------------------

#5 ---------- CONTROL-M SERVER CONTAINER ------------
# P13:22, P14:7005, P15:7006
echo "Starting ctrlm container..."
echo --------------------------------------------------------------------------------------------------
${RUNCMD} -e constraint:node==<NODE_WHERE_CONTAINER_WOULD_BE_RUNNING> -p $P13:22 -p $P14:7005 -p $P15:7006 --name ${release}_ctm -h ctm.domain.com  ${registryName}/controlm:${TAG}  /usr/sbin/sshd -D
if [ "$?" != "0" ];then
	cleanup
fi
ctm_node=$(MD inspect -f '{{.Node.Name}}' ${release}_ctm )
echo --------------------------------------------------------------------------------------------------

#6 ---------- WXS CONTAINER ------------
# P05:22, P06:2809, P07:1105
echo "Starting wxs container..."
echo --------------------------------------------------------------------------------------------------
${RUNCMD} -e constraint:node==<NODE_WHERE_CONTAINER_WOULD_BE_RUNNING> -p $P05:22 -p $P06:2814 -p $P07:2815 --name ${release}_wxs -h wxs.domain.com ${registryName}/cache:${TAG}  /usr/sbin/sshd -D
if [ "$?" != "0" ];then
	cleanup
fi
wxs_node=$(MD inspect -f '{{.Node.Name}}' ${release}_wxs )
echo --------------------------------------------------------------------------------------------------
#7 ---------- VACENT ------------
# P11:22,

#8 ---------- ENDECA CONTAINER ------------
# P12:8443 , P16:22, P17:8006, P18:8443, P57:17010
echo "Starting endeca container..."
echo --------------------------------------------------------------------------------------------------
${RUNCMD} -e constraint:node==<NODE_WHERE_CONTAINER_WOULD_BE_RUNNING> -v /shared-dir/${release}/nas-search-itl:/nas-search-itl  -p $P12:8443 -p $P16:22 -p $P17:8006 -p $P18:17000 -p $P57:17010 --name ${release}_endeca -h endeca.domain.com ${registryName}/search:${TAG} /usr/sbin/sshd -D
if [ "$?" != "0" ];then
	cleanup
fi
endeca_node=$(MD inspect -f '{{.Node.Name}}' ${release}_endeca )
echo --------------------------------------------------------------------------------------------------
#9 ---------- WASGUEST CONTAINER ------------
# P19:22, P20:10000, P21:10001, P55:10243
echo "Starting wasguest container..."
echo --------------------------------------------------------------------------------------------------
${RUNCMD} -v /shared-dir/${release}/splunklogs:/splunklogs -e constraint:node==<NODE_WHERE_CONTAINER_WOULD_BE_RUNNING> -v /shared-dir/${release}/nas-cq-pub:/nas-cq-pub -v /shared-dir/${release}/nas-cq-auth:/nas-cq-auth -p $P19:22 -p $P20:$P20 -p $P21:$P21 --name ${release}_wasguest -h wasguest.domain.com  ${registryName}/commercelive:${TAG} /usr/sbin/sshd -D
if [ "$?" != "0" ];then
	cleanup
fi
wasguest_node=$(MD inspect -f '{{.Node.Name}}' ${release}_wasguest )
echo --------------------------------------------------------------------------------------------------
#10 ---------- IHSGUEST CONTAINER ------------
# P22:22, P23:80, P24:443, P25:8000, P26:8001, P27:8002, P28:8004, P29:8006, P30:8007
echo "Starting ihsguest container..."
echo --------------------------------------------------------------------------------------------------
${RUNCMD} -v /shared-dir/${release}/splunklogs:/splunklogs -e constraint:node==<NODE_WHERE_CONTAINER_WOULD_BE_RUNNING> -p $P22:22 -p $P23:80 -p $P24:443 -p $P25:8000 -p $P27:8002 -p $P28:8004 -p $P29:8006 -p $P30:8007 --name ${release}_ihsguest -h www.docker.domain.com  ${registryName}/weblive:${TAG} /usr/sbin/sshd -D
if [ "$?" != "0" ];then
	cleanup
fi
ihsguest_node=$(MD inspect -f '{{.Node.Name}}' ${release}_ihsguest )
echo --------------------------------------------------------------------------------------------------
#11 ---------- WASAUTHOR CONTAINER ------------
# P31:22, P32:10000, P33:10001 , P56:10225
echo "Starting wasauthor container..."
echo --------------------------------------------------------------------------------------------------
${RUNCMD} -v /shared-dir/${release}/splunklogs:/splunklogs -e constraint:node==<NODE_WHERE_CONTAINER_WOULD_BE_RUNNING>  -v /shared-dir/${release}/nas-cq-pub:/nas-cq-pub -v /shared-dir/${release}/nas-cq-auth:/nas-cq-auth -v /shared-dir/${release}/nas-search-itl:/nas-search-itl -p $P31:22 -p $P32:$P32 -p $P33:$P33 --name ${release}_wasauthor -h wasauthor.domain.com  ${registryName}/commerceauth:${TAG} /usr/sbin/sshd -D
if [ "$?" != "0" ];then
	cleanup
fi
wasauthor_node=$(MD inspect -f '{{.Node.Name}}' ${release}_wasauthor )
echo --------------------------------------------------------------------------------------------------
#12 ---------- IHSAUTHOR CONTAINER ------------
# P34:22, P235:80, P36:443, P37:8000, P38:8001, P39:8002, P40:8004, P41:8006, P42:8007
echo "Starting ihsauthor container..."
echo --------------------------------------------------------------------------------------------------
${RUNCMD} -v /shared-dir/${release}/splunklogs:/splunklogs -e constraint:node==<NODE_WHERE_CONTAINER_WOULD_BE_RUNNING> -p $P34:22 -p $P35:80 -p $P36:443 -p $P37:8000 -p $P38:8001 -p $P39:8002 -p $P40:8004 -p $P41:8006 -p $P42:8007 --name ${release}_ihsauthor -h auth.docker.domain.com ${registryName}/webauth:${TAG} /usr/sbin/sshd -D
if [ "$?" != "0" ];then
	cleanup
fi
ihsauthor_node=$(MD inspect -f '{{.Node.Name}}' ${release}_ihsauthor )
echo --------------------------------------------------------------------------------------------------

#13 ---------- CQ PUBLISH CONTAINER ------------
# P43:22, p44:4503, P45:80, P46:443
echo "Starting aempublish container..."
echo --------------------------------------------------------------------------------------------------
${RUNCMD} -e constraint:node==<NODE_WHERE_CONTAINER_WOULD_BE_RUNNING> -v /shared-dir/${release}/nas-cq-pub:/nas-cq-pub -v /shared-dir/${release}/nas-cq-auth:/nas-cq-auth -p $P43:22 -p $P44:4503 -p $P45:80 -p $P46:443 --name ${release}_aempublish -h aempublish.domain.com  ${registryName}/contentlive:${TAG} /usr/sbin/sshd -D
if [ "$?" != "0" ];then
	cleanup
fi
aempublish_node=$(MD inspect -f '{{.Node.Name}}' ${release}_aempublish )
echo --------------------------------------------------------------------------------------------------
#14 ---------- CQ AUTHOR CONTAINER ------------
# P47:22, p48:4502, P49:80, P50:443
echo "Starting aemauthor container..."
echo --------------------------------------------------------------------------------------------------
${RUNCMD} -e constraint:node==<NODE_WHERE_CONTAINER_WOULD_BE_RUNNING> -v /shared-dir/${release}/nas-cq-auth:/nas-cq-auth -v /shared-dir/${release}/nas-cq-pub:/nas-cq-pub -p $P47:22 -p $P48:4502 -p $P49:80 -p $P50:443 --name ${release}_aemauthor -h aemauthor.domain.com ${registryName}/contentauth:${TAG} /usr/sbin/sshd -D
if [ "$?" != "0" ];then
	cleanup
fi
aemauthor_node=$(MD inspect -f '{{.Node.Name}}' ${release}_aemauthor )
echo --------------------------------------------------------------------------------------------------
################# COMMENT STOP  ##################

#15 ---------- JOBS CONTAINER - LIVE ------------
# P58:22, P59:7005, P60:7006
echo "Starting jobs live container..."
echo --------------------------------------------------------------------------------------------------
${RUNCMD} -e constraint:node==<NODE_WHERE_CONTAINER_WOULD_BE_RUNNING> -v /shared-dir/${release}/nas-cq-pub:/nas-cq-pub -v /shared-dir/${release}/nas-cq-auth:/nas-cq-auth -p $P58:22 -p $P59:7005 -p $P60:7006 --name ${release}_jobslive -h jobslive.domain.com ${registryName}/jobslive:${TAG} /usr/sbin/sshd -D
if [ "$?" != "0" ];then
	cleanup
fi
jobslive_node=$(MD inspect -f '{{.Node.Name}}' ${release}_jobslive )
echo --------------------------------------------------------------------------------------------------

#16 ---------- JOBS CONTAINER - AUTH ------------
# P61:22, P62:7005, P63:7006
echo "Starting jobs author container..."
echo --------------------------------------------------------------------------------------------------
${RUNCMD} -e constraint:node==<NODE_WHERE_CONTAINER_WOULD_BE_RUNNING> -v /shared-dir/${release}/nas-cq-pub:/nas-cq-pub -v /shared-dir/${release}/nas-cq-auth:/nas-cq-auth -p $P61:22 -p $P62:7005 -p $P63:7006 --name ${release}_jobsauth -h jobsauthor.domain.com ${registryName}/jobsauth:${TAG} /usr/sbin/sshd -D
if [ "$?" != "0" ];then
	cleanup
fi
jobsauth_node=$(MD inspect -f '{{.Node.Name}}' ${release}_jobsauth )
echo --------------------------------------------------------------------------------------------------
#16 ---------- SPLUNK CONTAINER ------------
# P67:22, P68:8000
echo "Starting splunk container..."
echo --------------------------------------------------------------------------------------------------
${RUNCMD} -v /shared-dir/${release}/splunklogs:/splunklogs -p $P67:22 -p $P68:8000 --name ${release}_splunk -h splunk.domain.com ${registryName}/splunklight:${TAG} /usr/sbin/sshd -D
if [ "$?" != "0" ];then
	cleanup
fi
splunk_node=$(MD inspect -f '{{.Node.Name}}' ${release}_splunk )
echo --------------------------------------------------------------------------------------------------

#16 ---------- BDD CONTAINER ------------
#
echo "Starting BDD container..."
echo --------------------------------------------------------------------------------------------------
${RUNCMD} -e constraint:node==<NODE_WHERE_CONTAINER_WOULD_BE_RUNNING> -p $P71:22 --name ${release}_bdd -h bdd.domain.com ${registryName}/bdd:${TAG} /usr/sbin/sshd -D
if [ "$?" != "0" ];then
	cleanup
fi
bdd_node=$(MD inspect -f '{{.Node.Name}}' ${release}_bdd )
echo --------------------------------------------------------------------------------------------------
echo --------------------------------------------------------------------------------------------------
echo "DBAUTH started on node : ${dbauth_node}"
echo "DBLIVE started on node : ${dblive_node}"
echo "Jenkins started on node : ${jenkins_node}"
echo "Mule started on node : ${mule_node}"
echo "ControlM started on node : ${ctm_node}"
echo "WXS started on node : ${wxs_node}"
echo "Endeca started on node : ${endeca_node}"
echo "WASGUEST started on node : ${wasguest_node}"
echo "IHSGUEST started on node : ${ihsguest_node}"
echo "WASAUTHOR started on node : ${wasauthor_node}"
echo "IHSAUTHOR started on node : ${ihsauthor_node}"
echo "AEM-PUBLISH started on node : ${aempublish_node}"
echo "AEM-AUTHOR started on node : ${aemauthor_node}"
echo "JOBS-LIVE started on node : ${jobslive_node}"
echo "JOBS-AUTH started on node : ${jobsauth_node}"
echo "SPLUNK started on node : ${splunk_node}"
echo "BDD started on node : ${bdd_node}"
echo --------------------------------------------------------------------------------------------------
echo --------------------------------------------------------------------------------------------------
##################################################################################################
#Creating external properties
echo "Creating external/properties files for release : ${release}..."
echo --------------------------------------------------------------------------------------------------
cp -rfv ${BINDIR}/ext_props/docker ${BINDIR}/ext_props/${release}_docker
cp -rfv ${BINDIR}/ext_props/dockerauth ${BINDIR}/ext_props/${release}_dockerauth
sed -i s#_DB_PORT_LIVE_#${P02}#g ${BINDIR}/ext_props/${release}_docker/external.properties
sed -i s#_DB_PORT_AUTH_#${P01}#g ${BINDIR}/ext_props/${release}_dockerauth/external.properties
##################################################################################################
#XAPP changes
echo --------------------------------------------------------------------------------------------------
echo "Proceeding with xapp changes for endeca ports..."
echo --------------------------------------------------------------------------------------------------
sed 's/release/'"${release}"'/g;s/\<endeca_port\>/'"${P18}"'/;s/\<endeca_port_logger\>/'"${P57}"'/;s/\<invokerip\>/'"${invokerip}"'/g' ${BINDIR}/author.sql > ${BINDIR}/out/${release}_author.sql
sed 's/release/'"${release}"'/g;s/\<endeca_port\>/'"${P18}"'/;s/\<endeca_port_logger\>/'"${P57}"'/;s/\<invokerip\>/'"${invokerip}"'/g' ${BINDIR}/guest.sql > ${BINDIR}/out/${release}_guest.sql
echo --------------------------------------------------------------------------------------------------
echo "Xapp changes for endeca ports are completed."
echo --------------------------------------------------------------------------------------------------
#Getting tokenized values for host/ports
jenkins_master_host=$(MD inspect --format='{{.Node.IP}}' ${release}_jenkins)

#Generate environment properties
cat << EOF >> ${BINDIR}/${release}_env.properties
release=$release
BINDIR=/opt/shop-envod
_BRANCH_=${_BRANCH_}
jenkins_master_host=${jenkins_master_host}
jenkins_master_port=${P53}
jenkins_master_port_slave=${P54}
invokerip=${invokerip}
_FILE_=${_FILE_}
_SID_=PLATFORM
_DB_HOST_IP_=10.166.0.214
_DB_HOSTNAME_AUTH_=dbauth.domain.com
_DB_HOSTNAME_LIVE_=dblive.domain.com
_DB_PORT_AUTH_=${P01}
_DB_PORT_LIVE_=${P02}
_P20_=${P20}
_P21_=${P21}
_P32_=${P32}
_P33_=${P33}
_EMAIL_="$_EMAIL_"
EOF

##################################################################################################
#> Generate host files for environment [internal IP]
#> Generate env scripts for components

############### COMMENT START ###############
for i in aemauthor aempublish ctm endeca ihsauthor ihsguest jenkins jobsauth jobslive mule wasauthor wasguest wxs splunk
############### COMMENT END ###############
#for i in ctm endeca ihsauthor ihsguest jenkins jobsauth jobslive mule wasauthor wasguest wxs
do
	IPAddress=$(MD inspect -f '{{.NetworkSettings.IPAddress}}' ${release}_${i})
	Hostname=$(MD inspect -f '{{.Config.Hostname}}' ${release}_${i})
	Domainname=$(MD inspect -f '{{.Config.Domainname}}' ${release}_${i})
	if [ "${i}" == "endeca" ] ; then
		IpExt=$(MD inspect -f '{{.Node.IP}}' ${release}_${i})
		echo $IpExt $Hostname.$Domainname $Hostname > ${BINDIR}/out/${release}_${i}.txt
		sed 's#BINDIR#'"${BINDIR}"'#g;s#release_#'"${release}"'_#g' ${BINDIR}/${i}.sh > ${BINDIR}/${release}_${i}.sh 2>/dev/null
	else
		echo $IPAddress $Hostname.$Domainname $Hostname > ${BINDIR}/out/${release}_${i}.txt
		sed 's#BINDIR#'"${BINDIR}"'#g;s#release_#'"${release}"'_#g' ${BINDIR}/${i}.sh > ${BINDIR}/${release}_${i}.sh 2>/dev/null

	fi
done

#Custom scripts for BDD Node
sed 's#BINDIR#'"${BINDIR}"'#g;s#release_#'"${release}"'_#g'  ${BINDIR}/bddstart.sh > ${BINDIR}/${release}_bddstart.sh 2>/dev/null
cat ${BINDIR}/bdd.sh > ${BINDIR}/${release}_bdd.sh 2>/dev/null
###############################################################################################################
#Token replacement for getHost shell
sed 's#BINDIR#'"${BINDIR}"'#g;s#release#'"${release}"'#g' ${BINDIR}/getHost.sh > ${BINDIR}/${release}_getHost.sh

#Changes for Database
echo 10.166.0.214 dbauth.domain.com dbauth > ${BINDIR}/out/${release}_dbauth.txt
echo 10.166.0.214 dblive.domain.com dblive > ${BINDIR}/out/${release}_dblive.txt

##################################################################################################
# Add lobtools and authlobtools to jobslive and jobsauth host entries, for jobs to work properly
sed -i '/jobslive/ s/$/ lobtools.devops.att.mnscorp.net/g' ${BINDIR}/out/${release}_jobslive.txt ${BINDIR}/out/${release}_jobsauth.txt
sed -i '/jobsauth/ s/$/ authlobtools.devops.att.mnscorp.net/g' ${BINDIR}/out/${release}_jobslive.txt ${BINDIR}/out/${release}_jobsauth.txt


##################################################################################################
# Execute DB LIVE changes

sed 's#BINDIR#'"${BINDIR}"'#g;s#release#'"${release}"'#g' ${BINDIR}/dbstarter.sh > ${BINDIR}/${release}_dbstarter.sh 2>/dev/null
chmod 777 ${BINDIR}/*.sh

##################################################################################################
# Execute DB live changes
echo --------------------------------------------------------------------------------------------------
echo "Initiating dblive changes..."
echo --------------------------------------------------------------------------------------------------
MD exec -t ${release}_dblive ${BINDIR}/${release}_dbstarter.sh
echo --------------------------------------------------------------------------------------------------

##################################################################################################
# Execute DB auth changes
echo --------------------------------------------------------------------------------------------------
echo "Initiating dbauth changes..."
echo --------------------------------------------------------------------------------------------------
MD exec -t ${release}_dbauth ${BINDIR}/${release}_dbstarter.sh
echo --------------------------------------------------------------------------------------------------

#	ALL CONTAINERS LIST:
#	aemauthor aempublish ctm dbauth dblive endeca ihsauthor ihsguest jenkins jobsauth jobslive mule wasauthor wasguest wxs
chmod 777 ${BINDIR}/${release}* ${BINDIR}/out/${release}*
##################################################################################################
#Execute changes in sequence of containers
hostList="aemauthor aempublish ctm dbauth dblive endeca ihsauthor ihsguest jenkins jobsauth jobslive mule wasauthor wasguest wxs splunk"
for eachCon in jenkins mule wxs endeca wasguest ihsguest wasauthor ihsauthor aempublish aemauthor jobslive jobsauth ctm splunk
do
	echo "Initiating ${eachCon} changes..."
	echo --------------------------------------------------------------------------------------------------
	MD exec -t ${release}_${eachCon} "sh ${BINDIR}/${release}_getHost.sh $(echo ${hostList} | sed 's/\ '"${eachCon}"'//')"
	MD exec -t ${release}_${eachCon} ${BINDIR}/${release}_${eachCon}.sh
	if [ "$?" != "0" ];then
		cleanup
	fi
	echo --------------------------------------------------------------------------------------------------
done

# BDD changes
echo --------------------------------------------------------------------------------------------------
echo "Initiating BDD changes..."
echo --------------------------------------------------------------------------------------------------
MD exec -t ${release}_bdd ${BINDIR}/${release}_bddstart.sh
if [ "$?" != "0" ];then
	cleanup
fi
echo --------------------------------------------------------------------------------------------------

echo --------------------------------------------------------------------------------------------------
##################################################################################################
##################################################################################################
# Getting Environment details and URLS
#
#
############# COMMENT START #############
cqauthornodeip=$(MD inspect --format='{{.Node.IP}}' ${release}_aemauthor)
cqpublishnodeip=$(MD inspect --format='{{.Node.IP}}' ${release}_aempublish)
############# COMMENT STOP #############
endecanodeip=$(MD inspect --format='{{.Node.IP}}' ${release}_endeca)
ihsauthnodeip=$(MD inspect --format='{{.Node.IP}}' ${release}_ihsauthor)
ihslivenodeip=$(MD inspect --format='{{.Node.IP}}' ${release}_ihsguest)
jenkinsnodeip=$(MD inspect --format='{{.Node.IP}}' ${release}_jenkins)
wasauthnodeip=$(MD inspect --format='{{.Node.IP}}' ${release}_wasauthor )
wasguestnodeip=$(MD inspect --format='{{.Node.IP}}' ${release}_wasguest)
splunknodeip=$(MD inspect --format='{{.Node.IP}}' ${release}_splunk)
#elknodeip=$(MD inspect --format='{{.Node.IP}}' ${release}_elk)
#elkkibanaport=$P64
#elkelasticport=$P65
wasauthorport=$P32
wasguestport=$P20
jenkinsport=$P53
authadmport=$P39
authlobtoolsport=$P37
authorgport=$P40
cqauthornodeport=$P48
cqdispauthport=$P50
cqdisppubport=$P46
cqpublishnodeport=$P44
ihsauthnodeport=$P35
ihsauthnodeportssl=$P36
ihslivenodeport=$P23
ihslivenodeportssl=$P24
liveadmport=$P27
livelobtoolsport=$P25
liveorgport=$P28
workbenchport=$P17
workbenchportssl=$P12
splunknodeport=$P68
dbauthip=10.166.0.214
dbauthport=$P69
dbliveip=10.166.0.214
dbliveport=$P70

echo "Stopping proxy apache and proceeding with $release changes..."
echo --------------------------------------------------------------------------------------------------
/etc/httpd/bin/httpd -k stop
sleep 5
#sed 's/env/'"${release}"'/g;s/\<authadmport\>/'"${authadmport}"'/g;s/\<authlobtoolsport\>/'"${authlobtoolsport}"'/g;s/\<authorgport\>/'"${authorgport}"'/g;s/\<cqauthornodeip\>/'"${cqauthornodeip}"'/g;s/\<cqauthornodeport\>/'"${cqauthornodeport}"'/g;s/\<cqdispauthport\>/'"${cqdispauthport}"'/g;s/\<cqdisppubport\>/'"${cqdisppubport}"'/g;s/\<cqpublishnodeip\>/'"${cqpublishnodeip}"'/g;s/\<cqpublishnodeport\>/'"${cqpublishnodeport}"'/g;s/\<endecanodeip\>/'"${endecanodeip}"'/g;s/\<ihsauthnodeip\>/'"${ihsauthnodeip}"'/g;s/\<ihsauthnodeport\>/'"${ihsauthnodeport}"'/g;s/\<ihsauthnodeportssl\>/'"${ihsauthnodeportssl}"'/g;s/\<ihslivenodeip\>/'"${ihslivenodeip}"'/g;s/\<ihslivenodeport\>/'"${ihslivenodeport}"'/g;s/\<ihslivenodeportssl\>/'"${ihslivenodeportssl}"'/g;s/\<liveadmport\>/'"${liveadmport}"'/g;s/\<livelobtoolsport\>/'"${livelobtoolsport}"'/g;s/\<liveorgport\>/'"${liveorgport}"'/g;s/\<workbenchport\>/'"${workbenchport}"'/g;s/\<workbenchportssl\>/'"${workbenchportssl}"'/g;s/\<jenkinsnodeip\>/'"${jenkinsnodeip}"'/g;s/\<jenkinsport\>/'"${jenkinsport}"'/g;s/\<wasauthnodeip\>/'"${wasauthnodeip}"'/g;s/\<wasguestnodeip\>/'"${wasguestnodeip}"'/g;s/\<wasauthorport\>/'"${wasauthorport}"'/g;s/\<wasguestport\>/'"${wasguestport}"'/g;s/\<invokerip\>/'"${invokerip}"'/g;s/\<elknodeip\>/'"${elknodeip}"'/g;s/\<elkkibanaport\>/'"${elkkibanaport}"'/g;s/\<elkelasticport\>/'"${elkelasticport}"'/g' ${BINDIR}/http-proxy/docker-ihstemplate.txt > /etc/httpd/conf/extra/${release}.conf

sed 's/env/'"${release}"'/g;s/\<authadmport\>/'"${authadmport}"'/g;s/\<authlobtoolsport\>/'"${authlobtoolsport}"'/g;s/\<authorgport\>/'"${authorgport}"'/g;s/\<cqauthornodeip\>/'"${cqauthornodeip}"'/g;s/\<cqauthornodeport\>/'"${cqauthornodeport}"'/g;s/\<cqdispauthport\>/'"${cqdispauthport}"'/g;s/\<cqdisppubport\>/'"${cqdisppubport}"'/g;s/\<cqpublishnodeip\>/'"${cqpublishnodeip}"'/g;s/\<cqpublishnodeport\>/'"${cqpublishnodeport}"'/g;s/\<endecanodeip\>/'"${endecanodeip}"'/g;s/\<ihsauthnodeip\>/'"${ihsauthnodeip}"'/g;s/\<ihsauthnodeport\>/'"${ihsauthnodeport}"'/g;s/\<ihsauthnodeportssl\>/'"${ihsauthnodeportssl}"'/g;s/\<ihslivenodeip\>/'"${ihslivenodeip}"'/g;s/\<ihslivenodeport\>/'"${ihslivenodeport}"'/g;s/\<ihslivenodeportssl\>/'"${ihslivenodeportssl}"'/g;s/\<liveadmport\>/'"${liveadmport}"'/g;s/\<livelobtoolsport\>/'"${livelobtoolsport}"'/g;s/\<liveorgport\>/'"${liveorgport}"'/g;s/\<workbenchport\>/'"${workbenchport}"'/g;s/\<workbenchportssl\>/'"${workbenchportssl}"'/g;s/\<jenkinsnodeip\>/'"${jenkinsnodeip}"'/g;s/\<jenkinsport\>/'"${jenkinsport}"'/g;s/\<wasauthnodeip\>/'"${wasauthnodeip}"'/g;s/\<wasguestnodeip\>/'"${wasguestnodeip}"'/g;s/\<wasauthorport\>/'"${wasauthorport}"'/g;s/\<wasguestport\>/'"${wasguestport}"'/g;s/\<invokerip\>/'"${invokerip}"'/g;s/\<splunknodeip\>/'"${splunknodeip}"'/g;s/\<splunknodeport\>/'"${splunknodeport}"'/g;s/\<dbauthip\>/'"${dbauthip}"'/g;s/\<dbauthport\>/'"${dbauthport}"'/g;s/\<dbliveip\>/'"${dbliveip}"'/g;s/\<dbliveport\>/'"${dbliveport}"'/g' ${BINDIR}/http-proxy/docker-ihstemplate.txt > /etc/httpd/conf/extra/${release}.conf
echo "Starting proxy apache"
/etc/httpd/bin/apachectl -k stop
sleep 5
nohup /etc/httpd/bin/apachectl -k start > /dev/null 2>&1 </dev/null &
sleep 5
ps -ef | grep -E "/etc/httpd/bin/httpd" | grep -v grep

if [ "$?" == "0" ];then
	echo "Proxy Apache is started."
else
	echo "Proxy Apache is not started."
	echo "Please check the issue with proxy."
fi


#########################
#Echo the environment URLS
cat << EOF >> ${BINDIR}/out/${release}_URL.txt
WCS Author Environment
====================
Application: http://auth.${release}.${invokerip}.xip.io
AdminConsole: https://authadminconsole.${release}.${invokerip}.xip.io/adminconsole
Management Center: https://authlobtools.${release}.${invokerip}.xip.io/lobtools
OrgadminConsole: https://authorgadminconsole.${release}.${invokerip}.xip.io/orgadminconsole
API: https://commerce-api.${release}.${invokerip}.xip.io
DMGR: http://dmgrauth.${release}.${invokerip}.xip.io/ibm/console/login.do

WCS Live Environment
====================
Application: http://www.${release}.${invokerip}.xip.io
AdminConsole: https://adminconsole.${release}.${invokerip}.xip.io/adminconsole
Management Center: https://lobtools.${release}.${invokerip}.xip.io/lobtools
OrgadminConsole :https://orgadminconsole.${release}.${invokerip}.xip.io/orgadminconsole
CS URL : https://cs.${release}.${invokerip}.xip.io
ISA URL: https://store.${release}.${invokerip}.xip.io
DMGR: http://dmgr.${release}.${invokerip}.xip.io/ibm/console/login.do
CACHE MONITOR: https://ogadminconsole.${release}.${invokerip}.xip.io/cachemonitor

CMS Environment
===================
CQ Author : http://cqauthor.${release}.${invokerip}.xip.io
CQ publish : http://cqpublish.${release}.${invokerip}.xip.io

Endeca Environment
====================
Workbench: http://workbench.${release}.${invokerip}.xip.io
JSPREF: http://workbench.${release}.${invokerip}.xip.io/endeca_jspref

jenkins Environment
====================
http://jenkins.${release}.${invokerip}.xip.io

Splunk
====================
http://splunk.${release}.${invokerip}.xip.io

DB Access
====================
Auth : http://dbauth.${release}.${invokerip}.xip.io/cgi-bin/oracletool.pl
Live : http://dblive.${release}.${invokerip}.xip.io/cgi-bin/oracletool.pl
EOF

chmod 777 ${BINDIR}/out/${release}_URL.txt
getTime
