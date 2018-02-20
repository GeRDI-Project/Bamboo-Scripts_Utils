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
 

# FUNCTION FOR SETTING UP ATLASSIAN LOGIN CREDENTIALS
InitAtlassianUserDetails() {
  # check if user is logged in
  if [ "$bamboo_ManualBuildTriggerReason_userName" = "" ]; then
    echo "You need to be logged in to run this job!" >&2
    exit 1
  fi
  
  # get user name
  atlassianUserName="$bamboo_ManualBuildTriggerReason_userName"
  echo "UserName: $atlassianUserName" >&2
  
  # check if password is set
  if [ "$bamboo_atlassianPassword" = "" ]; then
    echo "You need to specify your Atlassian password by setting the 'atlassianPassword' plan variable when running the plan customized!" >&2
    exit 1
  fi
  
  # assemble username+password for Atlassian REST requests
  atlassianCredentials="$atlassianUserName:$bamboo_atlassianPassword"
  
  # assemble username+password for Git Clones
  gitCredentials="$(echo "$atlassianUserName" | sed -e "s/@/%40/g"):$bamboo_atlassianPassword"
  
  # check if password is valid
  response=$(curl -sI -X HEAD -u "$atlassianCredentials" https://code.gerdi-project.de/rest/api/latest/projects/)
  httpCode=$(echo "$response" | grep -oP '(?<=HTTP/\d\.\d )\d+')
  if [ "$httpCode" != "200" ]; then
    echo "The 'atlassianPassword' plan variable is incorrect for user '$atlassianUserName'." >&2
    exit 1
  fi
  
  # get user profile
  userProfile=$(curl -sX GET -u "$atlassianCredentials" https://tasks.gerdi-project.de/rest/api/2/user?username="$atlassianUserName")
  
  # retrieve email from user profile
  atlassianUserEmail=$(echo "$userProfile" | grep -oP "(?<=\"emailAddress\":\")[^\"]+")
  echo "UserEmail: $atlassianUserEmail" >&2
  
  # retrieve displayName from user profile
  atlassianUserDisplayName=$(echo "$userProfile" | grep -oP "(?<=\"displayName\":\")[^\"]+")
  echo "UserDisplayName: $atlassianUserDisplayName" >&2
}


# FUNCTION FOR INITIALIZING GLOBAL SCRIPT VARIABLES
InitVariables() {
  InitAtlassianUserDetails

  overwriteFlag="$bamboo_replacePlans"

  repositoryUrl="$bamboo_gitCloneLink"
  if [ "$repositoryUrl" = "" ]; then
    echo "You need to specify a clone link of an existing harvester repository!"
    exit 1
  fi

  # retrieve Project ID from repository URL
  projectAbbrev=${repositoryUrl%/*}
  projectAbbrev=${projectAbbrev##*/}
  echo "Bitbucket Project: '$projectAbbrev'" >&2

  # retrieve Repository Slug from repository URL
  repositorySlug=${repositoryUrl##*/}
  repositorySlug=${repositorySlug%.git}
  echo "Slug: '$repositorySlug'" >&2
}


# FUNCTION FOR RETRIEVING THE LATEST VERSION OF A GERDI MAVEN PROJECT
GetGerdiMavenVersion () {
  metaData=$(curl -sX GET https://oss.sonatype.org/content/repositories/snapshots/de/gerdi-project/$1/maven-metadata.xml)
  ver=${metaData#*<latest>}
  ver=${ver%</latest>*}
  if [ "$ver" = "$metaData" ]; then
    ver=${metaData##*<version>}
    ver=${ver%</version>*}
  fi
  echo "$ver"
}



#############################
# START OF SCRIPT EXECUTION #
#############################

# create global variables
InitVariables

# clear, create and navigate to a temporary folder
echo "Setting up a temporary folder"
rm -fr harvesterSetupTemp
mkdir harvesterSetupTemp
cd harvesterSetupTemp

echo "Cloning repository code.gerdi-project.de/scm/$projectAbbrev/$repositorySlug.git"
cloneResponse=$(git clone -q https://"$gitCredentials"@code.gerdi-project.de/scm/$projectAbbrev/$repositorySlug.git .)
returnCode=$?
if [ $returnCode -ne 0 ]; then
  echo "Could not clone GIT repository!"
  exit 1
fi

# get class name of the provider
providerClassName=$(ls src/main/java/de/gerdiproject/harvest/*ContextListener.java)
providerClassName=${providerClassName%ContextListener.java}
providerClassName=${providerClassName##*/}
echo "Provider Class Name: '$providerClassName'"

# check if such plans already exist and should be overridden
if [ "$overwriteFlag" != "true" ] && [ "$overwriteFlag" != "yes" ] && [ "$overwriteFlag" != "1" ]; then
  planKey=$( echo "$providerClassName" | sed -e "s~[a-z]~~g")HAR
  doPlansExist=0
  
  echo "Checking Bamboo Plans"

  response=$(curl -sX GET -u "$atlassianCredentials" https://ci.gerdi-project.de/browse/CA-$planKey)
  cutResponse=${response%<title>Bamboo error reporting - GeRDI Bamboo</title>*}
  if [ "$response" != "" ] && [ "$cutResponse" = "$response" ]; then
    doPlansExist=1
  fi

  if [ $doPlansExist -ne 0 ]; then
    echo "Plans with the key '$planKey' already exist!"
    exit 1
  fi
else
  echo "Overriding any existing plans"
fi

# get the latest version of the Harvester Parent Pom
harvesterSetupVersion=$(GetGerdiMavenVersion "GeRDI-harvester-setup")
echo "Latest version of the HarvesterSetup is: $harvesterSetupVersion"

# create a basic pom.xml that will fetch the harvester setup
mv pom.xml backup-pom.xml
echo "Creating temporary pom.xml"
echo "<project>" >> pom.xml
echo " <modelVersion>4.0.0</modelVersion>" >> pom.xml
echo " <parent>" >> pom.xml
echo "  <groupId>de.gerdi-project</groupId>" >> pom.xml
echo "  <artifactId>GeRDI-harvester-setup</artifactId>" >> pom.xml
echo "  <version>$harvesterSetupVersion</version>" >> pom.xml
echo " </parent>" >> pom.xml
echo " <artifactId>temporary-harvester-setup</artifactId>" >> pom.xml
echo " <repositories>" >> pom.xml
echo "  <repository>" >> pom.xml
echo "   <id>Sonatype</id>" >> pom.xml
echo "   <url>https://oss.sonatype.org/content/repositories/snapshots/</url>" >> pom.xml
echo "  </repository>" >> pom.xml
echo " </repositories>" >> pom.xml
echo "</project>" >> pom.xml

# retrieve and unpack the harvester setup files
echo "Generating harvester setup files"
response=$(mvn generate-resources -Psetup)
returnCode=$?
if [ $returnCode -ne 0 ]; then
  echo "$response"
  echo "Could not generate Maven resources!"
  exit 1
fi

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

# restore old pom 
mv -f backup-pom.xml pom.xml

echo "Creating temporary Bamboo-Specs credentials"
cd bamboo-specs
touch .credentials
echo "username=$atlassianUserName" >> .credentials
echo "password=$bamboo_atlassianPassword" >> .credentials

echo "Running Bamboo-Specs"
mvn -Ppublish-specs

# clean up
echo "Removing the temporary directory"
cd ../
rm -fr harvesterSetupTemp