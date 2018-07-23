#!/bin/bash

#
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
#


#######################################################################################################################
#
# SYNOPSIS
#	initiate-hotfix-release.sh
#
# DESCRIPTION
# 	This script is called by a Bamboo Job.
#	It increments the bugfix number of STAGING_VERSION
#
#	That number is later used for the Staging Environment and also
#	when stage is merged into production.
#
# EXPECTED BAMBOO PLAN VARIABLES
#	ManualBuildTriggerReason_userName: login name of the current user
#	atlassianPassword                : Atlassian password of the current user
#
# EXPECTED GLOBAL BAMBOO VARIABLES
#	STAGING_VERSION
#
#######################################################################################################################

# treat unset variables as an error when substituting
set -u


#######################################################################################################################
# IMPORTS
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

	# get and verify Atlassian credentials
	local ATLASSIAN_USER_NAME=$(GetBambooUserName)
	local ATLASSIAN_PASSWORD=$(GetValueOfPlanVariable "atlassianPassword")
	ExitIfAtlassianCredentialsWrong "$ATLASSIAN_USER_NAME" "$ATLASSIAN_PASSWORD"


	#
	# Increment bugfix version of STAGING_VERSION
	#
	local newStagingVersion=$(IncrementVersion bugfix ${bamboo_STAGING_VERSION:-0.0.0})
	SetGlobalVariable  STAGING_VERSION "$newStagingVersion" "$ATLASSIAN_USER_NAME" "$ATLASSIAN_PASSWORD" >&2
}


#######################################################################################################################
#  BEGINNING OF EXECUTION 
#######################################################################################################################

Main "$@"
