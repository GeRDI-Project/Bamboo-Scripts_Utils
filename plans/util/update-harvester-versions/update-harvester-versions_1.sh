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
 
# This script is called by the Bamboo Job https://ci.gerdi-project.de/browse/UTIL-UHV and does the following things:
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
#  branch - the branch of the harvester repositories that is to be updated

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


# FUNCTION FOR GETTING A NEW POM VERSION
GetTargetVersionForUpdate(){
  local currentSourceVersion="$1"
  local currentTargetVersion="$2"
  local sourceParentVersion="$3"
  local targetParentVersion="$4"
  
  local majorVersionPattern="s~\(\\w\).\\w.\\w-*\\w*~\1~g"
  local minorVersionPattern="s~\\w.\(\\w\).\\w-*\\w*~\1~g"
  local bugfixVersionPattern="s~\\w.\\w.\(\\w\)-*\\w*~\1~g"
  local suffixPattern="s~\\w.\\w.\\w\(-*\\w*\)~\1~g"
    
  local sourceMajorVersion=$(echo $currentSourceVersion | sed -e "$majorVersionPattern")
  local sourceMinorVersion=$(echo $currentSourceVersion | sed -e "$minorVersionPattern")
  local sourceBugfixVersion=$(echo $currentSourceVersion | sed -e "$bugfixVersionPattern")
  local sourceSuffix=$(echo $currentSourceVersion | sed -e "$suffixPattern")
  
  local targetMajorVersion=$(echo $currentTargetVersion | sed -e "$majorVersionPattern")
  local targetMinorVersion=$(echo $currentTargetVersion | sed -e "$minorVersionPattern")
  #local targetBugfixVersion=$(echo $currentTargetVersion | sed -e "$bugfixVersionPattern")
  
  local sourceParentMajorVersion=$(echo $sourceParentVersion | sed -e "$majorVersionPattern")
  local sourceParentMinorVersion=$(echo $sourceParentVersion | sed -e "$minorVersionPattern")
  #local sourceParentBugfixVersion=$(echo $sourceParentVersion | sed -e "$bugfixVersionPattern")
  
  local targetParentMajorVersion=$(echo $targetParentVersion | sed -e "$majorVersionPattern")
  local targetParentMinorVersion=$(echo $targetParentVersion | sed -e "$minorVersionPattern")
  #local targetParentBugfixVersion=$(echo $targetParentVersion | sed -e "$bugfixVersionPattern")
  
  local newMajor="0"
  local newMinor="0"
  local newBugfix="0"
  
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
  local newVersion
  newVersion="$newMajor.$newMinor.$newBugfix$sourceSuffix"
  
  # if the new version is higher than the previously calculated one, return it
  if $(IsMavenVersionHigher "$newVersion" "$currentTargetVersion"); then
    echo "$newVersion"
  else  
    echo "$currentTargetVersion"
  fi
}


# FUNCTION FOR QUEUEING A PARENT POM UPDATE OF A PROJECT
QueueParentPomUpdate(){
  local targetParentVersion="$1"
  
  local sourceParentVersion
  sourceParentVersion=$(GetPomValue "project.parent.version" "$POM_FOLDER/pom.xml")

  if $(IsMavenVersionHigher "$targetParentVersion" "$sourceParentVersion"); then 
    echo "Queueing to update parent-pom version of $ARTIFACT_ID from $sourceParentVersion to $targetParentVersion" >&2
  
    # create main task if does not exist
    if [ -z "$JIRA_KEY" ]; then
      JIRA_KEY=$(CreateJiraTicket \
	    "Update Harvester Maven Versions" \
        "The versions of Harvester Maven libraries and projects are to be updated." \
        "$ATLASSIAN_USER_NAME" \
        "$ATLASSIAN_PASSWORD")
      AddJiraTicketToCurrentSprint "$JIRA_KEY" "$ATLASSIAN_USER_NAME" "$ATLASSIAN_PASSWORD"
      StartJiraTask "$JIRA_KEY" "$ATLASSIAN_USER_NAME" "$ATLASSIAN_PASSWORD"
    fi
    
    # calculate next version
    TARGET_VERSION=$(GetTargetVersionForUpdate "$SOURCE_VERSION" "$TARGET_VERSION" "$sourceParentVersion" "$targetParentVersion")
	
	# write update instructions to queue
    echo "pomContent=\"\$(cat \"$POM_FOLDER/pom.xml\")\"" >> $UPDATE_QUEUE_FILE
    echo "newParent=\"<parent>\${pomContent#*<parent>}\"" >> $UPDATE_QUEUE_FILE
    echo "newParent=\"\${newParent%%</parent>*}</parent>\"" >> $UPDATE_QUEUE_FILE
    echo "newParent=\$(echo \"\$newParent\" | sed -e \"s~<version>$sourceParentVersion</version>~<version>$targetParentVersion</version>~g\")" >> $UPDATE_QUEUE_FILE
    echo "rm -f \"$POM_FOLDER/pom.xml\"" >> $UPDATE_QUEUE_FILE
    echo "echo \"\${pomContent%%<parent>*}\$newParent\${pomContent#*</parent>}\" >> \"$POM_FOLDER/pom.xml\"" >> $UPDATE_QUEUE_FILE

	# write sub task description and commit message
    SUB_TASK_DESCRIPTION="$SUB_TASK_DESCRIPTION \\n- Updated *parent-pom* version to *$targetParentVersion*"
    echo "Updated parent-pom version to $targetParentVersion." >> $COMMIT_DESCRIPTION_FILE
  fi
}


# FUNCTION FOR QUEUEING A PROPERTY UPDATE OF A PROJECT
QueuePropertyUpdate(){
  local targetPropertyName="$1"
  local targetPropertyVersion="$2"
  
  local sourcePropertyVersion
  sourcePropertyVersion=$(cat "$POM_FOLDER/pom.xml" | grep -oP "(?<=\<$targetPropertyName\>)[^\<]*")
  
  if $(IsMavenVersionHigher "$targetPropertyVersion" "$sourcePropertyVersion"); then
    echo "Queueing to update <$targetPropertyName> property of $ARTIFACT_ID from $sourcePropertyVersion to $targetPropertyVersion" >&2
  
    # create main task if does not exist
    if [ -z "$JIRA_KEY" ]; then
      JIRA_KEY=$(CreateJiraTicket \
	    "Update Harvester Maven Versions" \
        "The versions of Harvester Maven libraries and projects are to be updated." \
        "$ATLASSIAN_USER_NAME" \
        "$ATLASSIAN_PASSWORD")
      AddJiraTicketToCurrentSprint "$JIRA_KEY" "$ATLASSIAN_USER_NAME" "$ATLASSIAN_PASSWORD"
      StartJiraTask "$JIRA_KEY" "$ATLASSIAN_USER_NAME" "$ATLASSIAN_PASSWORD"
    fi
    
    # calculate next version
    TARGET_VERSION=$(GetTargetVersionForUpdate "$SOURCE_VERSION" "$TARGET_VERSION" "$sourcePropertyVersion" "$targetPropertyVersion")
    
	# write update instructions to queue
	echo "sed --in-place=.tmp -e \"s~<$targetPropertyName>$sourcePropertyVersion</$targetPropertyName>~<$targetPropertyName>$targetPropertyVersion</$targetPropertyName>~g\" $POM_FOLDER/pom.xml && rm -f $POM_FOLDER/pom.xml.tmp" >> $UPDATE_QUEUE_FILE
    
	# write sub task description and commit message
	SUB_TASK_DESCRIPTION="$SUB_TASK_DESCRIPTION \\n- Updated *<$targetPropertyName>* property to *$targetPropertyVersion*"
    echo "Updated $targetPropertyName property to $targetPropertyVersion." >> $COMMIT_DESCRIPTION_FILE
  fi
}


# FUNCTION FOR INITIALIZING A VERSION UPDATE FOR A PROJECT
PrepareUpdate() {
  PROJECT="$1"
  SLUG="$2"
  POM_FOLDER="$TOP_FOLDER/tempDir/$3"
  
  cd "$TOP_FOLDER"

  # create new file for the update queue shell script  
  UPDATE_QUEUE_FILE="$TOP_FOLDER/updateQueue.sh"
  rm -f $UPDATE_QUEUE_FILE
  touch $UPDATE_QUEUE_FILE
  chmod +x $UPDATE_QUEUE_FILE
  
  # create a new file for the git commit message
  COMMIT_DESCRIPTION_FILE="$TOP_FOLDER/gitCommitDescription.txt"
  rm -f $COMMIT_DESCRIPTION_FILE
  touch $COMMIT_DESCRIPTION_FILE
  echo " " >> $COMMIT_DESCRIPTION_FILE # add first new-line
  
  # create a variable for the jira sub-task description
  SUB_TASK_DESCRIPTION=""
  
  # remove and (re-)create a temporary folder
  rm -rf tempDir
  mkdir tempDir
  cd tempDir
  
  # clone JsonLibraries
  CloneGitRepository "$ATLASSIAN_USER_NAME" "$ATLASSIAN_PASSWORD" "$PROJECT" "$SLUG"
  
  # checkout branch
  git checkout "$SOURCE_BRANCH"
  
  # get version from pom
  if [ -f "$POM_FOLDER/pom.xml" ]; then
    ARTIFACT_ID=$(GetPomValue "project.artifactId" "$POM_FOLDER/pom.xml") 
	echo "ArtifactId: $ARTIFACT_ID" >&2
    SOURCE_VERSION=$(GetPomValue "project.version" "$POM_FOLDER/pom.xml")
	echo "Current version: $SOURCE_VERSION" >&2
    TARGET_VERSION="$SOURCE_VERSION"
  else
    # if no pom.xml exists, we cannot update it
	echo "Cannot update '$PROJECT/$SLUG' because the pom.xml is missing!" >&2
    ARTIFACT_ID=""
	SOURCE_VERSION=""
	TARGET_VERSION=""
  fi
}


# FUNCTION FOR EXECUTING ALL QUEUED UPDATES AND COMMITTING THE CHANGES
ExecuteUpdate() {
  local atlassianUserEmail="$1"
  local atlassianUserDisplayName="$2"
  local reviewer="$3"
  
  if [ "$SOURCE_VERSION" != "$TARGET_VERSION" ]; then
    echo "Will update $ARTIFACT_ID from $SOURCE_VERSION to $TARGET_VERSION" >&2
  
    # create sub-task
	local subTaskKey
    subTaskKey=$(CreateJiraSubTask \
	  "$JIRA_KEY" \
	  "Update $ARTIFACT_ID to Version $TARGET_VERSION" \
      'The Maven version of '"$ARTIFACT_ID"' needs to be updated to version '"$TARGET_VERSION"'.\n\n\n*Details:*\n'"$SUB_TASK_DESCRIPTION" \
	  "$ATLASSIAN_USER_NAME" \
	  "$ATLASSIAN_PASSWORD")
	  
	# start sub-task
    StartJiraTask "$subTaskKey" "$ATLASSIAN_USER_NAME" "$ATLASSIAN_PASSWORD"
  
    # create git branch
    BRANCH_NAME="versionUpdate/$JIRA_KEY-$subTaskKey-VersionUpdate"
	CreateBranch "$BRANCH_NAME"
    
    # execute update queue
    echo -e $($UPDATE_QUEUE_FILE) >&2
   
    # set version
    echo -e $(mvn versions:set "-DnewVersion=$TARGET_VERSION" -DallowSnapshots=true -DgenerateBackupPoms=false -f"$POM_FOLDER/pom.xml") >&2
    
	# commit and push updates
    commitMessage="$JIRA_KEY $subTaskKey Updated pom.xml version to $TARGET_VERSION. $(cat $COMMIT_DESCRIPTION_FILE)"
	echo -e $(PushAllFilesToGitRepository "$atlassianUserDisplayName" "$atlassianUserEmail" "$commitMessage") >&2
  
    # create pull request if it is not major version update
    isMajorUpdate=$(IsMajorVersionDifferent "$SOURCE_VERSION" "$TARGET_VERSION")
    if ! $isMajorUpdate; then
      echo $(CreatePullRequest \
        "$ATLASSIAN_USER_NAME" \
        "$ATLASSIAN_PASSWORD" \
        "$PROJECT" \
        "$SLUG" \
	    "$BRANCH_NAME" \
        "$SOURCE_BRANCH" \
        "Update $ARTIFACT_ID" \
        "Maven version update." \
        "$reviewer" \
        "") >&2
      ReviewJiraTask "$subTaskKey" "$ATLASSIAN_USER_NAME" "$ATLASSIAN_PASSWORD"
      FinishJiraTask "$subTaskKey" "$ATLASSIAN_USER_NAME" "$ATLASSIAN_PASSWORD"
    else
	  echo "Could not close JIRA task, because the major version changed! Please check the code!" >&2
    fi
  else
    echo "$ARTIFACT_ID is already up-to-date at version: $TARGET_VERSION" >&2
  fi
}


# FUNCTION THAT UPDATES THE PARENT POM OF ALL HARVESTERS
UpdateAllHarvesters() {
  local newParentVersion="$1"
  local atlassianUserEmail="$2"
  local atlassianUserDisplayName="$3"
  local reviewer="$4"
  
  echo "Trying to update all Harvesters to parent version $newParentVersion!" >&2
  
  local updateArguments
  updateArguments=$(curl -sX GET -u "$ATLASSIAN_USER_NAME:$ATLASSIAN_PASSWORD" https://code.gerdi-project.de/rest/api/latest/projects/HAR/repos \
  | python -m json.tool \
  | grep -oE '"http.*?git"' \
  | sed -e "s~\"http.*@\(.*\)\"~'\\1' '$newParentVersion' '$atlassianUserEmail' '$atlassianUserDisplayName' '$reviewer'~")

  # execute update of all harvesters
  while read arguments
  do 
    eval UpdateHarvester "$arguments"
  done <<< "$(echo -e "$updateArguments")"
}


# FUNCTION THAT UPDATES A SINGLE HARVESTER'S PARENT POM
UpdateHarvester() {
  local cloneLink="$1"
  local newParentVersion="$2"
  local atlassianUserEmail="$3"
  local atlassianUserDisplayName="$4"
  local reviewer="$5"
  
  local projectId="HAR"
  local slug=$(GetRepositorySlugFromCloneLink "$cloneLink")
  
  if $(IsOaiPmhHarvesterRepository "$projectId" "$slug" "$ATLASSIAN_USER_NAME" "$ATLASSIAN_PASSWORD") ; then
    echo "Postponing update of $projectId/$slug, because it is not an OAI-PMH harvester." >&2
	
  else
    PrepareUpdate "$projectId" "$slug" "."
    if [ -n "$SOURCE_VERSION" ]; then
      QueueParentPomUpdate "$newParentVersion"
      ExecuteUpdate "$atlassianUserEmail" "$atlassianUserDisplayName" "$reviewer"
	
	  if [ "$SLUG" = "oai-pmh" ]; then
	    OAIPMH_VERSION="$TARGET_VERSION"
	  fi
    fi
  fi
}


# FUNCTION FOR BUILDING AND DEPLOYING A HARVESTER RELATED LIBRARY VIA THE BAMBOO REST API
BuildAndDeployLibrary() {  
  local planLabel="$1"
  
  local isVersionAlreadyBuilt
  isVersionAlreadyBuilt=$(IsMavenVersionDeployed "$ARTIFACT_ID" "$TARGET_VERSION")
  
  if [ "$isVersionAlreadyBuilt" = true ]; then
    echo "Did not deploy $ARTIFACT_ID $TARGET_VERSION, because it already exists in the Sonatype repository." >&2
	exit 0
  fi
  
  if ! $(echo "$TARGET_VERSION" | grep -q "\-SNAPSHOT" ); then
    echo "Cannot automatically deploy RELEASE versions, because it takes 15 minutes until they are accessible in the Maven Central repository!" >&2
	exit 1
  fi
  
  # get ID of deployment project
  local deploymentId
  deploymentId=$(GetDeploymentId "$planLabel" "$ATLASSIAN_USER_NAME" "$ATLASSIAN_PASSWORD")
  if [ -z "$deploymentId" ]; then exit 1; fi
  echo "deploymentId: $deploymentId" >&2
  
  # get ID of 'Maven Deploy' environment
  local environmentId
  environmentId=$(GetDeployEnvironmentId "$deploymentId" "Maven Snapshot" "$ATLASSIAN_USER_NAME" "$ATLASSIAN_PASSWORD")
  if [ -z "$environmentId" ]; then exit 1; fi
  echo "environmentId: $environmentId" >&2
       
  # get branch number of the plan
  local planBranchId
  planBranchId=$(GetPlanBranchId "$planLabel" "$BRANCH_NAME" "$ATLASSIAN_USER_NAME" "$ATLASSIAN_PASSWORD")
  if [ -z "$planBranchId" ]; then exit 1; fi
  echo "planLabel: $planLabel$planBranchId" >&2  

  local planResultKey
  planResultKey="$planLabel$planBranchId-2"
        
  # wait for plan to finish
  WaitForPlanToBeDone "$planResultKey" "$ATLASSIAN_USER_NAME" "$ATLASSIAN_PASSWORD"
     
  # start bamboo deployment
  local deploymentResultId
  deploymentResultId=$(StartBambooDeployment \
   "$deploymentId" \
   "$environmentId" \
   "$TARGET_VERSION($planResultKey)" \
   "$planResultKey" \
   "$ATLASSIAN_USER_NAME" \
   "$ATLASSIAN_PASSWORD")
        
  if [ -z "$deploymentResultId" ]; then exit 1; fi
  
  echo "deploymentResultId: $deploymentResultId" >&2
  WaitForDeploymentToBeDone "$deploymentResultId" "$ATLASSIAN_USER_NAME" "$ATLASSIAN_PASSWORD"
}


# The main function that is executed in this script
#
Main() {
  # check early exit conditions
  ExitIfNotLoggedIn
  ExitIfPlanVariableIsMissing "atlassianPassword"
  ExitIfPlanVariableIsMissing "reviewer"
  ExitIfPlanVariableIsMissing "branch"

  ATLASSIAN_USER_NAME=$(GetBambooUserName)
  ATLASSIAN_PASSWORD=$(GetValueOfPlanVariable "atlassianPassword")

  # test Atlassian credentials
  ExitIfAtlassianCredentialsWrong "$ATLASSIAN_USER_NAME" "$ATLASSIAN_PASSWORD"
  
  # get more Atlassian user details
  local atlassianUserEmail
  atlassianUserEmail=$(GetAtlassianUserEmailAddress "$ATLASSIAN_USER_NAME" "$ATLASSIAN_PASSWORD" "$ATLASSIAN_USER_NAME")
  
  local atlassianUserDisplayName
  atlassianUserDisplayName=$(GetAtlassianUserDisplayName "$ATLASSIAN_USER_NAME" "$ATLASSIAN_PASSWORD" "$ATLASSIAN_USER_NAME")
  
  # check pull-request reviewer
  local reviewer
  reviewer=$(GetValueOfPlanVariable reviewer)
  echo "Reviewer: $reviewer" >&2
  if [ "$reviewer" = "$ATLASSIAN_USER_NAME" ]; then
    echo "You cannot be a reviewer yourself! Please set the 'reviewer' variable to a proper value when running the plan customized!" >&2
    exit 1
  fi
  
  # init global variables
  SOURCE_BRANCH=$(GetValueOfPlanVariable branch)
  TOP_FOLDER=$(pwd)
  SOURCE_VERSION=""
  TARGET_VERSION=""
  ARTIFACT_ID=""
  JIRA_KEY=""
  SLUG=""
  SUB_TASK_DESCRIPTION=""
  COMMIT_DESCRIPTION_FILE=""
  UPDATE_QUEUE_FILE=""
  BRANCH_NAME=""
  PROJECT=""
  OAIPMH_VERSION=""

  # get parent pom version  
  local parentPomVersion
  parentPomVersion=$(GetPomValue "project.version" "parentPom/pom.xml")
  echo "ParentPom Version: $parentPomVersion" >&2

  # update harvester utils
  PrepareUpdate "HL" "harvesterutils" "."
  if [ -n "$SOURCE_VERSION" ]; then
    QueueParentPomUpdate "$parentPomVersion"
    ExecuteUpdate "$atlassianUserEmail" "$atlassianUserDisplayName" "$reviewer"
	local harvesterUtilsVersion="$TARGET_VERSION"
    if ! $(BuildAndDeployLibrary "CAHL-HU"); then
	  echo "DID NOT BUILD $ARTIFACT_ID $TARGET_VERSION !" >&2
	fi
  fi

  # update json library
  PrepareUpdate "HL" "jsonlibraries" "."
  if [ -n "$SOURCE_VERSION" ]; then
    QueueParentPomUpdate "$parentPomVersion"
    QueuePropertyUpdate "harvesterutils.dependency.version" "$harvesterUtilsVersion"
    ExecuteUpdate "$atlassianUserEmail" "$atlassianUserDisplayName" "$reviewer"
	local jsonLibVersion="$TARGET_VERSION"
    if ! $(BuildAndDeployLibrary "CAHL-JL"); then
	  echo "DID NOT BUILD $ARTIFACT_ID $TARGET_VERSION !" >&2
	fi
  fi

  # update harvester base library
  PrepareUpdate "HL" "harvesterbaselibrary" "."
  if [ -n "$SOURCE_VERSION" ]; then
    QueueParentPomUpdate "$parentPomVersion"
    QueuePropertyUpdate "gerdigson.dependency.version" "$jsonLibVersion"
    ExecuteUpdate "$atlassianUserEmail" "$atlassianUserDisplayName" "$reviewer"
    local harvesterLibVersion="$TARGET_VERSION"
    if ! $(BuildAndDeployLibrary "CAHL-HBL"); then
	  echo "DID NOT BUILD $ARTIFACT_ID $TARGET_VERSION !" >&2
	fi
  fi

  # update harvester parent pom
  PrepareUpdate "HL" "harvesterparentpom" "."
  if [ -n "$SOURCE_VERSION" ]; then
    QueueParentPomUpdate "$parentPomVersion"
    QueuePropertyUpdate "restfulharvester.dependency.version" "$harvesterLibVersion"
    QueuePropertyUpdate "harvesterutils.dependency.version" "$harvesterUtilsVersion"
    ExecuteUpdate "$atlassianUserEmail" "$atlassianUserDisplayName" "$reviewer"
    local harvesterParentPomVersion="$TARGET_VERSION"
    if ! $(BuildAndDeployLibrary "CAHL-HPP"); then
	  echo "DID NOT BUILD $ARTIFACT_ID $TARGET_VERSION !" >&2
	fi
  fi

  # update all other harvesters
  UpdateAllHarvesters "$harvesterParentPomVersion" "$atlassianUserEmail" "$atlassianUserDisplayName" "$reviewer"

  echo " " >&2

  if [ -n "$JIRA_KEY" ]; then
    ReviewJiraTask "$JIRA_KEY" "$ATLASSIAN_USER_NAME" "$ATLASSIAN_PASSWORD"
    echo "-------------------------------------------------" >&2
    echo "FINISHED UPDATING! PLEASE, CHECK THE JIRA TICKET:" >&2
    echo "https://tasks.gerdi-project.de/browse/$JIRA_KEY" >&2
    echo "-------------------------------------------------" >&2
  else
    echo "------------------------------" >&2
    echo "NO PROJECTS HAD TO BE UPDATED!" >&2
    echo "------------------------------" >&2
  fi

  echo " " >&2
  
  # update OAI-PMH harvesters
  ./scripts/plans/util/update-harvester-versions/update-oaipmh-harvester-versions_2.sh "$OAIPMH_VERSION" "$JIRA_KEY"
}


###########################
#  BEGINNING OF EXECUTION #
###########################

Main "$@"
