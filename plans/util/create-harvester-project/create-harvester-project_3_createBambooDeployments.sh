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

# This script is called by the Bamboo Job https://ci.gerdi-project.de/browse/UTIL-CHP.
# It runs the mavenized Bamboo-Specs of a specified directory.
#
# Arguments
#  1 - the path to the directory inside the 'harvesterSetupTemp' folder which contains a bamboo-specs pom.xml
#
# Bamboo Plan Variables:
#  ManualBuildTriggerReason_userName - the login name of the current user
#  atlassianPassword - the Atlassian password of the current user
#  providerName - the human readable name of the data provider that is to be harvested
#  providerUrl - the url to the data provider home page
#  authorOrganization - the organization of the harvester developer
#  authorOrganizationUrl - the url to the homepage of the harvester developer's organization
#  optionalAuthorName - the full name of the harvester developer, if not specified the executing user's name will be used
#  optionalAuthorEmail - the email address of the harvester developer, if not specified the executing user's email address will be used

# treat unset variables as an error when substituting
set -u

# get arguments
bambooSpecsDirectory="$1"

# load helper scripts
source ./scripts/helper-scripts/atlassian-utils.sh
source ./scripts/helper-scripts/bamboo-utils.sh
source ./scripts/helper-scripts/maven-utils.sh

# check early exit conditions
ExitIfNotLoggedIn
ExitIfPlanVariableIsMissing "atlassianPassword"

atlassianUserName=$(GetBambooUserName)
atlassianPassword=$(GetValueOfPlanVariable "atlassianPassword")

# test Atlassian credentials
ExitIfAtlassianCredentialsWrong "$atlassianUserName" "$atlassianPassword"

# navigate to the Bamboo Specs directory
cd harvesterSetupTemp/bamboo-specs/deployments

# create Bamboo deployment jobs
RunBambooSpecs "$atlassianUserName" "$atlassianPassword"