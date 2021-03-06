#!/bin/bash
#
# Copyright 2016 IBM Corp. All Rights Reserved.
#
# Licensed under the Apache License, Version 2.0 (the “License”);
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#  https://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an “AS IS” BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

# load configuration variables
source local.env

# PACKAGE_NAME is configurable so that multiple versions of the actions
# can be deployed in different packages under the same namespace
if [ -z $PACKAGE_NAME ]; then
  PACKAGE_NAME=lwr
fi

if [ -z $FUNCTIONS_NAMESPACE ]; then
  FUNCTIONS_NAMESPACE=logistics-wizard
fi

if ibmcloud fn namespace get $FUNCTIONS_NAMESPACE > /dev/null 2>&1; then
  echo "Namespace $FUNCTIONS_NAMESPACE already exists."
else
  ibmcloud fn namespace create $FUNCTIONS_NAMESPACE
fi

NAMESPACE_INSTANCE_ID=$(ibmcloud fn namespace get $FUNCTIONS_NAMESPACE --properties | grep ID | awk '{print $2}')
ibmcloud fn property set --namespace $NAMESPACE_INSTANCE_ID
echo "Namespace Instance ID is $NAMESPACE_INSTANCE_ID"

function usage() {
  echo "Usage: $0 [--install,--uninstall,--update,--env]"
}

function install() {
  echo "Creating database..."
  # ignore "database already exists error"
  curl -s -X PUT $CLOUDANT_URL/$CLOUDANT_DATABASE | grep -v file_exists

  echo "Inserting database design documents..."
  # ignore "document already exists error"
  curl -s -X POST -H 'Content-Type: application/json' -d @database-designs.json $CLOUDANT_URL/$CLOUDANT_DATABASE/_bulk_docs | grep -v conflict

  echo "Creating $PACKAGE_NAME package"
  ibmcloud cloud-functions package create $PACKAGE_NAME\
    --param services.controller.url $CONTROLLER_SERVICE\
    --param services.cloudant.url $CLOUDANT_URL\
    --param services.cloudant.database $CLOUDANT_DATABASE

  echo "Creating actions"
  ibmcloud cloud-functions action create $PACKAGE_NAME/recommend\
    -a description 'Recommend new shipments based on weather conditions'\
    --web true\
    dist/recommend.bundle.js
  ibmcloud cloud-functions action create $PACKAGE_NAME/retrieve\
    -a description 'Return the list of recommendations'\
    --web true\
    actions/retrieve.js
  ibmcloud cloud-functions action create $PACKAGE_NAME/acknowledge\
    -a description 'Acknowledge a list of recommendations'\
    --web true\
    actions/acknowledge.js
  ibmcloud cloud-functions action create $PACKAGE_NAME/prepare-for-slack\
    -a description 'Transform a recommendation into a Slack message'\
    --web true\
    actions/prepare-for-slack.js

  OPENWHISK_HOST=$(ibmcloud fn property get --apihost -o raw)
  FUNCTIONS_NAMESPACE_URL=https://${OPENWHISK_HOST}/api/v1/web/${NAMESPACE_INSTANCE_ID}/${PACKAGE_NAME}
  echo "URL to call functions is $FUNCTIONS_NAMESPACE_URL"
}

function uninstall() {
  echo "Removing actions..."
  ibmcloud cloud-functions action delete $PACKAGE_NAME/recommend
  ibmcloud cloud-functions action delete $PACKAGE_NAME/retrieve
  ibmcloud cloud-functions action delete $PACKAGE_NAME/acknowledge
  ibmcloud cloud-functions action delete $PACKAGE_NAME/prepare-for-slack

  echo "Removing package..."
  ibmcloud cloud-functions package delete $PACKAGE_NAME

  echo "Done"
  ibmcloud cloud-functions list
}

function update() {
  echo "Updating actions..."
  ibmcloud cloud-functions action update $PACKAGE_NAME/recommend         dist/recommend.bundle.js
  ibmcloud cloud-functions action update $PACKAGE_NAME/retrieve          actions/retrieve.js
  ibmcloud cloud-functions action update $PACKAGE_NAME/acknowledge       actions/acknowledge.js
  ibmcloud cloud-functions action update $PACKAGE_NAME/prepare-for-slack actions/prepare-for-slack.js
}

function showenv() {
  echo "FUNCTIONS_NAMESPACE=$FUNCTIONS_NAMESPACE"
  echo "PACKAGE_NAME=$PACKAGE_NAME"
  echo "CONTROLLER_SERVICE=$CONTROLLER_SERVICE"
  echo "CLOUDANT_URL=$CLOUDANT_URL"
  echo "CLOUDANT_DATABASE=$CLOUDANT_DATABASE"
}

case "$1" in
"--install" )
install
;;
"--uninstall" )
uninstall
;;
"--update" )
update
;;
"--env" )
showenv
;;
* )
usage
;;
esac
