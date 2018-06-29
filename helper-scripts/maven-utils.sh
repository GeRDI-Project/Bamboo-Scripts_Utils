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

mavenExecVersion="1.6.0"
  
# Returns true if a specified version and artifact of a specified GeRDI Maven project exist in Sonatype or in Maven Central.
#  Arguments:
#  1 - the artifact identifier of the GeRDI Maven project
#  2 - the version of the GeRDI Maven project
#
IsMavenVersionDeployed() {
  artifactId="$1"
  version="$2"
  
  # check Sonatype if it is a snapshot version
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


# Returns a specified value of a pom.xml.
#  Arguments:
#  1 - the path to the tag of which the value is retrieved (e.g. project.version)
#  2 - the path to the pom.xml (optional)
#
GetPomValue() {
  valueKey="$1"
  pomPath="$2"
  
  if [ "$pomPath" = "" ]; then
    echo $(mvn -q -Dexec.executable="echo" -Dexec.args='${'"$valueKey"'}' --non-recursive org.codehaus.mojo:exec-maven-plugin:$mavenExecVersion:exec)
  else
    echo $(mvn -q -Dexec.executable="echo" -Dexec.args='${'"$valueKey"'}' --non-recursive org.codehaus.mojo:exec-maven-plugin:$mavenExecVersion:exec -f"$pomPath")
  fi
}