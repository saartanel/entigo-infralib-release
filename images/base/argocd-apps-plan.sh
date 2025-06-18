#!/bin/bash
if [ "$ARGOCD_NAMESPACE" == "" ]
then
  echo "Unable to get ArgoCD namespace."
  exit 29
fi

if [ "$1" == "" ]
then
  echo "First parameters has to be ArgoCD Application file."
  exit 28
fi

app_file=$1
app_name=`yq -r '.metadata.name' $app_file`

if [ "$app_name" == "" ]
then
  echo "Unable to find .metadata.name in $app_file."
  exit 27
fi

#local development hack
targetRevision=`yq -r '.spec.sources[0].targetRevision' $app_file`
if [ "$targetRevision" == "local" ]
then
  echo "Detected local target"
  path=`yq -r '.spec.sources[0].path' $app_file`
  repo=`yq -r '.spec.sources[0].repoURL' $app_file`
  repopod=`kubectl get pod -n $ARGOCD_NAMESPACE -l app.kubernetes.io/component=repo-server -o jsonpath='{.items[0].metadata.name}'`
  kubectl exec -c repo-server -n $ARGOCD_NAMESPACE $repopod -- bash -c "mkdir -p /tmp/conf/modules/k8s && rm -rf /tmp/conf/$path"
  kubectl cp /conf/$path ${ARGOCD_NAMESPACE}/${repopod}:/tmp/conf/modules/k8s
  kubectl exec -it -c repo-server -n ${ARGOCD_NAMESPACE} $repopod -- bash -c "cd /tmp/conf/ && git init; git add . && git config user.email 'agent@entigo.com' && git config user.name 'agent' && git commit -a -m'updates'"
  yq -y -i 'del(.spec.sources[0].targetRevision)' $app_file
fi

if kubectl get applications.argoproj.io $app_name -n ${ARGOCD_NAMESPACE} -o jsonpath='{.metadata.name}' >/dev/null 2>&1; then
    APP_EXISTED="yes"
    kubectl patch -n ${ARGOCD_NAMESPACE} applications.argoproj.io $app_name --type=json -p="[{'op': 'remove', 'path': '/spec/syncPolicy/automated'}]" > /dev/null 2>&1
else
    APP_EXISTED="no"
fi

kubectl apply -n ${ARGOCD_NAMESPACE} -f $app_file
if [ $? -ne 0 ]
then
  echo "Failed to kubectl apply ArgoCD Application $app_name!"
  exit 24
fi

if [ "$USE_ARGOCD_CLI" == "true" ]
then
  STATUS=`argocd --server ${ARGOCD_HOSTNAME} --grpc-web app get --refresh $app_name -o json | jq -r '"Status:\(.status.sync.status) Missing:\(if .status.resources then (.status.resources | map(select(.status == "OutOfSync" and .health.status == "Missing" and (.hook == null or .hook == false))) | length) else 0 end) Changed:\(if .status.resources then (.status.resources | map(select(.status == "OutOfSync" and .health.status != "Missing" and .requiresPruning == null and (.hook == null or .hook == false))) | length) else 0 end) RequiredPruning:\(if .status.resources then (.status.resources | map(select(.requiresPruning == true and (.hook == null or .hook == false))) | length) else 0 end)"'`
  if [ $? -ne 0 ]
  then
    echo "Failed to refresh ArgoCD Application $app_name!"
    exit 25
  fi
else
  if [ $APP_EXISTED == "no" ]
  then
    retry_count=0
    while [ $retry_count -lt 50 ]; do
      APPSTATUS=$(kubectl get applications.argoproj.io -n ${ARGOCD_NAMESPACE} $app_name -o json | jq -r '.status.sync.status // "null"')
      # Check if the result is not "null"
      if [ "$APPSTATUS" != "null" ] && [ -n "$APPSTATUS" ]; then
        break
      fi    
      echo "Waiting for ArgoCD to process $app_name application. Status is Null."
      sleep 6
      retry_count=$((retry_count + 1))
    done
  fi

  STATUS=`kubectl get applications.argoproj.io -n ${ARGOCD_NAMESPACE} $app_name -o json | jq -r '"Status:\(.status.sync.status) Missing:\(if .status.resources then (.status.resources | map(select(.status == "OutOfSync" and .health.status == "Missing" and (.hook == null or .hook == false))) | length) else 0 end) Changed:\(if .status.resources then (.status.resources | map(select(.status == "OutOfSync" and .health.status != "Missing" and .requiresPruning == null and (.hook == null or .hook == false))) | length) else 0 end) RequiredPruning:\(if .status.resources then (.status.resources | map(select(.requiresPruning == true and (.hook == null or .hook == false))) | length) else 0 end)"'`
  if [ $? -ne 0 ]
  then
    echo "Failed to get ArgoCD Application $app_name!"
    exit 26
  fi
fi

echo "Status $app_name $STATUS"
if [ "$STATUS" != "Status:Synced Missing:0 Changed:0 RequiredPruning:0" ]
then
  touch $app_file.sync
  if [ "$APP_EXISTED" == "yes" -a "$USE_ARGOCD_CLI" == "true" ]
  then
    argocd --server ${ARGOCD_HOSTNAME} --grpc-web app diff --exit-code=false $app_name
  fi
fi
echo "###############"
