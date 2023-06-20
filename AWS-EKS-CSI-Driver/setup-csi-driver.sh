#!/bin/sh

# This script can be used to setup EBS csi driver on an EKS cluster
# The script assumes AWS-CLI, kubectl, and eksctl are installed on the system before running this script

read -p 'Enter the Cluster Name : ' clustername

export CLUSTER_NAME=$clustername

echo -e "\nCluster Name is: ${CLUSTER_NAME}"
echo -e "\nIf you want to proceed with above informaton, type \"yes\" or \"no\": " 
read value

if [ $value == "yes" ]
then
   
    #Create an OIDC provider for the cluster
    export OIDC_ID=$(aws eks describe-cluster --name ${CLUSTER_NAME} --query "cluster.identity.oidc.issuer" --output text | cut -d '/' -f 5)
    echo ${OIDC_ID}
    export CHECK=$(aws iam list-open-id-connect-providers | grep ${OIDC_ID})
    
    if [ -z "$CHECK" ]
    then
          eksctl utils associate-iam-oidc-provider --cluster $CLUSTER_NAME --approve
    else
          echo "\$OIDC Provider already exists"
    fi
    

    Create an IAM-POLICY and extract POLICY_ARN
    curl https://raw.githubusercontent.com/shamimice03/AWS_EKS-EBS_CSI/main/AwsEBSCSIDriverPolicy.json > ebs_csi_policy.json
    
    aws iam create-policy \
    --policy-name AwsEBSCSIDriverPolicy \
    --policy-document file://ebs_csi_policy.json

     
    export POLICY_ARN=$(aws iam list-policies --query 'Policies[?PolicyName==`AwsEBSCSIDriverPolicy`].Arn' --output text)
    echo ${POLICY_ARN}


    #Configure IAM Role for Service Account
    export ROLE_NAME='AmazonEKSEBSCSIDriverRole'
    export SA_NAME='ebs-csi-controller-sa'
    eksctl create iamserviceaccount \
        --name ${SA_NAME} \
        --cluster ${CLUSTER_NAME} \
        --attach-policy-arn=${POLICY_ARN} \
        --role-name ${ROLE_NAME} \
        --namespace kube-system \
        --approve \
        --override-existing-serviceaccounts

    #Save the "ROLE_ARN" as an environment variable
    export ROLE_ARN=$(aws iam list-roles --query 'Roles[?RoleName==`AmazonEKSEBSCSIDriverRole`].Arn' --output text)

    #Install CSI
    eksctl create addon \
    --name aws-ebs-csi-driver \
    --cluster ${CLUSTER_NAME} \
    --service-account-role-arn ${ROLE_ARN} \
    --force

   cat <<EOF | kubectl create -f - 
   apiVersion: storage.k8s.io/v1
   kind: StorageClass
   metadata:
     name: ebs-gp2-sc
     annotations: 
       storageclass.kubernetes.io/is-default-class: "true"   # Make this storageClass as Default
   provisioner: ebs.csi.aws.com   # Amazon EBS CSI driver
   parameters:
     type: gp2
     encrypted: 'true'   # EBS volumes will always be encrypted by default
   volumeBindingMode: WaitForFirstConsumer
   reclaimPolicy: Delete
EOF

else
    echo -e "Exiting..bye.\n" 
    exit
fi
