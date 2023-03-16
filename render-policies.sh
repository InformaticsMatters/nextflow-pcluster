#!/usr/bin/env bash

if [ "$#" -ne 2 ]
then
  echo "ERROR: Wrong number of arguments"
  echo "Usage: render-policies.sh AWS_REGION ACCOUNT_ID"
  exit 1
fi

REGION=$1
ACCOUNT=$2

for F in EVERYTHING head-node image-builder instance privileged
do
  sed 's/<REGION>/'"$REGION"'/' iam/${F}-policy.json > a.json
  sed 's/<AWS ACCOUNT ID>/'"$ACCOUNT"'/' a.json > v3-${F}-policy.json
  rm a.json
done
