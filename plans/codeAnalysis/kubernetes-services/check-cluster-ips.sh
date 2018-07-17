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

# This script is being called by the Bamboo Job TODO which checks if there
# are duplicate clusterIPs defined in the gerdireleases repository.
#
# Bamboo Plan Variables:
#  ManualBuildTriggerReason_userName - the login name of the current user


# treat unset variables as an error when substituting
set -u

# load helper scripts
source ./scripts/helper-scripts/k8s-utils.sh

! $(CheckDuplicateClusterIps "gerdireleases/k8s-deployment")
