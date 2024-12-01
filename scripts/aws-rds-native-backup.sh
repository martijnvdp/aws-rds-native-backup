#! /bin/bash
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

# if [ -z "${S3_BUCKET:-}" ]; then
#   echo "S3_BUCKET was not set"
# fi

# if [ -z "${S3_BUCKET:-}" ]; then
#   echo "S3_BUCKET was not set"
# fi

# if [ -z "${S3_PREFIX:-}" ]; then
#   echo "S3_BUCKET was not set"
# fi

# if [ -z "${S3_REGION:-}" ]; then
#   echo "S3_BUCKET not set, using \$REGION ($REGION)"
#   S3_REGION=$REGION
# fi

echo "Printing Volume Information"
df -h .



# get backup targets from rds cluster tags
clusters=$(aws rds describe-db-clusters)
clusterIdentifiers=$(echo $clusters|yq '.DBClusters[].DBClusterIdentifier')
for cluster in $clusterIdentifiers
do
    echo "Getting tags from RDS cluster ${cluster}.."
    if [ "$(echo $clusters| yq '.DBClusters[] | select(.DBClusterIdentifier == "'${cluster}'")'| yq .TagList| yq '.[] | select(.Key=="'${BACKUP_TAG_KEY}'")|.Value')" == true ]; then
        echo "${cluster} has ${BACKUP_TAG_KEY} tag set to true"
        RDS_HOST=$(echo $clusters| yq '.DBClusters[] | select(.DBClusterIdentifier == "'${cluster}'")'| yq .ReaderEndpoint)
        RDS_ENGINE=$(echo $clusters| yq '.DBClusters[] | select(.DBClusterIdentifier == "'${cluster}'")'| yq .Engine)
        
        echo "get iam token for user ${RDS_USER} ..."
        if [ $RDS_ENGINE == "aurora-mysql" ]; then
            RDS_PORT="3306"
            Databases="test"
            #export MYSQL_PWD=$(aws rds generate-db-auth-token --hostname $RDS_HOST --port $RDS_PORT --username $RDS_USER --region $AWS_REGION)
            #$Databases=$(mysql --user=$RDS_USER -h $RDS_HOST -e \"show databases\" --ssl-ca=\"eu-west-1-bundle.pem\" --enable-cleartext-plugin)
        fi

        if [ $RDS_ENGINE == "aurora-postgresql" ]; then
            RDS_PORT="5432"
            export PGPASSWORD=$(aws rds generate-db-auth-token --hostname $RDS_HOST --port $RDS_PORT --username $RDS_USER --region $AWS_REGION)
            Databases=$( psql --username=$RDS_USER  -h $RDS_HOST -c "select datname from pg_database" -d postgres --csv)
        fi
        
        echo $Databases
        for RDS_DATABASE in $Databases
        do
            FILENAME=${RDS_DATABASE}_$(date +"%Y-%m-%dT%H:%M:%SZ")
            echo "Using Filename: ${FILENAME}"

            if [ $RDS_ENGINE == "aurora-postgresql" ]; then
                echo "Start dump.."
                echo "pg_dump -h "${RDS_HOST}" -p "${RDS_PORT}" -U "${RDS_USER}" -bCc -d "${RDS_DATABASE}" sslmode=verify-full sslrootcert=eu-west-1-bundle.pem" 
                # { pg_dump -h "${RDS_HOST}" -p "${RDS_PORT}" -U "${RDS_USER}" -bCc -d "${RDS_DATABASE}" sslmode=verify-full sslrootcert=eu-west-1-bundle.pem |\
                # bzip2 |\
                # aws s3 cp - "s3://$S3_BUCKET/$S3_PREFIX/${FILENAME}.sql.bz" --region=$S3_REGION; } 3>&1 | tr '\015' '\012'
                echo "Done."
            fi
        done
    fi
done



