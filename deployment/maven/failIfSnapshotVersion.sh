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

# This script fails with exit code 1 if the injected plan variable "maven.version"
# represents a Maven SNAPSHOT version.


# treat unset variables as an error when substituting
set -u

isSnapshot=$(echo "$bamboo_inject_maven_version" | grep -cP "\-SNAPSHOT\$")

if [ "$isSnapshot" = "1" ]; then
  echo "Maven release deployments must not contain SNAPSHOT versions!" >&2
  exit 1
fi