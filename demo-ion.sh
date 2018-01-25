#!/bin/bash

echo "################Running build################"
echo "######Triggering Ion against git repo########"
ionize analyze

echo "###############Build finished################"
echo "#######Posting Artifact to repository########"
tar czf /tmp/Python-Mock-$(cat version).tgz ./
aws s3 cp /tmp/Python-Mock-$(cat version).tgz s3://ion-channel-ppierson/public/artifact/ --acl public-read
sources=$(ion-connect project get-projects --team-id 0dcb0911-6aee-43be-a0f1-eb7ecfc691f8 | jq -r '.[].source')
#echo $sources
if echo $sources | grep -w 'https://s3.amazonaws.com/ion-channel-ppierson/public/artifact/Python-Mock-'$(cat version).tgz > /dev/null; then
    echo '#####Project exists, continue as expected#####'
else
    echo '#####Creating new project#####'
    project_id=$(ion-connect project create-project --team-id 0dcb0911-6aee-43be-a0f1-eb7ecfc691f8 --ruleset-id 0ecb7331-dde6-48f6-ac04-789931dc695e --type artifact Python-Mock-Artifact-$(cat version) https://s3.amazonaws.com/ion-channel-ppierson/public/artifact/Python-Mock-$(cat version).tgz master | jq -r '.id')
    #echo $project_id
    sed -i "s/^project: .*/project: $project_id/" .ionize-artifact.yaml
    cat .ionize-artifact.yaml
fi

echo "#####Triggering Ion against Artifact#########"
ionize --config .ionize-artifact.yaml analyze
