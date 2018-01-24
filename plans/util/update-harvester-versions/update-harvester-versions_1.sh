#!/bin/bash


# FUNCTION FOR SETTING UP GLOBAL VARIABLES
InitVariables() {
  # check login
  userName="$bamboo_ManualBuildTriggerReason_userName"
  if [ "$userName" = "" ]; then
    echo "Please log in to Bamboo!" >&2
    exit 1
  fi
  echo "User Email: $userName" >&2
  encodedEmail=$(echo "$userName" | sed -e "s/@/%40/g")

  # check if password exists
  userPw=$bamboo_passwordGit"
  if [ "$userPw" = "" ]; then
    echo "You need to specify your BitBucket password by setting the 'passwordGit' variable when running the plan customized!" >&2
    exit 1
  fi

  # check pull-request reviewers
  reviewer1="$bamboo_firstReviewer}"
  reviewer2="$bamboo_secondReviewer}"
  if [ "$reviewer1" = "" ] || [ "$reviewer2" = "" ] ; then
    echo "You need to specify valid reviewers for your pull-request by setting the 'firstReviewer' and 'secondReviewer' variables when running the plan customized!" >&2
    exit 1
  fi
  if [ "$reviewer1" = "$userName" ] || [ "$reviewer2" = "$userName" ] ; then
    echo "You cannot be a reviewer yourself! Please set the 'firstReviewer' and 'secondReviewer' variables to proper values when running the plan customized!" >&2
    exit 1
  fi

  echo "Reviewer 1: $reviewer1" >&2
  echo "Reviewer 2: $reviewer2" >&2
  
  # Get User Full Name
  userFullName=$(curl -sX GET -u $userName:$userPw https://ci.gerdi-project.de/browse/user/$encodedEmail)
  userFullName=${userFullName#*<title>}
  userFullName=${userFullName%%:*}
  echo "User Full Name: $userFullName" >&2

  # get parent pom version
  topDir=$(pwd)
  cd parentPoms
  parentPomVersion=$(mvn -q -Dexec.executable="echo" -Dexec.args='${project.version}' --non-recursive org.codehaus.mojo:exec-maven-plugin:1.3.1:exec)
  echo "ParentPom Version: $parentPomVersion" >&2
  cd $topDir
}


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


# FUNCTION FOR SETTING A JIRA ISSUE TO REVIEW
ReviewJiraTask() {
  taskKey="$1"
  
  # set to Review
  echo "Setting $taskKey to 'In Review'" >&2
  jiraPostResponse=$(curl -sX POST -u $userName:$userPw -H "Content-Type: application/json" -d '{
    "transition": {"id": 101}
  }' https://tasks.gerdi-project.de/rest/api/latest/issue/$taskKey/transitions?expand=transitions.fields)
}


# FUNCTION FOR SETTING A JIRA ISSUE TO DONE
FinishJiraTask() {
  taskKey="$1"
  
  echo "Setting $taskKey to 'Done'" >&2
  jiraPostResponse=$(curl -sX POST -u $userName:$userPw -H "Content-Type: application/json" -d '{
    "transition": {"id": 71}
  }' https://tasks.gerdi-project.de/rest/api/latest/issue/$taskKey/transitions?expand=transitions.fields)
}


# FUNCTION FOR ABORTING A JIRA ISSUE IN PROGRESS
AbortJiraTask() {
  taskKey="$1"
  reason="$2"
  
  # set to WNF
  echo "Setting $taskKey to 'Will not Fix'" >&2
  jiraPostResponse=$(curl -sX POST -u $userName:$userPw -H "Content-Type: application/json" -d '{
    "transition": {"id": 181},
  "update": {
        "comment": [{"add": {"body": "'"$reason"'"}}]
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
CreatePullRequest() {
  branch="$1"
  title="$2"
  commitMessage="$3"
  git commit -m ''"$commitMessage"''
  git push -q
  
  # retrieve repository slug
  repoSlug=${repositoryAddress%.git}
  repoSlug=${repoSlug##*/}
  
  # retrieve project key
  projectKey=${repositoryAddress%/*}
  projectKey=${projectKey##*/}
  
  echo "Creating Pull-Request for repository '$repoSlug' in project '$projectKey'. Reviewers are $reviewer1 and $reviewer2" >&2
  
  # create pull-request
  bitbucketPostResponse=$(curl -sX POST -u $userName:$userPw -H "Content-Type: application/json" -d '{
    "title": "'"$title"'",
    "description": "Maven version update.",
    "state": "OPEN",
    "open": true,
    "closed": false,
    "fromRef": {
        "id": "refs/heads/'"$branch"'",
        "repository": {
            "slug": "'"$repoSlug"'",
            "name": null,
            "project": {
                "key": "'"$projectKey"'"
            }
        }
    },
    "toRef": {
        "id": "refs/heads/master",
        "repository": {
            "slug": "'"$repoSlug"'",
            "name": null,
            "project": {
                "key": "'"$projectKey"'"
            }
        }
    },
    "locked": false,
    "reviewers": [
        { "user": { "name": "'"$reviewer1"'" }},
        { "user": { "name": "'"$reviewer2"'" }}
    ],
    "links": {
        "self": [
            null
        ]
    }
  }' https://code.gerdi-project.de/rest/api/latest/projects/$projectKey/repos/$repoSlug/pull-requests)
}


# FUNCTION FOR GETTING A NEW POM VERSION
GetTargetVersionForUpdate(){
  currentSourceVersion="$1"
  currentTargetVersion="$2"
  sourceParentVersion="$3"
  targetParentVersion="$4"
  
  majorVersionPattern="s~\(\\w\).\\w.\\w-*\\w*~\1~g"
  minorVersionPattern="s~\\w.\(\\w\).\\w-*\\w*~\1~g"
  bugfixVersionPattern="s~\\w.\\w.\(\\w\)-*\\w*~\1~g"
  suffixPattern="s~\\w.\\w.\\w\(-*\\w*\)~\1~g"
    
  sourceMajorVersion=$(echo $currentSourceVersion | sed -e "$majorVersionPattern")
  sourceMinorVersion=$(echo $currentSourceVersion | sed -e "$minorVersionPattern")
  sourceBugfixVersion=$(echo $currentSourceVersion | sed -e "$bugfixVersionPattern")
  sourceSuffix=$(echo $currentSourceVersion | sed -e "$suffixPattern")
  
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
  if [ -f "$pomDirectory/pom.xml" ]; then
    artifactId=$(mvn -q -Dexec.executable="echo" -Dexec.args='${project.artifactId}' --non-recursive org.codehaus.mojo:exec-maven-plugin:1.3.1:exec -f"$pomDirectory/pom.xml")
    sourceVersion=$(mvn -q -Dexec.executable="echo" -Dexec.args='${project.version}' --non-recursive org.codehaus.mojo:exec-maven-plugin:1.3.1:exec -f"$pomDirectory/pom.xml")
    targetVersion="$sourceVersion"
  else
    # if no pom.xml exists, we cannot update it
	echo "Cannot update '$repositoryAddress' because the pom.xml is missing!" >&2
    artifactId=""
	sourceVersion=""
	targetVersion=""
  fi
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
      branchName="$jiraKey-$subTaskKey-VersionUpdate"
      echo $(git checkout -b $branchName) >&2
    
      # set GIT user
      echo $(git config user.email "$userName") >&2
      echo $(git config user.name "$userFullName") >&2
  
      echo $(git push -q --set-upstream origin $branchName) >&2
    
      # execute update queue
      echo $(cat $updateQueue) >&2
      echo $($updateQueue) >&2
   
      # set major version
      echo $(mvn versions:set "-DnewVersion=$targetVersion" -DallowSnapshots=true -DgenerateBackupPoms=false -f"$pomDirectory/pom.xml") >&2
    
      echo $(git add -A) >&2
      echo $(CreatePullRequest "$branchName" "Update $artifactId" "$jiraKey $subTaskKey Updated pom version to $targetVersion. $(cat $gitCommitDescription)") >&2
   
      ReviewJiraTask "$subTaskKey"
      FinishJiraTask "$subTaskKey"
    else
      AbortJiraTask "$subTaskKey" "Could not auto-update, because the major version would change. Please do it manually!"
    fi
  else
    echo "$artifactId is already up-to-date at version: $targetVersion" >&2
  fi
  
  #rm -rf tempDir
  echo "$targetVersion"
}


# FUNCTION THAT UPDATES THE PARENT POM OF ALL HARVESTERS
UpdateAllHarvesters() {
  newParentVersion="$1"
  
  echo "Trying to update all Harvesters to parent version $newParentVersion!" >&2
  
  harvesterUrls=$(curl -sX GET -u $userName:$userPw -H "Content-Type: application/json" https://code.gerdi-project.de/rest/api/latest/projects/HAR/repos | python -m json.tool) 

  # grep harvester clone URLs, except those of the libraries, and convert them to batch instructions
  harvesterUrls=$(echo "$harvesterUrls" \
  | grep -oE '"http.*?git"' \
  | grep -vE '".*/harvesterbaselibrary.git"' \
  | grep -vE '".*/harvestersetup.git"' \
  | grep -vE '".*/harvesterutils.git"' \
  | grep -vE '".*/jsonlibraries.git"' \
  | grep -vE '".*/parentpoms.git"' \
  | sed -e "s~\"http.*@\(.*\)\"~UpdateHarvester \\1 $newParentVersion~")

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
  if [ "$sourceVersion" != "" ]; then
    QueueParentPomUpdate "$newParentVersion"
    harvesterVersion=$(ExecuteUpdate)
  fi
}


# FUNCTION FOR BUILDING AND DEPLOYING A HARVESTER RELATED LIBRARY VIA THE BAMBOO REST API
BuildAndDeployLibrary() {  
  planLabel="$1"
  deploymentVersion="$2"
	
  # TODO: check if the latest version is among the deployments
  if [ $isReadyToBuild -eq 0 ]; then
    isEverythingSuccessful=1
    
    # get ID of deployment project
    deploymentId=$(GetDeploymentId "$planLabel")
    
    if [ "$deploymentId" != "" ]; then
      echo "deploymentId: $deploymentId" >&2
    
      # get ID of 'Maven Deploy' environment
      environmentId=$(GetMavenDeployEnvironmentId "$deploymentId")
    
      if [ "$environmentId" != "" ]; then
        echo "environmentId: $environmentId" >&2
       
        # get branch number of the plan
        planBranchId=$(GetPlanBranchId "$planLabel")
       
        if [ "$planBranchId" != "" ]; then
          echo "planLabel: $planLabel$planBranchId" >&2  

          # start bamboo plan
          planResultKey=$(StartBambooPlan "$planLabel$planBranchId")
      
          if [ "$planResultKey" != "" ]; then
            echo "planResultKey: $planResultKey" >&2
        
            # wait for plan to finish
            didPlanSucceed=$(WaitForPlanToBeDone "$planResultKey")

            # fail if the plan was not successful
            if [ $didPlanSucceed -eq 0 ]; then        
              # start bamboo deployment
              deploymentResultId=$(StartBambooDeployment "$deploymentId" "$environmentId" "$deploymentVersion($planResultKey)" "$planResultKey")
        
              if [ "$deploymentResultId" != "" ]; then
                echo "deploymentResultId: $deploymentResultId" >&2
                didDeploymentSucceed=$(WaitForDeploymentToBeDone "$deploymentResultId")
        
                if [ $didDeploymentSucceed -eq 0 ]; then
                  isEverythingSuccessful=0
                fi
              fi
            fi
          fi
        fi
      fi
    fi
    if [ $isEverythingSuccessful -eq 0 ]; then
      echo "COULD NOT FINISH BAMBOO PLAN/DEPLOYMENT $planLabel!" >&2
    fi
  fi
}


# FUNCTION FOR RETRIEVING THE NUMBER SUFFIX THAT REPRESENTS THE PLAN BRANCH OF THE CURRENT BRANCH
GetPlanBranchId() {
  planLabel="$1"
  bambooGetResponse=$(curl -sX GET -u $userName:$userPw -H "Content-Type: application/json" https://ci.gerdi-project.de/rest/api/latest/plan/$planLabel/branch/$branch)
  planBranchId=${bambooGetResponse#*key=\"$planLabel}
  planBranchId=${planBranchId%%\"*}
  
  echo "$planBranchId"
}


# FUNCTION THAT RETRIEVES THE ID OF THE DEPLOYMENT JOB THAT IS LINKED TO A SPECIFIED BRANCH
GetDeploymentId() {
  planLabel="$1"
  
  bambooGetResponse=$(curl -sX GET -u $userName:$userPw -H "Content-Type: application/json" https://ci.gerdi-project.de/rest/api/latest/deploy/project/all)
  deploymentId=${bambooGetResponse%\"planKey\":\{\"key\":\"$planLabel\"\}*}

  if [ ${#deploymentId} -eq ${#bambooGetResponse} ]; then
    echo "The plan $planLabel does not have a deployment job" >&2
    echo ""
  else  
    deploymentId=${deploymentId##*\{\"id\":}
    deploymentId=${deploymentId%%,*}
    echo "$deploymentId"
  fi
}


# FUNCTION FOR RETRIEVING THE ID OF THE "MAVEN DEPLOY" ENVIRONMENT ON A SPECIFIED DEPLOYMENT JOB
GetMavenDeployEnvironmentId() {
  deploymentId="$1"
  bambooGetResponse=$(curl -sX GET -u $userName:$userPw -H "Content-Type: application/json" https://ci.gerdi-project.de/rest/api/latest/deploy/project/$deploymentId)
  bambooGetResponse=${bambooGetResponse#*\"environments\":\[}
  environmentId=$(echo "$bambooGetResponse" | grep -oP "(?<=\{\"id\":)\d+(?=,.*?\"name\":\"Maven Deploy\")")
  
  if [ "$environmentId" = "" ]; then
    echo "Could not find a 'Maven Deploy' environment for deployment project $deploymentId!" >&2
  fi
  echo "$environmentId"
}


# FUNCTION THAT STARTS A BAMBOO PLAN
StartBambooPlan() {
  planLabel="$1"
  
  bambooPostResponse=$(curl -sX POST -u $userName:$userPw -H "Content-Type: application/json" -d '{}' https://ci.gerdi-project.de/rest/api/latest/queue/$planLabel?stage\&executeAllStages)
  buildNumber=$(echo "$bambooPostResponse" | grep -oP '(?<=buildNumber=")\d+(?=")')
  
  # return plan result key
  if [ "$buildNumber" = "" ]; then
    echo "Could not start Bamboo Plan $planLabel: $bambooPostResponse" >&2
    echo ""
  else
    echo "$planLabel-$buildNumber"
  fi
}


# FUNCTION THAT DEPLOYS A BAMBOO PROJECT
StartBambooDeployment() {
  deploymentId="$1"
  environmentId="$2"
  deploymentVersion="$3"
  planResultKey="$4"
  
  requestSuffix=""
  versionId=""
  tries=1
  
  # build a version. if it already exists, append _(1)
  while [ "$versionId" = "" ]; do  
    bambooPostResponse=$(curl -sX POST -u $userName:$userPw -H "Content-Type: application/json" -d '{
      "planResultKey":"'"$planResultKey"'",
      "name":"'"$deploymentVersion$requestSuffix"'"
    }' https://ci.gerdi-project.de/rest/api/latest/deploy/project/$deploymentId/version)
  
    hasError=$(echo $bambooPostResponse | grep -P "This release version is already in use, please select another.")
  echo "$hasError" >&2
    if [ "${#hasError}" -eq 0 ]; then
    versionId=${bambooPostResponse#*\{\"id\":}
      versionId=${versionId%%,*}
  else
    requestSuffix="_($tries)"
    tries=$(expr $tries + 1 )
  fi
  done
  
  bambooPostResponse=$(curl -sX POST -u $userName:$userPw -H "Content-Type: application/json" https://ci.gerdi-project.de/rest/api/latest/queue/deployment?environmentId=$environmentId\&versionId=$versionId)
  deploymentResultId=$(echo "$bambooPostResponse" | grep -oP '(?<="deploymentResultId":)\d+(?=,)')
  
  # return plan result key
  if [ "$deploymentResultId" = "" ]; then
    echo "Could not start Bamboo Plan $planLabel: $bambooPostResponse" >&2
  fi
  echo "$deploymentResultId"
}


# FUNCTION THAT WAITS FOR A BAMBOO PLAN TO FINISH
WaitForPlanToBeDone() {
  planResultKey="$1"
  finishedResponse="{\"message\":\"Result $planResultKey not building.\",\"status-code\":404}"
  bambooGetResponse=""
  
  echo "Waiting for plan $planResultKey to finish..." >&2
  
  # wait 3 seconds and send a get-request to check if the plan is still running
  while [ ''"$bambooGetResponse"'' != ''"$finishedResponse"'' ]; do
    bambooGetResponse=$(curl -sX GET -u $userName:$userPw -H "Content-Type: application/json" https://ci.gerdi-project.de/rest/api/latest/result/status/$planResultKey)
    sleep 3
  done
  
  # check if the plan finished successfully
  bambooGetResponse=$(curl -sX GET -u $userName:$userPw -H "Content-Type: application/json" https://ci.gerdi-project.de/rest/api/latest/result/$planResultKey)
  buildState=$(echo "$bambooGetResponse" | grep -oP "(?<=\<buildState\>)\w+?(?=\</buildState\>)")
    
  echo "Bamboo Plan $planResultKey finished with state '$buildState'!" >&2
  if [ "$buildState" = "Successful" ]; then
    echo 0
  else
    echo 1
  fi
}


# FUNCTION THAT WAITS FOR A BAMBOO DEPLOYMENT TO FINISH
WaitForDeploymentToBeDone() {
  deploymentResultId="$1"
  lifeCycleState="IN_PROGRESS"
  
  echo "Waiting for deployment $deploymentResultId to finish..." >&2
  
  # wait 10 seconds and send a get-request to check if the plan is still running
  while [ "$lifeCycleState" = "IN_PROGRESS" ]; do
    bambooGetResponse=$(curl -sX GET -u $userName:$userPw -H "Content-Type: application/json" https://ci.gerdi-project.de/rest/api/latest/deploy/result/$deploymentResultId)
  lifeCycleState=${bambooGetResponse#*\"lifeCycleState\":\"}
    lifeCycleState=${lifeCycleState%%\"*}
    sleep 10
  done
  
  # check if the plan finished successfully
  deploymentState=${bambooGetResponse#*\"deploymentState\":\"}
  deploymentState=${deploymentState%%\"*}
  
  echo "Bamboo Deployment $deploymentResultId finished with state '$deploymentState'!" >&2
  if [ "$deploymentState" = "SUCCESS" ]; then
    echo 0
  else
    echo 1
  fi
}


# set up some variables
InitVariables

# update harvester setup /archive
PrepareUpdate "code.gerdi-project.de/scm/har/harvestersetup.git" "archive"
if [ "$sourceVersion" != "" ]; then
  QueueParentPomUpdate "$parentPomVersion"
  harvesterSetupArchiveVersion=$(ExecuteUpdate)
fi

# update harvester setup
PrepareUpdate "code.gerdi-project.de/scm/har/harvestersetup.git" "."
if [ "$sourceVersion" != "" ]; then
  QueueParentPomUpdate "$parentPomVersion"
  QueuePropertyUpdate "setup.archive.dependency.version" "$harvesterSetupArchiveVersion"
  harvesterSetupVersion=$(ExecuteUpdate)
fi

# update json library
PrepareUpdate "code.gerdi-project.de/scm/har/jsonlibraries.git" "."
if [ "$sourceVersion" != "" ]; then
  QueueParentPomUpdate "$parentPomVersion"
  jsonLibVersion=$(ExecuteUpdate)
  BuildAndDeployLibrary "CA-JL" "$jsonLibVersion"
fi

# update harvester base library
PrepareUpdate "code.gerdi-project.de/scm/har/harvesterbaselibrary.git" "."
if [ "$sourceVersion" != "" ]; then
  QueuePropertyUpdate "gerdigson.dependency.version" "$jsonLibVersion"
  QueueParentPomUpdate "$parentPomVersion"
  harvesterLibVersion=$(ExecuteUpdate)
  BuildAndDeployLibrary "CA-HL" "$harvesterLibVersion"
fi

# update harvester utils
PrepareUpdate "code.gerdi-project.de/scm/har/harvesterutils.git" "."
if [ "$sourceVersion" != "" ]; then
  QueueParentPomUpdate "$parentPomVersion"
  harvesterUtilsVersion=$(ExecuteUpdate)
  BuildAndDeployLibrary "CA-HU" "$harvesterUtilsVersion"
fi

# update harvester parent pom
PrepareUpdate "code.gerdi-project.de/scm/har/parentpoms.git" "harvester"
if [ "$sourceVersion" != "" ]; then
  QueueParentPomUpdate "$parentPomVersion"
  QueuePropertyUpdate "restfulharvester.dependency.version" "$harvesterLibVersion"
  QueuePropertyUpdate "harvesterutils.dependency.version" "$harvesterUtilsVersion"
  harvesterParentPomVersion=$(ExecuteUpdate)
  BuildAndDeployLibrary "CA-HPPSA" "$harvesterParentPomVersion"
fi

# update all other harvesters
UpdateAllHarvesters "$harvesterParentPomVersion"

# set main task to "Review"
ReviewJiraTask "$jiraKey"