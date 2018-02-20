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


# FUNCTION FOR RETRIEVING THE LATEST VERSION OF A GERDI MAVEN PROJECT
GetGerdiMavenVersion () {
  metaData=$(curl -sX GET https://oss.sonatype.org/content/repositories/snapshots/de/gerdi-project/$1/maven-metadata.xml)
  ver=${metaData%</versions>*}
  ver=${ver##*<version>}
  ver=${ver%</version>*}
  echo "$ver"
}



#############################
# START OF SCRIPT EXECUTION #
#############################

# set up global variables
InitAtlassianUserDetails

# check if all required variables exist
if [ "$bamboo_providerName" = "" ] \
|| [ "$bamboo_providerUrl" = "" ] \
|| [ "$bamboo_authorOrganization" = "" ] \
|| [ "$bamboo_authorOrganizationUrl" = "" ]
then
echo "Some Variables are missing! Make sure to fill out all variables and to run the plan customized!"
exit 1
fi

# create repository
response=$(curl -sX POST -u "$atlassianCredentials" -H "Content-Type: application/json" -d '{
    "name": "'"$bamboo_providerName"'",
    "scmId": "git",
    "forkable": true
}' https://code.gerdi-project.de/rest/api/1.0/projects/HAR/repos/)

# check for BitBucket errors
errorsPrefix="\{\"errors\""
if [ "${response%$errorsPrefix*}" = "" ]
then
echo "Could not create repository for the Harvester:"
echo "$response"
exit 1
fi

# retrieve the urlencoded repository name from the curl response
encodedRepositoryName="$response"
encodedRepositoryName=${encodedRepositoryName#*\{\"slug\":\"}
encodedRepositoryName=${encodedRepositoryName%%\"*}

echo "Created repository '$encodedRepositoryName'."

# clear, create and navigate to a temporary folder
echo "Setting up a temporary folder"
rm -fr harvesterSetupTemp
mkdir harvesterSetupTemp
cd harvesterSetupTemp

# clone newly created repository
echo "Cloning repository code.gerdi-project.de/scm/har/$encodedRepositoryName.git"
cloneResponse=$(git clone -q "https://$gitCredentials@code.gerdi-project.de/scm/har/$encodedRepositoryName.git")
returnCode=$?
if [ $returnCode -ne 0 ]; then
 echo "Could not clone GIT repository!"
 exit 1
fi
cd $encodedRepositoryName

# get the latest version of the Harvester Parent Pom
harvesterSetupVersion=$(GetGerdiMavenVersion "GeRDI-harvester-setup")
echo "Latest version of the HarvesterSetup is: $harvesterSetupVersion"

# create a basic pom.xml that will fetch the harvester setup
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

# get the latest version of the Harvester Parent Pom
parentPomVersion=$(GetGerdiMavenVersion "GeRDI-parent-harvester")
echo "Latest version of the Harvester Parent Pom is: $parentPomVersion"

# rename placeholders for the unpacked files
chmod o+rw scripts/renameSetup.sh
chmod +x scripts/renameSetup.sh
./scripts/renameSetup.sh\
 "$bamboo_providerName"\
 "$bamboo_providerUrl"\
 "$atlassianUserDisplayName"\
 "$atlassianUserEmail"\
 "$bamboo_authorOrganization"\
 "$bamboo_authorOrganizationUrl"\
 "$parentPomVersion"
 
# check if bamboo plans already exist
providerClassName=$(ls src/main/java/de/gerdiproject/harvest/*ContextListener.java)
providerClassName=${providerClassName%ContextListener.java}
providerClassName=${providerClassName##*/}

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
  
  # delete repository
  response=$(curl -sX DELETE -u "$atlassianCredentials" https://code.gerdi-project.de/rest/api/1.0/projects/HAR/repos/$encodedRepositoryName)
  exit 1
fi
 
# run AStyle without changing the files
echo "Formatting files with AStyle"
astyleResult=$(astyle --options="/usr/lib/astyle/file/kr.ini" --recursive --formatted "src/*")

# commit and push all files
echo "Adding files to GIT"
git add -A ${PWD}

echo "Committing files to GIT"
git config user.email "$atlassianUserEmail"
git config user.name "$atlassianUserDisplayName"
git commit -m "Bamboo: Created harvester repository for the provider '$bamboo_providerName'."

echo "Pushing files to GIT"
git push -q


echo "Creating temporary Bamboo-Specs credentials"
cd bamboo-specs
touch .credentials
echo "username=$atlassianUserName" >> .credentials
echo "password=$bamboo_atlassianPassword" >> .credentials

echo "Running Bamboo-Specs"
mvn -Ppublish-specs

# clean up
echo "Removing the temporary directory"
cd ../../
rm -fr harvesterSetupTemp