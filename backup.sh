#!/bin/bash

deploypath="/app/infor/sce/wildfly-26.1.2.Final/"
db="scprd"
node="1"

read -p "Enter User: " id

# Format date: YYYYMMDD
mydate=$(date +"%Y%m%d")

echo "${mydate}-${id}"
fol="${mydate} - ${id}"

mkdir -p "$fol/backup/oltp"
mkdir -p "$fol/backup/ui"
mkdir -p "$fol/backup/batch"
mkdir -p "$fol/backup/api"
mkdir -p "$fol/backup/esb"
mkdir -p "$fol/backup/scheduler"
mkdir -p "$fol/backup/reports"

cp "${deploypath}${db}-wmoltp${node}/deployments/wmserver.ear" "./$fol/backup/oltp/"
cp "${deploypath}${db}-uiservice${node}/deployments/service.ear" "./$fol/backup/ui/"
cp "${deploypath}${db}-wmbatch${node}/deployments/wmserver.ear" "./$fol/backup/batch/"
cp "${deploypath}${db}-wmwmapi${node}/deployments/wmserver.ear" "./$fol/backup/api/"
cp "${deploypath}${db}-wmesbserver${node}/deployments/wmserver.ear" "./$fol/backup/esb/"
cp "${deploypath}${db}-scheduler${node}/deployments/schedserver.war" "./$fol/backup/scheduler/"
cp "${deploypath}${db}-reports${node}/deployments/${db}_scereports.war" "./$fol/backup/reports/"
