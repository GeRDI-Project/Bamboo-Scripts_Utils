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


# FUNCTION FOR RETRIEVING THE LATEST VERSION OF A GERDI MAVEN PROJECT
GetGerdiMavenVersion () {
  metaData=$(curl -sX GET https://oss.sonatype.org/content/repositories/snapshots/de/gerdi-project/$1/maven-metadata.xml)
  ver=${metaData%</versions>*}
  ver=${ver##*<version>}
  ver=${ver%</version>*}
  echo "$ver"
}


# FUNCTION FOR CHECKING IF A VERSION IS IN SONATYPE
IsMavenVersionInSonatype() {
  checkedArtifactId="$1"
  checkedVersion="$2"
  
  response=$(curl -sI -X HEAD https://oss.sonatype.org/content/repositories/snapshots/de/gerdi-project/$checkedArtifactId/$checkedVersion/)
  httpCode=$(echo "$response" | grep -oP '(?<=HTTP/\d\.\d )\d+')
  if [ $httpCode -eq 200 ]; then
    echo true
  else
    echo false
  fi
}


CreateHarvesterSetupPom () {
  harvesterSetupVersion="$1"
  
  # get the latest version of the Harvester Parent Pom, if no version was specified
  if [ "$harvesterSetupVersion" = "" ]; then
    harvesterSetupVersion=$(GetGerdiMavenVersion "GeRDI-harvester-setup")
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

  exit 0
}


RunBambooSpecs() {
  userName="$1"
  password="$2"
  
  echo "Creating Bamboo-Specs credentials file" >&2

  touch .credentials
  echo "username=$userName" >> .credentials
  echo "password=$password" >> .credentials

  echo "Running Bamboo-Specs" >&2
  mvn -Ppublish-specs
  
  if [ $?  -ne 0 ]; then
    echo "Could not create Bamboo Jobs!" >&2
    exit 1
  fi
  
  rm -f .credentials
}