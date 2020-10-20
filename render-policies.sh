#!/usr/bin/env bash

if [ "$#" -ne 3 ]
then
  echo "ERROR: Wrong number of arguments"
  echo "Usage: render-policies.sh AWS_REGION ACCOUNT_ID CLUSTER_NAME"
  exit 1
fi

REGION=$1
ACCOUNT=$2
CLUSTER=$3

for F in instance operator user
do
  sed 's/<REGION>/'"$REGION"'/' iam/${F}-policy.json > a.json
  sed 's/<AWS ACCOUNT ID>/'"$ACCOUNT"'/' a.json > b.json
  sed 's/<CLUSTERNAME>/'"$CLUSTER"'/' b.json > nf-${F}-policy.json
  rm a.json b.json
done
