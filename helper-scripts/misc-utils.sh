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


ExitIfLastOperationFailed() {
  errorMessage="$1"
  
  if [ $? -ne 0 ]; then
    if [ "$errorMessage" != "" ]; then
      echo "$errorMessage" >&2
	fi
    exit 1
  fi
}


IsUrlReachable() {
  url="$1"
  userName="$2"
  password="$3"

  httpCode=$(GetHeadHttpCode "$url" "$userName" "$password")
  
  if [ httpCode -eq 200 ]; then
    echo true
  else
    echo false
  fi
}


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


# FUNCTION FOR CHECKING IF TWO MAJOR VERSIONS DIFFER
IsMajorVersionDifferent() {
  sourceMajorVersion=${1%%.*}
  targetMajorVersion=${2%%.*}
  
  if [ $targetMajorVersion -ne $sourceMajorVersion ]; then
    echo "true"
  else
    echo "false"
  fi
}
