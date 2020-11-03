#!/usr/bin/env bash

if [ "$#" -ne 4 ]
then
  echo "ERROR: Wrong number of arguments"
  echo "Usage: render-policies.sh AWS_REGION ACCOUNT_ID CLUSTER_NAME ROLE_NAME"
  exit 1
fi

REGION=$1
ACCOUNT=$2
CLUSTER=$3
ROLE=$4

for F in instance operator user
do
  sed 's/<REGION>/'"$REGION"'/' iam/${F}-policy.json > a.json
  sed 's/<AWS ACCOUNT ID>/'"$ACCOUNT"'/' a.json > b.json
  sed 's/<PARALLELCLUSTER EC2 ROLE NAME>/'"$ROLE"'/' b.json > c.json
  sed 's/<CLUSTERNAME>/'"$CLUSTER"'/' c.json > nf-${F}-policy.json
  rm a.json b.json c.json
done
