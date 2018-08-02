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


# Takes a path that may lead to either a directory or a pom.xml
# and returns a relative path that will definitely point to a pom.xml.
#
# Arguments:
#  1 - a file path to a pom.xml or a Maven project folder (default: current folder)
#
GetPomXmlPath() {
  local pomXmlPath="${1-}"
  
  if [ -z "$pomXmlPath" ] || [ "$pomXmlPath" = "." ]; then
    pomXmlPath="pom.xml"
  elif ! $(echo "$pomXmlPath" | grep -q "pom.xml\$"); then
    if ! $(echo "$pomXmlPath" | grep -q "/\$\|\\\\\$"); then
      pomXmlPath="$pomXmlPath/"
    fi
    pomXmlPath="$pomXmlPath""pom.xml"
  fi
  
  echo "$pomXmlPath"
}


# Checks if a pom.xml contains any -SNAPSHOT versions.
# Exits with 1 if no -SNAPSHOT versions could be found.
#
# Arguments:
#  1 - a file path to a pom.xml or a Maven project folder (default: current folder)
#
HasSnapshotVersions() {
  local pomXmlPath=$(GetPomXmlPath "${1-}")
  
  if [ ! -f "$pomXmlPath" ]; then
    echo "Cannot check SNAPSHOT versions of '$pomXmlPath' because the path does not exist!" >&2
    exit 1
  fi
  
  grep -qi "<\([a-z.]*\)>[0-9.]\+\-SNAPSHOT</\1>" "$pomXmlPath"
}


# Returns true if a specified version and artifact of a specified GeRDI Maven project exist in Sonatype or in Maven Central.
#  Arguments:
#  1 - the artifact identifier of the GeRDI Maven project
#  2 - the version of the GeRDI Maven project
#
IsMavenVersionDeployed() {
  local artifactId="$1"
  local version="$2"
  
  # check Sonatype if it is a snapshot version
  local response
  if [ "${version%-SNAPSHOT}" != "$version" ]; then
    response=$(curl -sI -X HEAD https://oss.sonatype.org/content/repositories/snapshots/de/gerdi-project/$artifactId/$version/)
  else
    response=$(curl -sI -X HEAD http://central.maven.org/maven2/de/gerdi-project/$artifactId/$version/)
  fi
  
  local httpCode
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
  local artifactId="$1"
  local includeSnapshots="$2"
  local metaData
  
  local releaseVersion=""
  metaData=$(curl -fsX GET http://central.maven.org/maven2/de/gerdi-project/$artifactId/maven-metadata.xml)
  if [ $? -eq 0 ]; then
    releaseVersion=${metaData%</versions>*}
    releaseVersion=${releaseVersion##*<version>}
    releaseVersion=${releaseVersion%</version>*}
  fi
  
  local snapshotVersion=""
  if [ "$includeSnapshots" = true ]; then
    metaData=$(curl -fsX GET https://oss.sonatype.org/content/repositories/snapshots/de/gerdi-project/$artifactId/maven-metadata.xml)
    if [ $? -eq 0 ]; then
	    snapshotVersion=${metaData%</versions>*}
      snapshotVersion=${snapshotVersion##*<version>}
      snapshotVersion=${snapshotVersion%</version>*}
	  fi
  fi
  
  if [ -z "$snapshotVersion" ] || [ "$releaseVersion" \> "$snapshotVersion" ]; then
    echo "$releaseVersion"
  else  
    echo "$snapshotVersion"
  fi
}


# Checks if one maven version is higher than another and exits with 1 if it is not.
#  Arguments:
#  1 - the supposedly higher version
#  2 - the supposedly older version
#
IsMavenVersionHigher() {
  local newVersion="$1"
  local oldVersion="$2"
  
  local oldPrefix=${oldVersion%-*}
  local oldSuffix=${oldVersion##*-}
  local newPrefix=${newVersion%-*}
  local newSuffix=${newVersion##*-}
  
  if [ -n "$newVersion" ]; then
    if [ -z "$oldVersion" ] || [ "$newPrefix" \> "$oldPrefix" ]; then
      exit 0
    elif [ "$newPrefix" = "$oldPrefix" ] && [ -z "$newSuffix" ] && [ -n "$oldSuffix" ]; then
      exit 0
    fi
  fi
  
  exit 1
}


# Returns a specified value of a pom.xml.
#  Arguments:
#  1 - the path to the tag of which the value is retrieved (e.g. project.version)
#  2 - the path to the pom.xml (default: current folder)
#
GetPomValue() {
  local valueKey="$1"
  local pomPath=$(GetPomXmlPath "${2-.}")
  
  # try to retrieve the value
  local retrievedValue
  retrievedValue=$(mvn -q -Dexec.executable="echo" -Dexec.args='${'"$valueKey"'}' --non-recursive \
                   org.codehaus.mojo:exec-maven-plugin:1.6.0:exec -f"$pomPath")
                   
  # do not return the error message if the value was not retrieved
  if [ $? -eq 0 ]; then
    echo "$retrievedValue"
  else
    echo -e "Could not retrieve $valueKey from $pomPath:\n$retrievedValue" >&2
    exit 1
  fi
}


# Replaces all -SNAPSHOT versions in a pom.xml with the corresponding release versions
# If the pom.xml does not exist or does not compile with the new versions, this function fails.
#
# Arguments:
#  1 - a file path to a pom.xml or a Maven project folder (default: current folder)
#
UpdateMavenSnapshotToRelease() {
  local pomXmlPath=$(GetPomXmlPath "${1-.}")
  
  if [ ! -f "$pomXmlPath" ]; then
    echo "Cannot update '$pomXmlPath' because the path does not exist!" >&2
    exit 1
  fi
  
  # create a backup of the pom.xml
  cp -f "$pomXmlPath" "$pomXmlPath.backup"
  
  # remove all SNAPSHOT suffixes
  perl -pi -e \
       "s~<([a-z.]*)>([0-9.]+)-SNAPSHOT</\1>~<\1>\2</\1>~gi" \
       "$pomXmlPath"
  
  # check if maven still compiles
  local mvnResult
  mvnResult=$(mvn compile -f"$pomXmlPath")
  
  if [ $? -ne 0 ]; then
    # restore pom.xml from backup file
    mv -f "$pomXmlPath.backup" "$pomXmlPath"
    
    echo -e "Could not replace all SNAPSHOT versions:\n$mvnResult" >&2
    exit 1
  fi
}