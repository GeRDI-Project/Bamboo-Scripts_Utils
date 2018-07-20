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

# This script is being called by a Bamboo Job. It increments the minor version of the global Bamboo variable
# PRODUCTION_VERSION and merges all stage to production branches.
#
# Bamboo Plan Variables:
#  ManualBuildTriggerReason_userName - the login name of the current user
#  atlassianPassword - the Atlassian password of the current user
#  reviewer - the reviewer for the pull request

# treat unset variables as an error when substituting

#!/bin/bash

set -u

source ./scripts/helper-scripts/atlassian-utils.sh
source ./scripts/helper-scripts/bamboo-utils.sh
source ./scripts/helper-scripts/misc-utils.sh


# Main function that is executed by this script
#
# ONE OPTIONAL ARGUMENT can be given, which is used instead of incrementing
# the minor version of global TEST_VERSION (e. g. in case of a major release).
#
Main() {
	#
	# verify exected plan variables
	#
	ExitIfNotLoggedIn
	ExitIfPlanVariableIsMissing "atlassianPassword"
	ExitIfPlanVariableIsMissing "RELEASED_REPOSITORIES"
	ExitIfPlanVariableIsMissing "reviewer"

	# get and verify Atlassian credentials
	ATLASSIAN_USER_NAME=$(GetBambooUserName)
	ATLASSIAN_PASSWORD=$(GetValueOfPlanVariable "atlassianPassword")

	echo -----------------------------
	echo $bamboo_atlassianPassword
	echo -----------------------------
	echo $ATLASSIAN_USER_NAME
	x=$(GetValueOfPlanVariable "atlassianPassword")
	echo $x
	echo -----------------------------

	# ExitIfAtlassianCredentialsWrong "$ATLASSIAN_USER_NAME" "$ATLASSIAN_PASSWORD"


	#
	# Set STAGING_VERSION to TEST_VERSION and in increment minor version 
	# of TEST_VERSION, unless a customTestVersion is given instead.
	#
	local currentTestVersion=${bamboo_TEST_VERSION:-0.0.0}

	bamboo_STAGING_VERSION=$currentTestVersion
	# SetGlobalVariable "STAGING_VERSION" "$currentTestVersion" "$ATLASSIAN_USER_NAME" "$ATLASSIAN_PASSWORD"

	if [ $# -eq 1 ]; then
		bamboo_TEST_VERSION="$1"
		# SetGlobalVariable "TEST_VERSION"    "$1"     "$ATLASSIAN_USER_NAME" "$ATLASSIAN_PASSWORD"
	else
		bamboo_TEST_VERSION=$(IncrementVersion minor $currentTestVersion) 
		# SetGlobalVariable "TEST_VERSION"    "$(IncrementVersion minor $currentTestVersion)"     "$ATLASSIAN_USER_NAME" "$ATLASSIAN_PASSWORD"
	fi


	#
	# Create a pull request for merging the master into the stage branch for the released repos
	#

	local title="Merge to Staging $bamboo_STAGING_VERSION"
	local description="All master branches are to be merged to stage for Feature Freeze $bamboo_STAGING_VERSION"
	local reviewer=$(GetValueOfPlanVariable reviewer)
	local projectsAndCloneLinks=$(GetValueOfPlanVariable "RELEASED_REPOSITORIES")

	#echo 
	#echo title: $title
	#echo description: $description
	#echo reviewer: $reviewer
	#echo projectsAndCloneLinks $projectsAndCloneLinks
	#echo 

	echo
	echo Versions at the end:
	echo STAGING_VERSION: $bamboo_STAGING_VERSION
	echo TEST_VERSION: $bamboo_TEST_VERSION
	echo

	exit 0

	./scripts/plans/releaseWorkflow/merge-branches.sh  \
		"$ATLASSIAN_USER_NAME"                          \
		"$ATLASSIAN_PASSWORD"                            \
		"master"                                          \
		"stage"                                            \
		"$bamboo_RELEASED_REPOSITORIES"                     \
		"$title"                                             \
		"$description"                                        \
		"$reviewer"
}


###########################
#  BEGINNING OF EXECUTION #
###########################

Main "$@"
