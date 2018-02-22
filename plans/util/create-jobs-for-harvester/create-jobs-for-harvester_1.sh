#!/bin/bash

# Licensed to the Apache Software Foundation (ASF) under one
# or more contributor license agreements.  See the NOTICE file
# distributed with this work for additional information
# regarding copyright ownership.  The ASF licenses this file
# to you under the Apache License, Version 2.0 (the
# "License"); you may not use this file except in compliance
# with the License.  You may obtain a copy of the License at
#
#   http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing,
# software distributed under the License is distributed on an
# "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY
# KIND, either express or implied.  See the License for the
# specific language governing permissions and limitations
# under the License.

# This script is being called by the Bamboo Job https://ci.gerdi-project.de/browse/UTIL-CHPL which creates/overwrites
# Bamboo jobs for an existing harvester project.
#
# Bamboo Plan Variables:
#  ManualBuildTriggerReason_userName - the login name of the current user
#  atlassianPassword - the Atlassian password of the current user
#  gitCloneLink - the clone link of a git repository
#  overwriteExistingJobs - if true, overwrites jobs if they already exist for the harvester

# load helper scripts
source scripts/helper-scripts/atlassian-utils.sh
source scripts/helper-scripts/bamboo-utils.sh
source scripts/helper-scripts/git-utils.sh
source scripts/helper-scripts/maven-utils.sh
source scripts/helper-scripts/misc-utils.sh

# check early exit conditions
ExitIfNotLoggedIn
ExitIfPlanVariableIsMissing "atlassianPassword"
ExitIfPlanVariableIsMissing "gitCloneLink"

atlassianUserName=$(GetBambooUserName)
atlassianPassword=$(GetValueOfPlanVariable "atlassianPassword")

# test Atlassian credentials
ExitIfAtlassianCredentialsWrong "$atlassianUserName" "$atlassianPassword"

# retrieve plan variables
overwriteFlag=$(GetValueOfPlanVariable overwriteExistingJobs)
gitCloneLink=$(GetValueOfPlanVariable gitCloneLink)

projectAbbrev=$(GetProjectIdFromCloneLink "$gitCloneLink")
echo "Bitbucket Project: '$projectAbbrev'" >&2

repositorySlug=$(GetRepositorySlugFromCloneLink "$gitCloneLink")
echo "Slug: '$repositorySlug'" >&2

# clear, create and navigate to a temporary folder
echo "Setting up a temporary folder" >&2
rm -fr harvesterSetupTemp
mkdir harvesterSetupTemp
cd harvesterSetupTemp

# clone newly created repository
CloneGitRepository "$atlassianUserName" "$atlassianPassword" "$projectAbbrev" "$repositorySlug"

# get class name of the provider
providerClassName=$(ls src/main/java/de/gerdiproject/harvest/*ContextListener.java)
providerClassName=${providerClassName%ContextListener.java}
providerClassName=${providerClassName##*/}
echo "Provider Class Name: '$providerClassName'" >&2

# check if Bamboo plans already exist and should be overridden
planKey="$( echo "$providerClassName" | sed -e "s~[a-z]~~g")HAR"
doPlansExist=$(IsUrlReachable "https://ci.gerdi-project.de/rest/api/latest/plan/CA-$planKey" "$atlassianUserName" "$atlassianPassword")

if [ "$doPlansExist" = true ]; then
  if [ "$overwriteFlag" = true ]; then
    echo "Overriding existing Bamboo jobs!" >&2
  else
    echo "Plans with the key '$planKey' already exist!" >&2
    exit 1
  fi
fi

# back up existing pom.xml
mv pom.xml backup-pom.xml

# create a setup pom.xml in cloned repository directory
CreateHarvesterSetupPom

# retrieve and unpack the harvester setup files
echo "Generating harvester setup files"
mvn generate-resources -Psetup
ExitIfLastOperationFailed "Could not generate Maven resources!"

# rename placeholders for the unpacked files
chmod o+rw scripts/renameSetup.sh
chmod +x scripts/renameSetup.sh
./scripts/renameSetup.sh\
 "$providerClassName"\
 "XXX"\
 "XXX"\
 "XXX"\
 "XXX"\
 "XXX"\
 "XXX"

# restore backed up pom.xml
mv -f backup-pom.xml pom.xml

# create Bamboo jobs
cd bamboo-specs
CreateBambooSpecs "$atlassianUserName" "$atlassianPassword"

# clean up temporary folder
echo "Removing the temporary directory"
cd ../
rm -fr harvesterSetupTemp