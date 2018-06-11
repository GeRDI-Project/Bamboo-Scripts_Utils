#!/bin/bash

# Copyright © 2018 Robin Weiss (http://www.gerdi-project.de/)
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
 
# This script is being called by the Bamboo Job https://ci.gerdi-project.de/browse/UTIL-UHV and does the following things:
#  1. Retrieve the current version of the GeRDI Parent Pom (https://oss.sonatype.org/content/repositories/snapshots/de/gerdi-project/GeRDI-parent/)
#  2. Update the Harvester Setup Archive, if needed (https://oss.sonatype.org/content/repositories/snapshots/de/gerdi-project/GeRDI-harvester-setup-archive/)
#  3. Update the Harvester Setup, if needed (https://oss.sonatype.org/content/repositories/snapshots/de/gerdi-project/GeRDI-harvester-setup/)
#  4. Update the Json Library, if needed (https://oss.sonatype.org/content/repositories/snapshots/de/gerdi-project/GSON/)
#  5. Update the Harvester Base Library, if needed (https://oss.sonatype.org/content/repositories/snapshots/de/gerdi-project/RestfulHarvester-Library/)
#  6. Update the Harvester Utilities, if needed (https://oss.sonatype.org/content/repositories/snapshots/de/gerdi-project/GeRDI-harvester-utilities-archive/)
#  7. Update the Harvester Parent Pom, if needed (https://oss.sonatype.org/content/repositories/snapshots/de/gerdi-project/GeRDI-parent-harvester/)
#  8. Update all Maven Harvester Projects
# If any of the above updates are required, a JIRA ticket is created. All Pom changes are committed on a branch which is automatically created, along with a pull request,
# and a sub-task in the JIRA ticket.
#
# Bamboo Plan Variables:
#  ManualBuildTriggerReason_userName - the login name of the current user
#  atlassianPassword - the Atlassian password of the current user
#  reviewer - the user name of the person that has to review the pull requests

# treat unset variables as an error when substituting
set -u
  
source ./scripts/helper-scripts/atlassian-utils.sh
source ./scripts/helper-scripts/bamboo-utils.sh
source ./scripts/helper-scripts/jira-utils.sh
source ./scripts/helper-scripts/git-utils.sh
source ./scripts/helper-scripts/maven-utils.sh
source ./scripts/helper-scripts/misc-utils.sh


#########################
#  FUNCTION DEFINITIONS #
#########################

# FUNCTION FOR SETTING UP GLOBAL VARIABLES
InitVariables() {
  # check early exit conditions
  ExitIfNotLoggedIn
  ExitIfPlanVariableIsMissing "atlassianPassword"
  ExitIfPlanVariableIsMissing "reviewer"

  atlassianUserName=$(GetBambooUserName)
  atlassianPassword=$(GetValueOfPlanVariable "atlassianPassword")

  # test Atlassian credentials
  ExitIfAtlassianCredentialsWrong "$atlassianUserName" "$atlassianPassword"
  
  # get more Atlassian user details
  atlassianUserEmail=$(GetAtlassianUserEmailAddress "$atlassianUserName" "$atlassianPassword" "$atlassianUserName")
  atlassianUserDisplayName=$(GetAtlassianUserDisplayName "$atlassianUserName" "$atlassianPassword" "$atlassianUserName")
  
  # check pull-request reviewer
  reviewer1=$(GetValueOfPlanVariable reviewer)
  echo "Reviewer: $reviewer1" >&2
  if [ "$reviewer1" = "$atlassianUserName" ]; then
    echo "You cannot be a reviewer yourself! Please set the 'reviewer' variable to a proper value when running the plan customized!" >&2
    exit 1
  fi
  
  # init global variables
  sourceVersion=""
  jiraKey=""

  # get parent pom version
  topDir=$(pwd)
  cd parentPoms
  parentPomVersion=$(GetPomValue "project.version" "")
  echo "ParentPom Version: $parentPomVersion" >&2
  cd $topDir
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
  
  sourceParentVersion=$(GetPomValue "project.parent.version" "$pomDirectory/pom.xml")

  if [ "$sourceParentVersion" != "" ] && [ "$sourceParentVersion" != "$targetParentVersion" ]; then
    echo "Queueing to update parent-pom version of $artifactId from $sourceParentVersion to $targetParentVersion" >&2
  
    # create main task if does not exist
    if [ "$jiraKey" = "" ]; then
      jiraKey=$(CreateJiraTicket \
	    "Update Harvester Maven Versions" \
        "The versions of Harvester Maven libraries and projects are to be updated." \
        "$atlassianUserName" \
        "$atlassianPassword")
      AddJiraTicketToCurrentSprint "$jiraKey" "$atlassianUserName" "$atlassianPassword"
      StartJiraTask "$jiraKey" "$atlassianUserName" "$atlassianPassword"
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
  
  sourcePropertyVersion=$(cat "$pomDirectory/pom.xml" | grep -oP "(?<=\<$targetPropertyName\>)[^\<]*")
  
  if [ "$sourcePropertyVersion" != "" ] && [ "$sourcePropertyVersion" != "$targetPropertyVersion" ]; then
    echo "Queueing to update <$targetPropertyName> property of $artifactId from $sourcePropertyVersion to $targetPropertyVersion" >&2
  
    # create main task if does not exist
    if [ "$jiraKey" = "" ]; then
      jiraKey=$(CreateJiraTicket \
	    "Update Harvester Maven Versions" \
        "The versions of Harvester Maven libraries and projects are to be updated." \
        "$atlassianUserName" \
        "$atlassianPassword")
      AddJiraTicketToCurrentSprint "$jiraKey" "$atlassianUserName" "$atlassianPassword"
      StartJiraTask "$jiraKey" "$atlassianUserName" "$atlassianPassword"
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
  repositorySlug="$1"
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
  CloneGitRepository "$atlassianUserName" "$atlassianPassword" "HAR" "$repositorySlug"
  
  # get version from pom
  if [ -f "$pomDirectory/pom.xml" ]; then
    artifactId=$(GetPomValue "project.artifactId" "$pomDirectory/pom.xml") 
	echo "artifactId: $artifactId" >&2
    sourceVersion=$(GetPomValue "project.version" "$pomDirectory/pom.xml")
	echo "current version: $sourceVersion" >&2
    targetVersion="$sourceVersion"
  else
    # if no pom.xml exists, we cannot update it
	echo "Cannot update 'HAR/$repositorySlug' because the pom.xml is missing!" >&2
    artifactId=""
	sourceVersion=""
	targetVersion=""
  fi
}


# FUNCTION FOR EXECUTING ALL QUEUED UPDATES AND COMMITTING THE CHANGES
ExecuteUpdate() {  
  if [ "$sourceVersion" != "$targetVersion" ]; then
    echo "Will update $artifactId from $sourceVersion to $targetVersion" >&2
  
    # create sub-task
    subTaskKey=$(CreateJiraSubTask \
	  "$jiraKey" \
	  "Update $artifactId to Version $targetVersion" \
      'The Maven version of '"$artifactId"' needs to be updated to version '"$targetVersion"'.\n\n\n*Details:*\n'"$subTaskDescription" \
	  "$atlassianUserName" \
	  "$atlassianPassword")
	  
	# start sub-task
    StartJiraTask "$subTaskKey" "$atlassianUserName" "$atlassianPassword"
  
    # create git branch
    branchName="$jiraKey-$subTaskKey-VersionUpdate"
	CreateBranch "$branchName"
    
    # execute update queue
    echo $($updateQueue) >&2
   
    # set version
    echo $(mvn versions:set "-DnewVersion=$targetVersion" -DallowSnapshots=true -DgenerateBackupPoms=false -f"$pomDirectory/pom.xml") >&2
    
	# commit and push updates
    commitMessage="$jiraKey $subTaskKey Updated pom.xml version to $targetVersion. $(cat $gitCommitDescription)"
	echo $(PushAllFilesToGitRepository "$atlassianUserDisplayName" "$atlassianUserEmail" "$commitMessage") >&2
  
    # create pull request if it is not major version update
    isMajorUpdate=$(IsMajorVersionDifferent "$sourceVersion" "$targetVersion")
    if [ "$isMajorUpdate" = "false" ]; then
      echo $(CreatePullRequest \
        "$atlassianUserName" \
        "$atlassianPassword" \
        "HAR" \
        "$repositorySlug" \
	    "$branchName" \
        "master" \
        "Update $artifactId" \
        "Maven version update." \
        "$reviewer1" \
        "") >&2
      ReviewJiraTask "$subTaskKey" "$atlassianUserName" "$atlassianPassword"
      FinishJiraTask "$subTaskKey" "$atlassianUserName" "$atlassianPassword"
    else
	  echo "Could not close JIRA task, because the major version changed! Please check the code!" >&2
    fi
  else
    echo "$artifactId is already up-to-date at version: $targetVersion" >&2
  fi
}


# FUNCTION THAT UPDATES THE PARENT POM OF ALL HARVESTERS
UpdateAllHarvesters() {
  newParentVersion="$1"
  
  echo "Trying to update all Harvesters to parent version $newParentVersion!" >&2
  
  harvesterUrls=$(curl -sX GET -u "$atlassianUserName:$atlassianPassword" https://code.gerdi-project.de/rest/api/latest/projects/HAR/repos | python -m json.tool) 

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
  while read updateInstruction
  do 
    $updateInstruction
  done <<< "$(echo -e "$harvesterUrls")"
}


# FUNCTION THAT UPDATES A SINGLE HARVESTER'S PARENT POM
UpdateHarvester() {
  cloneLink="$1"
  newParentVersion="$2"
  
  repositorySlug=$(GetRepositorySlugFromCloneLink "$cloneLink")
  PrepareUpdate "$repositorySlug" "."
  if [ "$sourceVersion" != "" ]; then
    QueueParentPomUpdate "$newParentVersion"
    ExecuteUpdate
  fi
}


# FUNCTION FOR BUILDING AND DEPLOYING A HARVESTER RELATED LIBRARY VIA THE BAMBOO REST API
BuildAndDeployLibrary() {  
  planLabel="$1"
  isVersionAlreadyBuilt=$(IsMavenVersionDeployed "$artifactId" "$targetVersion")
  
  if [ "$isVersionAlreadyBuilt" = false ]; then
    isEverythingSuccessful=1
    
    # get ID of deployment project
    deploymentId=$(GetDeploymentId "$planLabel" "$atlassianUserName" "$atlassianPassword")
    
    if [ "$deploymentId" != "" ]; then
      echo "deploymentId: $deploymentId" >&2
    
      # get ID of 'Maven Deploy' environment
      environmentId=$(GetMavenDeployEnvironmentId "$deploymentId" "$atlassianUserName" "$atlassianPassword")
    
      if [ "$environmentId" != "" ]; then
        echo "environmentId: $environmentId" >&2
       
        # get branch number of the plan
        planBranchId=$(GetPlanBranchId "$planLabel" "$branchName" "$atlassianUserName" "$atlassianPassword")
       
        if [ "$planBranchId" != "" ]; then
          echo "planLabel: $planLabel$planBranchId" >&2  

          planResultKey="$planLabel$planBranchId-2"
        
          # wait for plan to finish
          $(WaitForPlanToBeDone "$planResultKey" "$atlassianUserName" "$atlassianPassword")

          # fail if the plan was not successful
          if [ $? -eq 0 ]; then        
            # start bamboo deployment
            deploymentResultId=$(StartBambooDeployment \
			  "$deploymentId" \
			  "$environmentId" \
			  "$targetVersion($planResultKey)" \
			  "$planResultKey" \
			  "$atlassianUserName" \
			  "$atlassianPassword")
        
            if [ "$deploymentResultId" != "" ]; then
              echo "deploymentResultId: $deploymentResultId" >&2
              $(WaitForDeploymentToBeDone "$deploymentResultId" "$atlassianUserName" "$atlassianPassword")
              isEverythingSuccessful=$?
            fi
          fi
        fi
      fi
    fi
    if [ $isEverythingSuccessful -ne 0 ]; then
      echo "DID NOT FINISH BAMBOO PLAN/DEPLOYMENT $planLabel!" >&2
    fi
  else
    echo "Did not deploy $artifactId $targetVersion, because it already exists in the Sonatype repository." >&2
  fi
}


###########################
#  BEGINNING OF EXECUTION #
###########################

# set up some variables
InitVariables

# update harvester utils
PrepareUpdate "harvesterutils" "."
if [ "$sourceVersion" != "" ]; then
  QueueParentPomUpdate "$parentPomVersion"
  ExecuteUpdate
  harvesterUtilsVersion="$targetVersion"
  BuildAndDeployLibrary "CA-HU"
fi

# update harvester setup /archive
PrepareUpdate "harvestersetup" "archive"
if [ "$sourceVersion" != "" ]; then
  QueueParentPomUpdate "$parentPomVersion"
  ExecuteUpdate
  harvesterSetupArchiveVersion="$targetVersion"
fi

# update harvester setup
PrepareUpdate "harvestersetup" "."
if [ "$sourceVersion" != "" ]; then
  QueueParentPomUpdate "$parentPomVersion"
  QueuePropertyUpdate "harvesterutils.dependency.version" "$harvesterUtilsVersion"
  QueuePropertyUpdate "setup.archive.dependency.version" "$harvesterSetupArchiveVersion"
  ExecuteUpdate
  harvesterSetupVersion="$targetVersion"
fi

# update json library
PrepareUpdate "jsonlibraries" "."
if [ "$sourceVersion" != "" ]; then
  QueueParentPomUpdate "$parentPomVersion"
  QueuePropertyUpdate "harvesterutils.dependency.version" "$harvesterUtilsVersion"
  ExecuteUpdate
  jsonLibVersion="$targetVersion"
  BuildAndDeployLibrary "CA-JL"
fi

# update harvester base library
PrepareUpdate "harvesterbaselibrary" "."
if [ "$sourceVersion" != "" ]; then
  QueueParentPomUpdate "$parentPomVersion"
  QueuePropertyUpdate "gerdigson.dependency.version" "$jsonLibVersion"
  ExecuteUpdate
  harvesterLibVersion="$targetVersion"
  BuildAndDeployLibrary "CA-HL"
fi

# update harvester parent pom
PrepareUpdate "parentpoms" "harvester"
if [ "$sourceVersion" != "" ]; then
  QueueParentPomUpdate "$parentPomVersion"
  QueuePropertyUpdate "restfulharvester.dependency.version" "$harvesterLibVersion"
  QueuePropertyUpdate "harvesterutils.dependency.version" "$harvesterUtilsVersion"
  ExecuteUpdate
  harvesterParentPomVersion="$targetVersion"
  BuildAndDeployLibrary "CA-HPPSA"
fi

# update all other harvesters
UpdateAllHarvesters "$harvesterParentPomVersion"

echo " " >&2

if [ "$jiraKey" != "" ]; then
  ReviewJiraTask "$jiraKey" "$atlassianUserName" "$atlassianPassword"
  echo "-------------------------------------------------" >&2
  echo "FINISHED UPDATING! PLEASE, CHECK THE JIRA TICKET:" >&2
  echo "https://tasks.gerdi-project.de/browse/$jiraKey" >&2
  echo "-------------------------------------------------" >&2
else
  echo "------------------------------" >&2
  echo "NO PROJECTS HAD TO BE UPDATED!" >&2
  echo "------------------------------" >&2
fi

echo " " >&2