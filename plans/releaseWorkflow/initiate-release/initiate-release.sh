#!/bin/bash

# Copyright © 2018 Ingo Thomsen (http://www.gerdi-project.de/)
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


#######################################################################################################################
#
# SYNOPSIS
#	initiate-release.sh  [NewTestVersion]
#
# DESCRIPTION
# 	This script is called by a Bamboo Job.
#       Set the global STAGING_VERSION to value of TEST_VERSION. 
#	Then either increment the minor version of TEST_VERSION 
#       or set it to a an optional value (e. g. for a major release).
#       Go through all service repositories (as given by a global 
# 	variable) and merge the master into the stage branch.
#
# PARAMETER:
#	NewTestVersion (optional!)
#
# 	A specific new TEST_VERSION can be given, which is used instead 
#	of incrementing the minor version of global TEST_VERSION 
#	(e. g. in case of a major release).
#
# EXPECTED BAMBOO PLAN VARIABLES
#	ManualBuildTriggerReason_userName :  login name of the current user
#	atlassianPassword                 :  Atlassian password of current user
#	reviewer                          :  reviewer for the pull request
#
# EXPECTED GLOBAL BAMBOO VARIABLES
#	RELEASED_REPOSITORIES
#	STAGING_VERSION
#	TEST_VERSION
#
#######################################################################################################################


# treat unset variables as an error when substituting
set -u


#######################################################################################################################
#  IMPORTS        
#######################################################################################################################

source ./scripts/helper-scripts/atlassian-utils.sh
source ./scripts/helper-scripts/bamboo-utils.sh
source ./scripts/helper-scripts/misc-utils.sh


#######################################################################################################################
#  MAIN FUNCTION  
#######################################################################################################################

Main() {
	#
	# verify exected plan variables
	#
	ExitIfNotLoggedIn
	ExitIfPlanVariableIsMissing "atlassianPassword"
	ExitIfPlanVariableIsMissing "RELEASED_REPOSITORIES"
	ExitIfPlanVariableIsMissing "reviewer"

	# get and verify Atlassian credentials
	local ATLASSIAN_USER_NAME=$(GetBambooUserName)
	local ATLASSIAN_PASSWORD=$(GetValueOfPlanVariable "atlassianPassword")
	ExitIfAtlassianCredentialsWrong "$ATLASSIAN_USER_NAME" "$ATLASSIAN_PASSWORD"


	#
	# Set STAGING_VERSION to TEST_VERSION and increment minor version 
	# of TEST_VERSION, unless a customTestVersion was given as parameter.
	#
	local currentTestVersion=${bamboo_TEST_VERSION:-0.0.0}
	local newTestVersion
	[ $# -eq 1 ]  &&  newTestVersion="$1" || newTestVersion=$(IncrementVersion minor $currentTestVersion)

	SetGlobalVariable  STAGING_VERSION "$currentTestVersion" "$ATLASSIAN_USER_NAME" "$ATLASSIAN_PASSWORD" >&2
	SetGlobalVariable  TEST_VERSION    "$newTestVersion"     "$ATLASSIAN_USER_NAME" "$ATLASSIAN_PASSWORD" >&2


	#
	# Create a pull request for merging the master into the stage branch for the released repos
	#
	local title="Merge to Staging $bamboo_STAGING_VERSION"
	local description="All master branches are to be merged to stage for Feature Freeze $bamboo_STAGING_VERSION."
	local reviewer=$(GetValueOfPlanVariable reviewer)
	local projectsAndCloneLinks=$(GetValueOfPlanVariable "RELEASED_REPOSITORIES")

	./scripts/plans/releaseWorkflow/merge-branches.sh  \
		"$ATLASSIAN_USER_NAME"                      \
		"$ATLASSIAN_PASSWORD"                        \
		"master"                                      \
		"stage"                                        \
		"$bamboo_RELEASED_REPOSITORIES"                 \
		"$title"                                         \
		"$description"                                    \
		"$reviewer"
}



#######################################################################################################################
#  BEGINNING OF EXECUTION 
#######################################################################################################################

Main "$@"
