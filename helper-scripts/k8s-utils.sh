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

# This script offers helper functions that concern Kubernetes.


# Generates a report of occurences of each clusterIP that is found
# in YAML files of a specified folder and sub-folders.
#
# Arguments:
#  1 - the root directory in which YAML files are being searched
#
# Return: true, if there are duplicate clusterIDs
#
CheckDuplicateClusterIps() {
  serviceFolder="$1"
  
  ipList=$(GetClusterIpList "$serviceFolder" | tr " " "\n")
  hasDuplicate=false
  
  while [ "$ipList" != "" ]; do
    clusterIp="$(echo "$ipList" | head -1)"
    occurences=$(echo "$ipList" | grep -c "$clusterIp")
    if [ "$occurences" -gt 1 ]; then
      hasDuplicate=true
	  printf "%-15s occurs $occurences times\n" "$clusterIp" >&2
    else
	  printf "%-15s occurs once\n" "$clusterIp" >&2
	fi
	ipList=$(echo "$ipList" | grep -v "^$clusterIp$")
  done
  echo "$hasDuplicate"
}


# Searches for an available clusterIp in a specified range by recursively
# searching clusterIPs of YAML files within a specified folder.
#
# Arguments:
#  1 - the root directory in which YAML files are being searched
#  2 - the first three IP segments (e.g. "192.168.0.")
#  3 - the lowest viable fourth IP segment
#  4 - the highest viable fourth IP segment
#
# Return:
#  a free clusterIP within the specified range
#
GetFreeClusterIp() {
  serviceFolder="$1"
  ipPrefix="$2"
  rangeFrom=$3
  rangeTo=$4
  
  ipList=$(GetClusterIpList "$serviceFolder")
  
  for ((lastSegment=$rangeFrom;lastSegment <= $rangeTo;lastSegment++))
  do
    clusterIp="$ipPrefix$lastSegment"
	
	if [ "$(echo "$ipList" | grep -oP "(?<![0-9])$clusterIp(?![0-9])")" = "" ]; then
      echo "$clusterIp"
	  exit 0
    fi
  done
  
  exit 1
}


# Recursively searches for clusterIPs that are defined in YAML files of a
# specified folder.
#
# Arguments:
#  1 - the root directory in which YAML files are being searched
#
# Return:
#  a space-separated list of clusterIPs
#
GetClusterIpList() {
  serviceFolder="$1"
  ipList=""
    
  for file in "$serviceFolder"/*
  do
    if [ -d "$file" ]; then
      dirIpList=$(GetClusterIpList "$file")

      # if there is a clusterIP in a subfolder, check if it is higher than the current highest
      if [ "$dirIpList" != "" ]; then
        ipList="$ipList $dirIpList"
	  fi
    fi
  done
  
  while read file; do
    if [ -f "$serviceFolder/$file" ] && [ "${file##*.}" = "yml" ]; then
	    clusterIp=$(grep -oP "(?<=clusterIP:).+" "$serviceFolder/$file" | tr -d '[:space:]')
    fi
    
    # if there is a clusterIP, check if it is higher than the current highest
    if [ "$clusterIp" != "" ] && [ "$clusterIp" != "None" ]; then
        ipList="$ipList $clusterIp"
    fi
  done <<< "$(ls "$serviceFolder")"
  
  if [ "$ipList" != "" ]; then
    ipList="${ipList# }"
  fi
  echo "$ipList"
}