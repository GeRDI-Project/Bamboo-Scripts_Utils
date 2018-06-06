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


# Returns true, if a HEAD request to a specified URL returned 200.
# Otherwise, false is returned.
#  Arguments:
#  1 - the URL that is tested
#  2 - a username for Basic Authentication (optional)
#  3 - a password for Basic Authentication (optional)
#
IsUrlReachable() {
  url="$1"
  userName="$2"
  password="$3"

  httpCode=$(GetHeadHttpCode "$url" "$userName" "$password")
  
  if [ $httpCode -eq 200 ]; then
    echo true
  else
    echo false
  fi
}


# This function echos true if the major version between two versions 
# of the schema 'major.minor.bugfix' differs.
#  Arguments:
#  1 - the first version that is compared
#  2 - the second version that is compared
#
IsMajorVersionDifferent() {
  majorVersionA=${1%%.*}
  majorVersionB=${2%%.*}
  
  if [ "$majorVersionA" != "$majorVersionB" ]; then
    echo "true"
  else
    echo "false"
  fi
}


# Returns the HTTP response code of a HEAD request to a specified URL.
#  Arguments:
#  1 - the URL that is tested
#  2 - a username for Basic Authentication (optional)
#  3 - a password for Basic Authentication (optional)
#
GetHeadHttpCode() {
  url="$1"
  userName="$2"
  password="$3"
  
  if [ "$userName" != "" ]; then
    response=$(curl -sIX HEAD -u "$userName:$password" $url)
  else
    response=$(curl -sIX HEAD $url)
  fi
  
  httpCode=$(echo "$response" | grep -oP '(?<=HTTP/\d\.\d )\d+')
  echo "$httpCode"
}


# Replaces all occurences of a specified ${placeholder} within a file
# with the actual value of $placeholder.
#  Arguments:
#  1 - the name of the placeholder and local variable
#  2 - the file path
SubstitutePlaceholderInFile() {
  placeHolderName="$1"
  fileName="$2"
  placeHolderValue="${!placeHolderName}"
  
  sed --in-place=.tmp -e "s~\${$placeHolderName}~$placeHolderValue~g" $fileName && rm -f $fileName.tmp
}


# This function fails with exit code 1, if the preceding operation did not exit with exit code 0.
#  Arguments:
#  1 - An optional error message that is printed only when the preceding operation failed
#
ExitIfLastOperationFailed() {
  lastOpReturnCode=$?
  errorMessage="$1"
  
  if [ $lastOpReturnCode -ne 0 ]; then
    if [ "$errorMessage" != "" ]; then
      echo "$errorMessage" >&2
	fi
    exit 1
  fi
}