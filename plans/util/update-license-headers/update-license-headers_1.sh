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
 
# This script is being called by the Bamboo Job https://ci.gerdi-project.de/browse/UTIL-ULH.
# It iterates through all Harvester Projects and updates their license headers using the 'addLicenses' helper script
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

# FUNCTION THAT UPDATES THE LICENSE HEADERS OF ALL HARVESTERS
UpdateAllLicenseHeaders() {
  
  # grep harvester clone URLs, and convert them to batch instructions
  cloneLinks=$(curl -sX GET -u "$atlassianUserName:$atlassianPassword" https://code.gerdi-project.de/rest/api/latest/projects/HAR/repos \
  | python -m json.tool \
  | grep -oE '"http.*?git"' \
  | sed -e "s~\"http.*@\(.*\)\"~\\1~")

  echo -e "Checking the following repositories:\n$cloneLinks\n" >&2
  
  # execute update of all harvesters
  while read cloneLink
  do
    echo "Checking project: $cloneLink"
    UpdateLicenseHeadersOfProject "$cloneLink"
  done <<< "$(echo -e "$cloneLinks")"
  
  # clean up temporary folder
  cd "$topDir"
  rm -rf "$tempDir"
}


# FUNCTION THAT UPDATES A SINGLE HARVESTER'S PARENT POM
UpdateLicenseHeadersOfProject() {
  cloneLink="$1"

  repositorySlug=$(GetRepositorySlugFromCloneLink "$cloneLink")
  projectId=$(GetProjectIdFromCloneLink "$cloneLink")

  cd "$topDir"

  # remove and (re-)create a temporary folder
  rm -rf "$tempDir"
  tempDir=$(mktemp -d)
  cd "$tempDir"

  # clone repository
  CloneGitRepository "$atlassianUserName" "$atlassianPassword" "$projectId" "$repositorySlug"

  # check if a pom XML with the correct parent exists
  if [ ! -f "pom.xml" ]; then
    echo "Cannot update $projectId/$repositorySlug, because it is missing a pom.xml" >&2

  elif [ "$(GetPomValue "project.parent.artifactId" "")" != "GeRDI-parent-harvester" ]; then
    echo "Skipping $projectId/$repositorySlug, because the parent pom is not GeRDI-parent-harvester." >&2
	
  elif [ "$(GetPomValue "project.parent.version" "")" \< "6.2.0-SNAPSHOT" ]; then
    echo "Cannot update $projectId/$repositorySlug. The parent pom must be 'GeRDI-parent-harvester' of version '6.2.0-SNAPSHOT' or higher!" >&2

  else
    # generate maven resources
    mvn generate-resources

    # execute script for updating license headers
    $(./scripts/addLicenses.sh)

    # continue if the script was successful
    if [ $? -eq 0 ]; then
      PushLicenseHeaderUpdate "$projectId" "$repositorySlug"
	else
	  echo "Could not add license headers to $projectId/$repositorySlug!" >&2
    fi
  fi
}


# FUNCTION FOR ATTEMPTING TO PUSH A LICENSE HEADER UPDATE
PushLicenseHeaderUpdate() { 
  projectId="$1" 
  repositorySlug="$2"
  if [ $(GetNumberOfUnstagedChanges) -ne 0 ]; then
    echo "License headers of $projectId/$repositorySlug need to be updated!" >&2
	
	# create JIRA ticket, if needed
	if [ "$jiraKey" = "" ]; then 
 	  jiraKey=""$(CreateJiraTicket \
	    "Update Harvester License Headers" \
        "The license headers of some harvester projects are to be updated." \
        "$atlassianUserName" \
        "$atlassianPassword")
      AddJiraTicketToCurrentSprint "$jiraKey" "$atlassianUserName" "$atlassianPassword"
      StartJiraTask "$jiraKey" "$atlassianUserName" "$atlassianPassword"
    fi
	
    # create sub-task
    subTaskKey=$(CreateJiraSubTask \
	  "$jiraKey" \
	  "Add license headers to $projectId/$repositorySlug" \
      "The license headers of $repositorySlug need to be updated and/or added." \
	  "$atlassianUserName" \
	  "$atlassianPassword")
	  
	# start sub-task
    StartJiraTask "$subTaskKey" "$atlassianUserName" "$atlassianPassword"
  
    # create git branch
    branchName="$jiraKey-$subTaskKey-UpdateLicenseHeaders"
	CreateBranch "$branchName"
    
	# commit and push updates
    commitMessage="$jiraKey $subTaskKey Updated license headers."
	echo $(PushAllFilesToGitRepository "$atlassianUserDisplayName" "$atlassianUserEmail" "$commitMessage") >&2
  
    # create pull request
      echo $(CreatePullRequest \
        "$atlassianUserName" \
        "$atlassianPassword" \
		"$projectId" \
        "$repositorySlug" \
	    "$branchName" \
        "$repositorySlug Update License Headers" \
        "Updated and/or added license headers." \
        "$reviewer1" \
        "") >&2
      ReviewJiraTask "$subTaskKey" "$atlassianUserName" "$atlassianPassword"
      FinishJiraTask "$subTaskKey" "$atlassianUserName" "$atlassianPassword"
  else
    echo "All headers of $projectId/$repositorySlug are up-to-date!" >&2
  fi
}


###########################
#  BEGINNING OF EXECUTION #
###########################

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
jiraKey=""
tempDir=""
topDir="$PWD"

# fire in the hole!
UpdateAllLicenseHeaders

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