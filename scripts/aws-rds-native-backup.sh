#!/bin/bash
set -euo pipefail

# Check environment

if [ -z "${BACKUP_TAG_KEY:-}" ]; then
  echo "BACKUP_TAG_KEY was not set"
fi

if [ -z "${AWS_REGION:-}" ]; then
  echo "REGION was not set"
fi

if [ -z "${RDS_USER:-}" ]; then
  echo "RDS_USER was not set"
fi

if [ -z "${MYSQL_EXCLUDED_DBS_REGEXP:-}" ]; then
  echo "MYSQL_EXCLUDED_DBS_REGEXP was not set"
fi

if [ -z "${PG_EXCLUDED_DBS_REGEXP:-}" ]; then
  echo "PG_EXCLUDED_DBS_REGEXP was not set"
fi

if [ -z "${S3_BUCKET:-}" ]; then
  echo "S3_BUCKET was not set"
fi

if [ -z "${S3_PREFIX:-}" ]; then
  echo "S3_PREFIX was not set"
fi

if [ -z "${TMP_PATH:-}" ]; then
  echo "TMP_PATH was not set"
fi

# functions

# check rds host connection
function check_connection() {
  nc -z -v -w1 $RDS_HOST $RDS_PORT &>/dev/null
  if [[ $? -eq 0 ]]; then
    return 0
  else
    echo "[ERROR]:connecting to the rds host: ${RDS_HOST} on port: ${RDS_PORT} check security group"
    return 1
  fi
}

# generate rds auth token
function get_db_auth_token() {
  echo "[INFO]:get iam token for user ${RDS_USER}..."
  DB_AUTH_TOKEN=$(aws rds generate-db-auth-token --hostname $RDS_HOST --port $RDS_PORT --username $RDS_USER --region $AWS_REGION)
  if [[ $? -eq 0 ]]; then
    return 0
  fi
  echo "[ERROR]:Error getting iam token for user ${RDS_USER}..."
  return 1
}

function get_databases() {
  if [ $RDS_ENGINE == "aurora-mysql" ]; then
    RDS_PORT="3306"
    # check connection
    if !(check_connection); then exit 1; fi
    get_db_auth_token
    export MYSQL_PWD=$DB_AUTH_TOKEN
    Databases=$(mysql --user=$RDS_USER -h $RDS_HOST -e "show databases" -N --ssl-ca="./eu-west-1-bundle.pem")
  fi

  if [ $RDS_ENGINE == "aurora-postgresql" ]; then
    RDS_PORT="5432"

    # check connection and get databases
    if !(check_connection); then exit 1; fi
    get_db_auth_token
    export PGPASSWORD=$DB_AUTH_TOKEN
    Databases=$(psql --username=$RDS_USER -h $RDS_HOST -c "select datname from pg_database" -d postgres --csv)
  fi
}

# get clusters with the backup enabled tag
function get_clusters() {
  selected_clusters=()
  err=false
  clusters=$(aws rds describe-db-clusters)
  clusterIdentifiers=$(echo $clusters | yq '.DBClusters[].DBClusterIdentifier')
  for cluster in $clusterIdentifiers; do
    echo "[INFO]:Checking tag ${BACKUP_TAG_KEY} is set to true on RDS cluster ${cluster}.."
    if [ "$(echo $clusters | yq '.DBClusters[] | select(.DBClusterIdentifier == "'${cluster}'")' | yq .TagList | yq '.[] | select(.Key=="'${BACKUP_TAG_KEY}'")|.Value')" == true ]; then
      echo "[INFO]:${BACKUP_TAG_KEY} is set to true on RDS cluster ${cluster}"
      selected_clusters+=(${cluster})
    fi
  done
  if [[ ${#selected_clusters[@]} -eq 0 ]]; then
    echo "[ERROR]:no clusters found with ${BACKUP_TAG_KEY} set to true"
    err=true
  fi
}

# copy to s3 (The largest object that can be uploaded in a single PUT is 5 GB.)
function copy_to_s3() {
  echo "[INFO]:Uploading to s3: s3://${S3_BUCKET}/${S3_PREFIX}/${FILENAME}.sql.bz"
  aws s3 cp ${TMP_PATH}/${FILENAME}.sql.bz s3://${S3_BUCKET}/${S3_PREFIX}/${FILENAME}.sql.bz
  rm ${TMP_PATH}/${FILENAME}.sql.bz
  echo "[INFO]:Done."
}

# start native backup
function start_backup() {
  FILENAME=${cluster}_${RDS_DATABASE}_$(date +"%Y-%m-%dT%H:%M:%SZ")

  echo "[INFO]:Start dump of database: ${RDS_DATABASE} from cluster ${cluster}"
  echo "[INFO]:Using Filename: ${FILENAME}"
  if [[ $RDS_ENGINE == "aurora-postgresql" ]]; then
    pg_dump -h $RDS_HOST -U $RDS_USER -bCc -d $RDS_DATABASE | bzip2 >${TMP_PATH}/${FILENAME}.sql.bz
  fi

  if [[ $RDS_ENGINE == "aurora-mysql" ]]; then
    mysqldump --user=$RDS_USER -h $RDS_HOST --ssl-ca="./eu-west-1-bundle.pem" \
      --single-transaction --add-drop-database --databases $RDS_DATABASE --no-tablespaces | bzip2 >${TMP_PATH}/${FILENAME}.sql.bz
  fi

  if [[ -s "${TMP_PATH}/${FILENAME}.sql.bz" ]]; then
    copy_to_s3
  else
    echo "[ERROR]:backup failed for ${RDS_DATABASE} on ${cluster}"
  fi
}

# start main script

# set ssl conection envs for postgress
export PGSSLMODE=verify-full
export PGSSLROOTCERT=./eu-west-1-bundle.pem

get_clusters
if ($err); then exit 1; fi

for cluster in ${selected_clusters[@]}; do
  RDS_HOST=$(echo $clusters | yq '.DBClusters[] | select(.DBClusterIdentifier == "'${cluster}'")' | yq .ReaderEndpoint)
  RDS_ENGINE=$(echo $clusters | yq '.DBClusters[] | select(.DBClusterIdentifier == "'${cluster}'")' | yq .Engine)

  get_databases

  if [[ $Databases != "" ]]; then
    for RDS_DATABASE in $Databases; do
      if [[ ! $RDS_DATABASE =~ $PG_EXCLUDED_DBS_REGEXP && $RDS_ENGINE == "aurora-postgresql" ]] || [[ ! $RDS_DATABASE =~ $MYSQL_EXCLUDED_DBS_REGEXP && $RDS_ENGINE == "aurora-mysql" ]]; then
        start_backup
      fi
    done
  else
    echo "[WARNING]:no databases found to backup on ${cluster}"
  fi
done
