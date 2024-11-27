FROM alpine:latest
RUN apk update && apk add curl zip yq postgresql-client bash bzip2 aws-cli
RUN rm -rf /var/cache/apk/*
ADD scripts/aws-rds-native-backup.sh /usr/bin/
RUN chmod +x /usr/bin/aws-rds-native-backup.sh
RUN curl -s https://truststore.pki.rds.amazonaws.com/eu-west-1/eu-west-1-bundle.pem --output eu-west-1-bundle.pem 
ENTRYPOINT ["bash", "/usr/bin/aws-rds-native-backup.sh"] 
