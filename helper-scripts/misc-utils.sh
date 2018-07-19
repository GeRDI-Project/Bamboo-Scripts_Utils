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

# This script offers some generic utility functions.


# Exits with 0, if a HEAD request to a specified URL returned 200.
# Otherwise, it exits with 1.
#  Arguments:
#  1 - the URL that is tested
#  2 - a username for Basic Authentication (optional)
#  3 - a password for Basic Authentication (optional)
#
IsUrlReachable() {
  local url="$1"
  local userName="$2"
  local password="$3"

  local httpCode
  httpCode=$(GetHeadHttpCode "$url" "$userName" "$password")
  
  if [ $httpCode -lt 200 ] || [ $httpCode -ge 400 ]; then
    exit 1
  fi
}


# This function echos true if the major version between two versions 
# of the schema 'major.minor.bugfix' differs.
#  Arguments:
#  1 - the first version that is compared
#  2 - the second version that is compared
#
IsMajorVersionDifferent() {
  local majorVersionA=${1%%.*}
  local majorVersionB=${2%%.*}
  
  if [ "$majorVersionA" != "$majorVersionB" ]; then
    echo "true"
  else
    echo "false"
  fi
}


# Return a given version with the major, minor or bufix version compoment incremented
# (and "components to right" set to zero)
#
# Arguments:
# 1 - fixed string (minor, major, bugfix) denoting which part is to be incremented 
# 2 - a version of the schema 'major.minor.bugfix'
#
IncrementVersion() {

  local versionType=$1

  local majorVersion=${2%%.*}
  local minorVersion=${2%.*}
        minorVersion=${minorVersion#*.}
  local bugfixVersion=${2##*.}

  case $versionType in
	  major)
		  majorVersion=$((majorVersion+1))
                  minorVersion=0
                  bugfixVersion=0
                  ;;
          minor)
                  minorVersion=$((minorVersion+1))
                  bugfixVersion=0
                  ;;
          bugfix)
                  bugfixVersion=$((bugfixVersion+1))
                  ;;
                *)
                  echo "Unknown version type '$versionType'! Valid values are 'major', 'minor', 'bugfix'." >&2
                  exit 1
  esac

  echo $majorVersion.$minorVersion.$bugfixVersion
}


# Returns the HTTP response code of a HEAD request to a specified URL.
#  Arguments:
#  1 - the URL that is tested
#  2 - a username for Basic Authentication (optional)
#  3 - a password for Basic Authentication (optional)
#
GetHeadHttpCode() {
  local url="$1"
  local userName="$2"
  local password="$3"
  
  local response
  if [ -n "$userName" ]; then
    response=$(curl -sIX HEAD -u "$userName:$password" $url)
  else
    response=$(curl -sIX HEAD $url)
  fi
  
  echo "$response" | grep -oP '(?<=HTTP/\d\.\d )\d+'
}


# Replaces all occurences of a specified ${placeholder} within a file
# with the actual value of $placeholder.
#  Arguments:
#  1 - the file path
#  2 - the name of the placeholder and local variable
#
SubstitutePlaceholderInFile() {
  local fileName="$1"
  local placeHolderName="$2"
  local placeHolderValue="${!placeHolderName}"
  
  sed --in-place=.tmp -e "s~\${$placeHolderName}~$placeHolderValue~g" $fileName && rm -f $fileName.tmp
}


# This function fails with exit code 1, if the preceding operation did not exit with exit code 0.
#  Arguments:
#  1 - An optional error message that is printed only when the preceding operation failed
#
ExitIfLastOperationFailed() {
  local lastOpReturnCode=$?
  local errorMessage="$1"
  
  if [ $lastOpReturnCode -ne 0 ]; then
    if [ -n "$errorMessage" ]; then
      echo "$errorMessage" >&2
	fi
    exit 1
  fi
}
