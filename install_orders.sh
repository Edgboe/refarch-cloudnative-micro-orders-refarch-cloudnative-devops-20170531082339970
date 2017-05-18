#!/bin/bash
# Terminal Colors
red=$'\e[1;31m'
grn=$'\e[1;32m'
yel=$'\e[1;33m'
blu=$'\e[1;34m'
mag=$'\e[1;35m'
cyn=$'\e[1;36m'
end=$'\e[0m'
coffee=$'\xE2\x98\x95'
coffee3="${coffee} ${coffee} ${coffee}"

API="api.ng.bluemix.net"
CLUSTER_NAME=$1
SPACE=$2
API_KEY=$3

function check_tiller {
	kubectl --namespace=kube-system get pods | grep tiller | grep Runnin
}

function bluemix_login {
	# Bluemix Login
	printf "${grn}Login into Bluemix${end}\n"
	if [[ -z "${API_KEY// }" && -z "${SPACE// }" ]]; then
		echo "${yel}API Key & SPACE NOT provided.${end}"
		bx login -a ${API}

	elif [[ -z "${SPACE// }" ]]; then
		echo "${yel}API Key provided but SPACE was NOT provided.${end}"
		export BLUEMIX_API_KEY=${API_KEY}
		bx login -a ${API}

	elif [[ -z "${API_KEY// }" ]]; then
		echo "${yel}API Key NOT provided but SPACE was provided.${end}"
		bx login -a ${API} -s ${SPACE}

	else
		echo "${yel}API Key and SPACE provided.${end}"
		export BLUEMIX_API_KEY=${API_KEY}
		bx login -a ${API} -s ${SPACE}
	fi

	status=$?

	if [ $status -ne 0 ]; then
		printf "\n\n${red}Bluemix Login Error... Exiting.${end}\n"
		exit 1
	fi
}

function create_api_key {
	# Creating for API KEY
	if [[ -z "${API_KEY// }" ]]; then
		printf "\n\n${grn}Creating API KEY...${end}\n"
		API_KEY=$(bx iam api-key-create kubekey | tail -1 | awk '{print $3}')
		echo "${yel}API key 'kubekey' was created.${end}"
		echo "${mag}Please preserve the API key! It cannot be retrieved after it's created.${end}"
		echo "${cyn}Name${end}	kubekey"
		echo "${cyn}API Key${end}	${API_KEY}"
	fi
}

function get_cluster_name {
	printf "\n\n${grn}Login into Container Service${end}\n\n"
	bx cs init

	if [[ -z "${CLUSTER_NAME// }" ]]; then
		echo "${yel}No cluster name provided. Will try to get an existing cluster...${end}"
		CLUSTER_NAME=$(bx cs clusters | tail -1 | awk '{print $1}')

		if [[ "$CLUSTER_NAME" == "Name" ]]; then
			echo "No Kubernetes Clusters exist in your account. Please provision one and then run this script again."
			exit 1
		fi
	fi
}

function set_cluster_context {
	# Getting Cluster Configuration
	unset KUBECONFIG
	printf "\n${grn}Setting terminal context to \"${CLUSTER_NAME}\"...${end}\n"
	eval "$(bx cs cluster-config ${CLUSTER_NAME} | tail -1)"
	echo "KUBECONFIG is set to = $KUBECONFIG"

	if [[ -z "${KUBECONFIG// }" ]]; then
		echo "${red}KUBECONFIG was not properly set. Exiting.${end}"
		exit 1
	fi
}

function initialize_helm {
	printf "\n\n${grn}Initializing Helm.${end}\n"
	helm init --upgrade
	echo "Waiting for Tiller (Helm's server component) to be ready..."

	TILLER_DEPLOYED=$(check_tiller)
	while [[ "${TILLER_DEPLOYED}" == "" ]]; do 
		sleep 1
		TILLER_DEPLOYED=$(check_tiller)
	done
}

function install_orders {
	printf "\n\n${grn}Getting Account Information...${end}\n"
	ORG=$(cat ~/.bluemix/.cf/config.json | jq .OrganizationFields.Name | sed 's/"//g')
	SPACE=$(cat ~/.bluemix/.cf/config.json | jq .SpaceFields.Name | sed 's/"//g')

	cd chart/bluecompute-orders

	printf "\n\n${grn}Installing Orders Application. This will take a few minutes...${end} ${coffee3}\n\n"
	time helm install --name orders \
	--set configMap.bluemixOrg=${ORG} \
	--set configMap.bluemixSpace=${SPACE} \
	--set configMap.kubeClusterName=${CLUSTER_NAME} \
	--set secret.apiKey=${API_KEY} \
	. --debug --wait --timeout 600

	printf "\n\n${grn}Orders was successfully installed!${end}\n"
	printf "\n\n${grn}Cleaning up...${end}\n"
	kubectl delete pods,jobs -l heritage=Tiller

	cd ..
}

# Setup Stuff
bluemix_login
create_api_key
get_cluster_name
set_cluster_context
initialize_helm

# Install Orders Chart
install_orders

printf "\n\nTo see Kubernetes Dashboard, paste the following in your terminal:\n"
echo "${cyn}export KUBECONFIG=${KUBECONFIG}${end}"

printf "\nThen run this command to connect to Kubernetes Dashboard:\n"
echo "${cyn}kubectl proxy${end}"

printf "\nThen open a browser window and paste the following URL to see the Services created by Orders Chart:\n"
echo "${cyn}http://127.0.0.1:8001/api/v1/proxy/namespaces/kube-system/services/kubernetes-dashboard/#/service?namespace=default${end}"