#! /bin/bash
set -euo pipefail


# Check environment

if [ -z "${REGION:-}" ]; then
  echo "REGION was not set"
fi

if [ -z "${POSTGRES_DATABASE:-}" ]; then
  echo "POSTGRES_DATABASE was not set"
fi

if [ -z "${POSTGRES_HOST:-}" ]; then
  echo "POSTGRES_HOST was not set"
fi

if [ -z "${POSTGRES_PORT:-}" ]; then
  echo "POSTGRES_HOST was not set"
fi

if [ -z "${POSTGRES_USER:-}" ]; then
  echo "POSTGRES_HOST was not set"
fi

if [ -z "${S3_BUCKET:-}" ]; then
  echo "S3_BUCKET was not set"
fi

if [ -z "${S3_BUCKET:-}" ]; then
  echo "S3_BUCKET was not set"
fi

if [ -z "${S3_PREFIX:-}" ]; then
  echo "S3_BUCKET was not set"
fi

if [ -z "${S3_REGION:-}" ]; then
  echo "S3_BUCKET not set, using \$REGION ($REGION)"
  S3_REGION=$REGION
fi

echo "Printing Volume Information"
df -h .

FILENAME=${POSTGRES_DATABASE}_$(date +"%Y-%m-%dT%H:%M:%SZ")
echo "Using Filename: ${FILENAME}"

export PGPASSWORD=$(aws rds generate-db-auth-token --hostname ${POSTGRES_HOST} --port ${POSTGRES_PORT} --username ${POSTGRES_USER} --region ${REGION})

echo "Start dump.."
{ pg_dump -h "${POSTGRES_HOST}" -p "${POSTGRES_PORT}" -U ${POSTGRES_USER} "dbname=${POSTGRES_DATABASE} sslmode=verify-full sslrootcert=eu-west-1-bundle.pem" |\
pv -L ${RATE_LIMIT} -r -b -i 60 -f 2>&3 |\
bzip2 |\
aws s3 cp - "s3://$S3_BUCKET/$S3_PREFIX/${FILENAME}.sql.bz.enc" --region=$S3_REGION; } 3>&1 | tr '\015' '\012'
echo "Done."
