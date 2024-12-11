FROM alpine:latest
RUN apk update 
RUN apk add curl zip yq bash bzip2 aws-cli netcat-openbsd 
RUN apk add postgresql-client
RUN apk add mariadb-connector-c
RUN apk add mysql-client
RUN rm -rf /var/cache/apk/*
ADD scripts/aws-rds-native-backup.sh /usr/bin/
RUN chmod +x /usr/bin/aws-rds-native-backup.sh
RUN curl -s https://truststore.pki.rds.amazonaws.com/eu-west-1/eu-west-1-bundle.pem --output eu-west-1-bundle.pem 
ENTRYPOINT ["bash", "/usr/bin/aws-rds-native-backup.sh"] 
