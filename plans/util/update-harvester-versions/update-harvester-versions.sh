# 1. Is JsonLibrary version higher than its dependency in the HarvesterBaseLibrary?
#      -> Change dependency version in HarvesterBaseLibrary
#      -> Change version of HarvesterBaseLibrary
#
# 2. Is HarvesterBaseLibrary version higher than its dependency in the HarvesterParentPom?
#      -> Change dependency version in HarvesterParentPom  
#
# 3. Is HarvesterUtils version higher than its dependency in the HarvesterParentPom?
#      -> Change dependency version in HarvesterParentPom
#
# 4. Is ParentPom version higher than the current parent of the HarvesterParentPom?
#      -> Change parent version in HarvesterParentPom
#
# 5. Was HarvesterParentPom changed?
#      -> Change version of HarvesterParentPom
#
# 6. For each Harvester do: Is HarvesterParentPom version higher than the parent of the Harvester?
#      -> Change parent version in Harvester pom


# check login
userName=${bamboo.ManualBuildTriggerReason.userName}
if [ "$userName" = "" ]; then
  echo "Please log in to Bamboo!" >&2
  exit 1
fi
encodedEmail=$(echo "$userName" | sed -e "s/@/%40/g")

# check if password exists
userPw=${bamboo.passwordGit}
if [ "$userPw" = "" ]; then
  echo "You need to specify your BitBucket password by setting the 'passwordGit' variable when running the plan customized!" >&2
  exit 1
fi

# Get User Full Name
userFullName=$(curl -sX GET -u $userName:$userPw https://ci.gerdi-project.de/browse/user/$encodedEmail)
userFullName=${userFullName#*<title>}
userFullName=${userFullName%%:*}


# FUNCTION FOR CREATING A JIRA TICKET
CreateJiraTicket() {
  jiraPostResponse=$(curl -sX POST -u $userName:$userPw -H "Content-Type: application/json" -d '{
    "fields": {
      "summary": "Update Harvester Maven Versions ",
	  "description": "This ticket was created by a Bamboo job. The versions of Harvester Maven libraries and projects are to be updated.",
	  "issuetype": { "id": "10002"},
	  "project": {"id": "10400"},
	  "customfield_10006": 0,
	  "labels": [
	    "version",
	    "maven",
	    "bamboo"
	  ]
    }
  }' https://tasks.gerdi-project.de/rest/api/latest/issue)
  
  jiraKey=${jiraPostResponse#*\"key\":\"}
  jiraKey=${jiraKey%%\"*}
  
  echo "Created JIRA task $jiraKey" >&2
  
  echo "$jiraKey"
}


# FUNCTION FOR CREATING A JIRA SUB-TASK
CreateJiraSubTask() {
  jiraParentKey="$1"
  updatedProjectName="$2"
  newVersion="$3"
  reasonForUpdate="$4"
  
  jiraPostResponse=$(curl -sX POST -u $userName:$userPw -H "Content-Type: application/json" -d '{
    "fields": {
      "summary": "Update '"$updatedProjectName"' to Version '"$newVersion"'",
	  "description": "The Maven version of '"$updatedProjectName"' needs to be updated to version '"$newVersion"'.\n\n\n*Details:*\n'"$reasonForUpdate"'",
	  "issuetype": { "id": "10003"},
	  "project": {"id": "10400"},
	  "parent": {"key": "'"$jiraParentKey"'"}
    }
  }' https://tasks.gerdi-project.de/rest/api/latest/issue)
  
  subTaskKey=${jiraPostResponse#*\"key\":\"}
  subTaskKey=${subTaskKey%%\"*}
  
  echo "Added JIRA sub-task $subTaskKey to issue $jiraParentKey" >&2
  
  echo "$subTaskKey"
}

# FUNCTION FOR ADDING AN ISSUE TO THE CURRENT SPRINT
AddTicketToSprint() {
  jiraKeyToAdd="$1"    
    
  # retrieve active sprint name
  jiraGetResponse=$(curl -sX GET -u $userName:$userPw -H "Content-Type: application/json" https://tasks.gerdi-project.de/rest/agile/latest/board/25/sprint)    
  sprintId=${jiraGetResponse##*\"id\":}
  sprintId=${sprintId%%,*}
   
  # add issue to sprint
  curl --output '/dev/null' -sX PUT -u $userName:$userPw -H "Content-Type: application/json" -d '{
      "idOrKeys":["'"$jiraKeyToAdd"'"],
      "customFieldId":10005,
	  "sprintId":'"$sprintId"',
	  "addToBacklog":false
  }' https://tasks.gerdi-project.de/rest/greenhopper/1.0/sprint/rank
  
  echo "Added $jiraKeyToAdd to Sprint $sprintId" >&2
}


# FUNCTION FOR STARTING A JIRA ISSUE
StartJiraTask() {
  taskKey="$1"
  
  #echo "Setting $taskKey to 'Selected for Development'" >&2
  jiraPostResponse=$(curl -sX POST -u $userName:$userPw -H "Content-Type: application/json" -d '{
    "transition": {"id": 111}
  }' https://tasks.gerdi-project.de/rest/api/latest/issue/$taskKey/transitions?expand=transitions.fields)
  
  echo "Setting $taskKey to 'In Progress'" >&2
  jiraPostResponse=$(curl -sX POST -u $userName:$userPw -H "Content-Type: application/json" -d '{
    "transition": {"id": 81}
  }' https://tasks.gerdi-project.de/rest/api/latest/issue/$taskKey/transitions?expand=transitions.fields)
  
}


# FUNCTION FOR FINISHING A JIRA ISSUE
FinishJiraTask() {
  taskKey="$1"
  
  # set to Review
  echo "Setting $taskKey to 'In Review'" >&2
  jiraPostResponse=$(curl -sX POST -u $userName:$userPw -H "Content-Type: application/json" -d '{
    "transition": {"id": 101}
  }' https://tasks.gerdi-project.de/rest/api/latest/issue/$taskKey/transitions?expand=transitions.fields)
  
  # set to Done
  echo "Setting $taskKey to 'Done'" >&2
  jiraPostResponse=$(curl -sX POST -u $userName:$userPw -H "Content-Type: application/json" -d '{
    "transition": {"id": 71}
  }' https://tasks.gerdi-project.de/rest/api/latest/issue/$taskKey/transitions?expand=transitions.fields)
}


# FUNCTION FOR ABORTING A JIRA ISSUE IN PROGRESS
AbortJiraTask() {
  taskKey="$1"
  
  # set to WNF
  echo "Setting $taskKey to 'Will not Fix'" >&2
  jiraPostResponse=$(curl -sX POST -u $userName:$userPw -H "Content-Type: application/json" -d '{
    "transition": {"id": 181},
	"update": {
        "comment": [{"add": {"body": "Could not auto-update, because the major version would change. Please do it manually!"}}]
    }
  }' https://tasks.gerdi-project.de/rest/api/latest/issue/$taskKey/transitions?expand=transitions.fields)
}


# FUNCTION FOR CHECKING IF A MAJOR VERSION UPDATE IS REQUIRED
IsMajorVersionUpdated() {
  sourceMajorVersion=${1%%.*}
  targetMajorVersion=${2%%.*}
  
  if [ $targetMajorVersion -ne $sourceMajorVersion ]; then
    echo "true"
  else
    echo "false"
  fi
}


# FUNCTION FOR COMMITTING AND MERGING TO GIT MASTER
CommitToMaster() {
  branch="$1"
  commitMessage="$2"
  git commit -m ''"$commitMessage"''
  git push -q
  
  git checkout -b master
  git merge -m 'Merged branch '"$branch"' to master:\n'"$commitMessage"'' "$branch"
}


# FUNCTION FOR GETTING A NEW POM VERSION
GetTargetVersionForUpdate(){
  sourceVersion="$1"
  currentTargetVersion="$2"
  sourceParentVersion="$3"
  targetParentVersion="$4"
  
  majorVersionPattern="s~\(\\w\).\\w.\\w-*\\w*~\1~g"
  minorVersionPattern="s~\\w.\(\\w\).\\w-*\\w*~\1~g"
  bugfixVersionPattern="s~\\w.\\w.\(\\w\)-*\\w*~\1~g"
  suffixPattern="s~\\w.\\w.\\w\(-*\\w*\)~\1~g"
    
  sourceMajorVersion=$(echo $sourceVersion | sed -e "$majorVersionPattern")
  sourceMinorVersion=$(echo $sourceVersion | sed -e "$minorVersionPattern")
  sourceBugfixVersion=$(echo $sourceVersion | sed -e "$bugfixVersionPattern")
  sourceSuffix=$(echo $sourceVersion | sed -e "$suffixPattern")
  
  targetMajorVersion=$(echo $currentTargetVersion | sed -e "$majorVersionPattern")
  targetMinorVersion=$(echo $currentTargetVersion | sed -e "$minorVersionPattern")
  targetBugfixVersion=$(echo $currentTargetVersion | sed -e "$bugfixVersionPattern")
  
  sourceParentMajorVersion=$(echo $sourceParentVersion | sed -e "$majorVersionPattern")
  sourceParentMinorVersion=$(echo $sourceParentVersion | sed -e "$minorVersionPattern")
  sourceParentBugfixVersion=$(echo $sourceParentVersion | sed -e "$bugfixVersionPattern")
  
  targetParentMajorVersion=$(echo $targetParentVersion | sed -e "$majorVersionPattern")
  targetParentMinorVersion=$(echo $targetParentVersion | sed -e "$minorVersionPattern")
  targetParentBugfixVersion=$(echo $targetParentVersion | sed -e "$bugfixVersionPattern")
  
  newVersion=""
  newMajor="0"
  newMinor="0"
  newBugfix="0"
  
  # check which part of the version needs to be incremented
  if [ $targetParentMajorVersion -gt $sourceParentMajorVersion ]; then
    newMajor=$(expr $sourceMajorVersion + 1)
  elif [ $targetParentMinorVersion -gt $sourceParentMinorVersion ]; then
    newMajor="$sourceMajorVersion"
    newMinor=$(expr $sourceMinorVersion + 1)
  else
    newMajor="$sourceMajorVersion"
    newMinor="$sourceMinorVersion"
    newBugfix=$(expr $sourceBugfixVersion + 1)
  fi
  
  # assemble version
  newVersion="$newMajor.$newMinor.$newBugfix$sourceSuffix"
  
  # if the new version is higher than the previously calculated one, return it
  if [ "$currentTargetVersion" \> "$newVersion" ]; then
    echo "$currentTargetVersion"
  else	
	echo "$newVersion"
  fi
}


# FUNCTION FOR QUEUEING A PARENT POM UPDATE OF A PROJECT
QueueParentPomUpdate(){
  targetParentVersion="$1"
  
  sourceParentVersion=$(mvn -q -Dexec.executable="echo" -Dexec.args='${project.parent.version}' --non-recursive org.codehaus.mojo:exec-maven-plugin:1.3.1:exec -f "$pomDirectory/pom.xml")

  if [ "$sourceParentVersion" != "$targetParentVersion" ]; then
    echo "Queueing to update parent-pom version of $artifactId from $sourceParentVersion to $targetParentVersion" >&2
  
    # create main task if does not exist
    if [ "$jiraKey" = "" ]; then
      jiraKey=$(CreateJiraTicket)
      AddTicketToSprint "$jiraKey"
      StartJiraTask "$jiraKey"
    fi
		
    # calculate next version
	targetVersion=$(GetTargetVersionForUpdate "$sourceVersion" "$targetVersion" "$sourceParentVersion" "$targetParentVersion")
    echo "pomContent=\"\$(cat \"$pomDirectory/pom.xml\")\"" >> $updateQueue
	echo "newParent=\"<parent>\${pomContent#*<parent>}\"" >> $updateQueue
	echo "newParent=\"\${newParent%%</parent>*}</parent>\"" >> $updateQueue
	echo "newParent=\$(echo \"\$newParent\" | sed -e \"s~<version>$sourceParentVersion</version>~<version>$targetParentVersion</version>~g\")" >> $updateQueue
	echo "rm -f \"$pomDirectory/pom.xml\"" >> $updateQueue
	echo "echo \"\${pomContent%%<parent>*}\$newParent\${pomContent#*</parent>}\" >> \"$pomDirectory/pom.xml\"" >> $updateQueue

	subTaskDescription="$subTaskDescription \\n- Updated *parent-pom* version to *$targetParentVersion*"
	echo "Updated parent-pom version to $targetParentVersion." >> $gitCommitDescription
  fi
}

# FUNCTION FOR QUEUEING A PROPERTY UPDATE OF A PROJECT
QueuePropertyUpdate(){
  targetPropertyName="$1"
  targetPropertyVersion="$2"
  
  sourcePropertyVersion=$(cat "$pomDirectory/pom.xml")
  sourcePropertyVersion=${sourcePropertyVersion#*<$targetPropertyName>}
  sourcePropertyVersion=${sourcePropertyVersion%</$targetPropertyName>*}
  
  #$(mvn -q -Dexec.executable="echo" -Dexec.args='${project.properties.'"$targetPropertyName"'}' --non-recursive org.codehaus.mojo:exec-maven-plugin:1.3.1:exec)

  if [ "$sourcePropertyVersion" != "$targetPropertyVersion" ]; then
    echo "Queueing to update <$targetPropertyName> property of $artifactId from $sourcePropertyVersion to $targetPropertyVersion" >&2
  
    # create main task if does not exist
    if [ "$jiraKey" = "" ]; then
      jiraKey=$(CreateJiraTicket)
      AddTicketToSprint "$jiraKey"
      StartJiraTask "$jiraKey"
    fi
    
    # calculate next version
	targetVersion=$(GetTargetVersionForUpdate "$sourceVersion" "$targetVersion" "$sourcePropertyVersion" "$targetPropertyVersion")
    echo "sed --in-place=.tmp -e \"s~<$targetPropertyName>$sourcePropertyVersion</$targetPropertyName>~<$targetPropertyName>$targetPropertyVersion</$targetPropertyName>~g\" $pomDirectory/pom.xml && rm -f $pomDirectory/pom.xml.tmp" >> $updateQueue
	subTaskDescription="$subTaskDescription \\n- Updated *<$targetPropertyName>* property to *$targetPropertyVersion*"
	echo "Updated $targetPropertyName property to $targetPropertyVersion." >> $gitCommitDescription
  fi
}


# FUNCTION FOR INITIALIZING A VERSION UPDATE FOR A PROJECT
PrepareUpdate() {
  repositoryAddress="$1"
  pomDirectory="$topDir/tempDir/$2"
  
  echo "Going to topDir '$topDir'"
  cd "$topDir"

  # create new file for the update queue shell script  
  updateQueue="$topDir/updateQueue.sh"
  rm -f $updateQueue
  touch $updateQueue
  chmod +x $updateQueue
  
  # create a new file for the git commit message
  gitCommitDescription="$topDir/gitCommitDescription.txt"
  rm -f $gitCommitDescription
  touch $gitCommitDescription
  echo " " >> $gitCommitDescription # add first new-line
  
  # create a variable for the jira sub-task description
  subTaskDescription=""
  
  # remove and (re-)create a temporary folder
  rm -rf tempDir
  mkdir tempDir
  cd tempDir
  
  # clone JsonLibraries
  echo "Cloning repository https://$encodedEmail@$repositoryAddress" >&2
  cloneResponse=$(git clone -q https://$encodedEmail:$userPw@$repositoryAddress .)

  # get version
  artifactId=$(mvn -q -Dexec.executable="echo" -Dexec.args='${project.artifactId}' --non-recursive org.codehaus.mojo:exec-maven-plugin:1.3.1:exec -f"$pomDirectory/pom.xml")
  sourceVersion=$(mvn -q -Dexec.executable="echo" -Dexec.args='${project.version}' --non-recursive org.codehaus.mojo:exec-maven-plugin:1.3.1:exec -f"$pomDirectory/pom.xml")
  targetVersion="$sourceVersion"
}


# FUNCTION FOR EXECUTING ALL QUEUED UPDATES AND COMMITTING THE CHANGES
ExecuteUpdate() {
  
  if [ "$sourceVersion" != "$targetVersion" ]; then
    echo "Will update $artifactId from $sourceVersion to $targetVersion" >&2
	
    # create and start sub task
    subTaskKey=$(CreateJiraSubTask "$jiraKey" "$artifactId" "$targetVersion" "$subTaskDescription")
    StartJiraTask "$subTaskKey"
	
	# update and commit version if it is not major
    isMajorUpdate=$(IsMajorVersionUpdated "$sourceVersion" "$targetVersion")
    if [ "$isMajorUpdate" = "false" ]; then
      # create git branch
      branchName="$jiraKey-VersionUpdate"
      echo $(git checkout -b $branchName) >&2
	  
	  # set GIT user
	  echo $(git config user.email "$userName") >&2
	  echo $(git config user.name "$userFullName") >&2
  
      echo $(git push -q --set-upstream origin $branchName) >&2
    
      # execute update queue
	  echo $(cat $updateQueue) >&2
	  echo $($updateQueue) >&2
	 
	  # set major version
      echo $(mvn versions:set "-DnewVersion=$targetVersion" -DallowSnapshots=true -f"$pomDirectory/pom.xml") >&2
    
      echo $(git add -A) >&2
      echo $(CommitToMaster "$branchName" "$jiraKey $subTaskKey Updated pom version to $targetVersion. $(cat $gitCommitDescription)") >&2
    
      FinishJiraTask "$subTaskKey"
    else
      AbortJiraTask "$subTaskKey"
    fi
  else
    echo "$artifactId is already up-to-date!" >&2
  fi
  
  #rm -rf tempDir
  echo "$targetVersion"
}


# FUNCTION THAT UPDATES THE PARENT POM OF ALL HARVESTERS
UpdateAllHarvesters() {
  newParentVersion="$1"
  
  harvesterUrls=$(curl -sX GET -u $userName:$userPw -H "Content-Type: application/json" https://code.gerdi-project.de/rest/api/latest/projects/HAR/repos | python -m json.tool) 

  # grep harvester clone URLs, except those of the libraries, and convert them to batch instructions
  harvesterUrls=$(echo "$harvesterUrls" \
  | grep -oE '"http.*?git"' \
  | grep -vE '".*/harvesterbaselibrary.git' \
  | grep -vE '".*/harvestersetup.git' \
  | grep -vE '".*/harvesterutils.git' \
  | grep -vE '".*/jsonlibraries.git' \
  | grep -vE '".*/parentpoms.git' \
  | sed -e "s~\"http.*@\(.*\)\"~UpdateHarvester \"\\1\" \"$newParentVersion\"~")

  # execute update of all harvesters
  printf '%s\n' "$harvesterUrls" | while IFS= read -r updateInstruction
  do 
    $updateInstruction
  done #< < (harvesterUrls)
}

# FUNCTION THAT UPDATES A SINGLE HARVESTER'S PARENT POM
UpdateHarvester() {
  cloneLink="$1"
  newParentVersion="$2"

  PrepareUpdate "$cloneLink" "."
  QueueParentPomUpdate "$newParentVersion"
  harvesterVersion=$(ExecuteUpdate)
}

# FUNCTION FOR BUILDING AND DEPLOYING A HARVESTER RELATED LIBRARY VIA THE BAMBOO REST API
BuildAndDeployLibrary() {
  planLabel="$1"
  deploymentVersion="$2"
  deploymentId=$(GetDeploymentId "$planLabel")
  
  # fail if no deployment project exists for the plan label
  if [ $? -ne 0 ]; then
    exit 1
  fi
  echo "DeploymentId: $deploymentId" >&2
  
  planResultKey=$(StartBambooPlan "$planLabel")
  WaitForPlanToBeDone "$planResultKey"
  
  # fail if the plan was not successful
  if [ $? -ne 0 ]; then
    exit 1
  fi
  echo "planResultKey: $planResultKey" >&2
  
  deploymentResultId=$(StartBambooDeployment "$deploymentId" "$deploymentVersion" "$planResultKey")
  WaitForDeploymentToBeDone "$deploymentResultId"
  
  # fail if the deployment was not successful
  if [ $? -ne 0 ]; then
    exit 1
  fi
  echo "deploymentResultId: $deploymentResultId" >&2
}

GetDeploymentId() {
  planLabel="$1"
  
  bambooGetResponse=$(curl -sX GET -u $userName:$userPw -H "Content-Type: application/json" https://ci.gerdi-project.de/rest/api/latest/deploy/project/all)
  deploymentId=${bambooGetResponse%\"planKey\":\{\"key\":\"$planLabel\"\}*}

  if [ ${#deploymentId} -eq ${#bambooGetResponse} ]; then
    echo "The plan $planLabel does not have a deployment job" >&2
    exit 1
  fi

  deploymentId=${deploymentId##*\{\"id\":}
  deploymentId=${deploymentId%%,*}
  
  echo "$deploymentId"
  exit 0
}


# FUNCTION THAT STARTS A BAMBOO PLAN
StartBambooPlan() {
  planLabel="$1"
  
  bambooPostResponse=$(curl -sX POST -u $userName:$userPw -H "Content-Type: application/json" -d '{}' https://ci.gerdi-project.de/rest/api/latest/queue/$planLabel?stage\&executeAllStages)
  buildNumber=${bambooPostResponse#*buildNumber=\"}
  buildNumber=${buildNumber%%\"*}
  
  # return plan result key
  echo "$planLabel-$buildNumber"
}


# FUNCTION THAT DEPLOYS A BAMBOO PROJECT
StartBambooDeployment() {
  deploymentId="$1"
  deploymentVersion="$2"
  planResultKey="$3"
  
  bambooPostResponse=$(curl -sX POST -u $userName:$userPw -H "Content-Type: application/json" -d '{
    "planResultKey":"'"$planResultKey"'",
	"name":"'"$deploymentVersion"'"
  }' https://ci.gerdi-project.de/rest/api/latest/deploy/project/$deploymentId/version)
  
  versionId=${bambooPostResponse#\"*id\": }
  versionId=${versionId%%\"*}
  
  bambooPostResponse=$(curl -sX POST -u $userName:$userPw -H "Content-Type: application/json" https://ci.gerdi-project.de/rest/api/latest/queue/deployment?environmentId=$environmentId&versionId=$versionId)
  deploymentResultId=${bambooPostResponse#*\"deploymentResultId\": }
  deploymentResultId=${deploymentResultId%%\"*}
  
  echo "$deploymentResultId"
}


# FUNCTION THAT WAITS FOR A BAMBOO PLAN TO FINISH
WaitForPlanToBeDone() {
  planResultKey="$1"
  timeoutTries=100
  finishedResponse="{\"message\":\"Result $planResultKey not building.\",\"status-code\":404}"
  bambooGetResponse=""
  
  # wait 3 seconds and send a get-request to check if the plan is still running
  while [ "$bambooGetResponse" != "$finishedResponse"] || [ $timeoutTries -le 0 ]; do
    sleep 3
    bambooGetResponse=$(curl -sX GET -u $userName:$userPw -H "Content-Type: application/json" https://ci.gerdi-project.de/rest/api/latest/result/status/$planResultKey)
	timeoutTries=$(expr $timeoutTries - 1)
  done
  
  # check if the plan finished successfully
  bambooGetResponse=$(curl -sX GET -u $userName:$userPw -H "Content-Type: application/json" https://ci.gerdi-project.de/rest/api/latest/result/status/$planResultKey)
  buildState=$(echo "$bambooGetResponse" | grep -oP "(?<=\<buildState\>)\w+?(?=\</buildState\>)")
  
  if [ "$buildState" == "Successful" ]; then
    exit 0
  else
    echo "Bamboo Plan $planResultKey failed!" >&2
    exit 1
  fi
}


# FUNCTION THAT WAITS FOR A BAMBOO DEPLOYMENT TO FINISH
WaitForDeploymentToBeDone() {
  deploymentResultId="$1"
  timeoutTries=100
  lifeCycleState=""
  
  # wait 10 seconds and send a get-request to check if the plan is still running
  while [ "$lifeCycleState" == "IN_PROGRESS"] || [ $timeoutTries -le 0 ]; do
    sleep 10
    bambooGetResponse=$(curl -sX GET -u $userName:$userPw -H "Content-Type: application/json" https://ci.gerdi-project.de/rest/api/latest/deploy/result/$deploymentResultId)
	lifeCycleState=${bambooGetResponse#*\"lifeCycleState\": }
    lifeCycleState=${lifeCycleState%%\"*}
	timeoutTries=$(expr $timeoutTries - 1)
  done
  
  # check if the plan finished successfully
  deploymentState=${bambooGetResponse#*\"deploymentState\": }
  deploymentState=${deploymentState%%\"*}
  
  if [ "$deploymentState" == "SUCCESS" ]; then
    exit 0
  else
    echo "Bamboo Deployment $deploymentResultId failed!" >&2
    exit 1
  fi
}


# GET PARENT POM VERSIONS
topDir=$(pwd)
cd parentPoms
parentPomVersion=$(mvn -q -Dexec.executable="echo" -Dexec.args='${project.version}' --non-recursive org.codehaus.mojo:exec-maven-plugin:1.3.1:exec)
echo "ParentPom version is: $parentPomVersion" >&2
cd $topDir

# update harvester setup /archive
PrepareUpdate "code.gerdi-project.de/scm/har/harvestersetup.git" "archive"
QueueParentPomUpdate "$parentPomVersion"
harvesterSetupArchiveVersion=$(ExecuteUpdate)

# update harvester setup
PrepareUpdate "code.gerdi-project.de/scm/har/harvestersetup.git" "."
QueueParentPomUpdate "$parentPomVersion"
QueuePropertyUpdate "setup.archive.dependency.version" "$harvesterSetupArchiveVersion"
harvesterSetupVersion=$(ExecuteUpdate)
BuildAndDeployLibrary "CA-HS" "$harvesterSetupVersion"

# update json library
PrepareUpdate "code.gerdi-project.de/scm/har/jsonlibraries.git" "."
QueueParentPomUpdate "$parentPomVersion"
jsonLibVersion=$(ExecuteUpdate)
BuildAndDeployLibrary "CA-JL" "$jsonLibVersion"
exit 0

# update harvester base library
PrepareUpdate "code.gerdi-project.de/scm/har/harvesterbaselibrary.git" "."
QueuePropertyUpdate "gerdigson.dependency.version" "$jsonLibVersion"
QueueParentPomUpdate "$parentPomVersion"
harvesterLibVersion=$(ExecuteUpdate)
#BuildAndDeployLibrary "CA-HL" "$harvesterLibVersion"


# update harvester utils
PrepareUpdate "code.gerdi-project.de/scm/har/harvesterutils.git" "."
QueueParentPomUpdate "$parentPomVersion"
harvesterUtilsVersion=$(ExecuteUpdate)
BuildAndDeployLibrary "CA-HU" "$harvesterUtilsVersion"

# update harvester parent pom
PrepareUpdate "code.gerdi-project.de/scm/har/parentpoms.git" "harvester"
QueueParentPomUpdate "$parentPomVersion"
QueuePropertyUpdate "restfulharvester.dependency.version" "$harvesterLibVersion"
QueuePropertyUpdate "harvesterutils.dependency.version" "$harvesterUtilsVersion"
harvesterParentPomVersion=$(ExecuteUpdate)
BuildAndDeployLibrary "CA-HPPSA" "$harvesterParentPomVersion"

# update all other harvesters
UpdateAllHarvesters "$harvesterParentPomVersion"