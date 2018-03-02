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

# This script offers helper functions that concern GeRDI Maven projects.


# Returns true if a specified version and artifact of a specified GeRDI Maven project exist in Sonatype or in Maven Central.
#  Arguments:
#  1 - the artifact identifier of the GeRDI Maven project
#  2 - the version of the GeRDI Maven project
#
IsMavenVersionDeployed() {
  artifactId="$1"
  version="$2"
  
  # check Ssonatype if it is a snapshot version
  if [ "${version%-SNAPSHOT}" != "$version" ]; then
    response=$(curl -sI -X HEAD https://oss.sonatype.org/content/repositories/snapshots/de/gerdi-project/$artifactId/$version/)
  else
    response=$(curl -sI -X HEAD http://central.maven.org/maven2/de/gerdi-project/$artifactId/$version/)
  fi
  
  httpCode=$(echo "$response" | grep -oP '(?<=HTTP/\d\.\d )\d+')
  if [ $httpCode -eq 200 ]; then
    echo true
  else
    echo false
  fi
}


# Returns the latest version of a specified GeRDI Maven project.
#  Arguments:
#  1 - the artifact identifier of the GeRDI Maven project
#  2 - if true, also the versions in the Sonatype repository are checked
#
GetLatestMavenVersion() {
  artifactId="$1"
  includeSnapshots="$2"
  
  releaseVersion=""
  metaData=$(curl -fsX GET http://central.maven.org/maven2/de/gerdi-project/$artifactId/maven-metadata.xml)
  if [ $? -eq 0 ]; then
    releaseVersion=${metaData%</versions>*}
    releaseVersion=${releaseVersion##*<version>}
    releaseVersion=${releaseVersion%</version>*}
  fi
  
  snapshotVersion=""
  if [ "$includeSnapshots" = true ]; then
    metaData=$(curl -fsX GET https://oss.sonatype.org/content/repositories/snapshots/de/gerdi-project/$artifactId/maven-metadata.xml)
    if [ $? -eq 0 ]; then
	  snapshotVersion=${metaData%</versions>*}
      snapshotVersion=${snapshotVersion##*<version>}
      snapshotVersion=${snapshotVersion%</version>*}
	fi
  fi
  
  if [ "$snapshotVersion" = "" ] || [ "$releaseVersion" \> "$snapshotVersion" ]; then
    echo "$releaseVersion"
  else  
    echo "$snapshotVersion"
  fi
}


# Creates a pom.xml that extends the GeRDI-harvester-setup project with either a specified or the latest version.
#  Arguments:
#  1 - a version of GeRDI-harvester-setup (optional)
#
CreateHarvesterSetupPom() {
  harvesterSetupVersion="$1"
  
  # get the latest version of the Harvester Parent Pom, if no version was specified
  if [ "$harvesterSetupVersion" = "" ]; then
    harvesterSetupVersion=$(GetLatestMavenVersion "GeRDI-harvester-setup" true)
  fi
  
  # create a basic pom.xml that will fetch the harvester setup
  echo "Creating temporary pom.xml for HarvesterSetup $harvesterSetupVersion" >&2
  
  # check if a pom.xml already exists
  if [ -e pom.xml ]; then
    echo "Could not create file '$PWD/pom.xml', because it already exists!" >&2
    exit 1
  fi
  
  echo '<project>
  <modelVersion>4.0.0</modelVersion>
  <parent>
    <groupId>de.gerdi-project</groupId>
    <artifactId>GeRDI-harvester-setup</artifactId>
    <version>'"$harvesterSetupVersion"'</version>
  </parent>
  <artifactId>temporary-harvester-setup</artifactId>
  <repositories>
    <repository>
      <id>Sonatype</id>
      <url>https://oss.sonatype.org/content/repositories/snapshots/</url>
    </repository>
  </repositories>
</project>' >> pom.xml

  echo "Successfully created file '$PWD/pom.xml'." >&2
}


# Creates a temporary credentials file and runs Bamboo Specs from a pom.xml,
# which creates Bamboo jobs.
#  Arguments:
#  1 - a Bamboo user name of a user that is allowed to create jobs
#  2 - the login password that belongs to argument 1
#
RunBambooSpecs() {
  userName="$1"
  password="$2"
  
  echo "Running Bamboo-Specs" >&2
  mvn -e compile -Dexec.args="'$userName' '$password'" 
  
  if [ $?  -ne 0 ]; then
    echo "Error creating Bamboo Jobs!" >&2
    exit 1
  fi
}