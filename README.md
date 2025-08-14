# Assignment for DevOps Engineer - AdCash

# Part I

## Overview

For this project, we selected Amazon Web Services (AWS) as our cloud provider for the following reasons:

- **Managed Kubernetes with EKS**: AWS Elastic Kubernetes Service (EKS) offers a fully managed control plane, reducing operational overhead and simplifying cluster setup and maintenance.
- **Global Infrastructure**: AWS provides reliable infrastructure across multiple regions, including `eu-north-1`, offering competitive pricing and low latency for European users.
- **Security & Compliance**: AWS delivers robust security features, including IAM integration, VPC isolation, and compliance with major standards—essential for production-ready environments.
- **Ecosystem Integration**: Seamless integration with other AWS services (e.g., IAM, CloudWatch, S3) allows for future expansion and tighter control over infrastructure.

We selected the `t3.small` instance type for our EKS cluster based on the following considerations:

- **Cost Efficiency**: Ideal for small-scale workloads and development environments.
- **Burstable Performance**: T3 instances provide baseline CPU performance with the ability to burst during short periods of increased demand.
- **Right-Sized Resources**: With 2 vCPUs and 2 GiB memory, `t3.small` provides enough capacity for our lightweight Kubernetes service.
- **Scalable Foundation**: The cluster is configured with 2–3 nodes, allowing basic horizontal scaling while keeping infrastructure lean.

This setup prioritizes simplicity, reliability, and cost control—suitable for projects that don't require heavy compute or monitoring tools like Prometheus at this stage.

## Prerequisites
Before deploying, ensure the following are installed and configured:

* AWS CLI, `kubectl`, and Terraform
* Access to the EKS cluster (`kubectl get nodes`)
* Target AWS region: **eu-north-1**

## Creating EKS cluster

```bash
eksctl create cluster \
  --name gandalf-cluster \
  --region eu-north-1 \
  --nodegroup-name standard-workers \
  --node-type t3.small \
  --nodes 2 \
  --nodes-min 2 \
  --nodes-max 3 \
  --managed
```
Check AWS Console -> CloudFormation -> find `eksctl-gandalf-cluster-cluster`,
or run:
```bash
aws eks describe-cluster --name gandalf-cluster --region eu-central-1
````
## Project structure

```bash
gandalf-app/
├── src/
│   └── main/
│       ├── java/com/example/gandalfapp/
│       │   ├── GandalfAppApplication.java  # Main class Spring Boot
│       │   ├── GandalfController.java      # REST-controller
│       └── resources/
│           ├── application.properties      # Config
│           └── static/gandalf.jpg          # Image
├── pom.xml                                 # Maven dependencies
├── Dockerfile                              # Image build
└── README.md
```

## Description
Spring Boot application with endpoints:
- `/gandalf` - returns Gandalf image.
- `/colombo` - returns current time in Colombo, Sri Lanka.

The project uses built-in Prometheus exporter through Spring Boot Actuator и Micrometer.

Metrics:
- `gandalf_requests_total`
- `colombo_requests_total`

## Build and deploy

### Building application
```bash
cd gandalf-app
mvn package
java -jar target/gandalfapp-0.0.1-SNAPSHOT.jar
```

### Docker build (multi-stage, Java 21 + slim runtime)
Docker Build (multi-stage, Java 21 + slim runtime)
- Stage 1 (build): includes JDK, Maven, source code (~600–700 MB)
- Stage 2 (runtime): only final JAR, ~90–100 MB
- Alpine JRE used for minimal image size
- Dependency caching enabled for faster rebuilds

```bash
docker build -t gandalf-app .
docker run -p 80:80 gandalf-app
```

### Check service
``curl http://localhost:80/gandalf --output g.png``

``curl http://localhost:80/colombo``

### Create ECR repository
```bash
aws ecr create-repository --repository-name gandalf-app --region eu-north-1
```

### Login push the image
```bash
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)

aws ecr get-login-password --region eu-north-1 \
| docker login --username AWS --password-stdin ${ACCOUNT_ID}.dkr.ecr.eu-north-1.amazonaws.com

docker tag gandalf-app:latest ${ACCOUNT_ID}.dkr.ecr.eu-north-1.amazonaws.com/gandalf-app:latest
docker push ${ACCOUNT_ID}.dkr.ecr.eu-north-1.amazonaws.com/gandalf-app:latest
```

### Reserve Elastic IP
```bash
aws ec2 allocate-address --region eu-north-1
```
Check output for `AllocationId` and `PublicIp`.

## Kubernetes deployment

### Update `kubectl` Context
```bash
aws eks --region eu-north-1 update-kubeconfig --name gandalf-cluster
```

### Apply kubernetes manifest
```bash
kubectl apply -f gandalf-app.yaml
```

### Verify service
```bash
kubectl get svc gandalf-lb
kubectl describe svc gandalf-lb
```
- Check IAM permissions, Elastic IP allocation, and subnet/AZ configuration
- Ensure EIP is in the same region and not attached elsewhere

### Create Image Pull Secret
Create the imagePullSecret
```bash
kubectl create secret docker-registry ecr-secret \
  --docker-server=024585201184.dkr.ecr.eu-north-1.amazonaws.com \
  --docker-username=AWS \
  --docker-password=$(aws ecr get-login-password --region eu-north-1)
```

### Test Endpoints

```bash
curl http://<external-IP>/gandalf
curl http://<external-IP>/colombo
curl http://<external-IP>/actuator/prometheus
```

> ⚠️ **Important:**  
> The endpoints are exposed via a LoadBalancer, which means actuator metrics may differ between individual pods. Each pod maintains its own state, so data like request counts or health indicators can vary depending on which pod the LoadBalancer routes your request to.


### Clean Up
```eksctl delete cluster --name gandalf-cluster --region eu-north-1```

## Part II - Prometheus Monitoring

## Overview

Prometheus can monitor workloads in EKS from a VM inside the same VPC using several discovery methods:

### Kubernetes API Service Discovery (role: pod)

- Prometheus queries the Kubernetes API to dynamically discover pods 
- Requires kubeconfig and RBAC 
- Pros: fully dynamic, label filtering 
- Cons: more complex, requires credentials

### ClusterIP or NodePort Service
- Scrape a single service endpoint
- Pros: simple setup 
- Cons: no per-pod metrics, uneven scraping possible

### Headless Service (clusterIP: None) — Chosen Method
- DNS resolves to all pod IPs
- Pros: per-pod metrics, no kubeconfig, simple
- Cons: requires VM network access to pods and internal DNS

### ServiceMonitor (Prometheus Operator)
- Prometheus in-cluster with Operator automatically discovers targets
- Pros: fully managed, dynamic
- Cons: requires Operator, in-cluster Prometheus only

### Reason for Choosing Headless Service
- Prometheus VM can reach pod IPs directly
- No kubeconfig required
- Easy to maintain and configure
- DNS-based discovery adapts automatically to scaling

## Terraform-Based Prometheus Deployment
### Prerequisites

- AWS account with EKS cluster (`gandalf-cluster`) running Gandalf App.
- Terraform installed on your local machine or Prometheus VM.
- Network access from Prometheus VM to EKS pod subnets.

### Project structure

```bash
terraform-prometheus/
│
├── main.tf          # Main AWS resources: EC2 instance, Security Group
├── variables.tf     # Variables like region, AMI, key_name
└── outputs.tf       # Output public IP of Prometheus
```
### Step 1: Create Headless Service
`gandalf-headless.yaml`

```yaml
apiVersion: v1
kind: Service
metadata:
  name: gandalf-headless
  namespace: default
spec:
  clusterIP: None
  selector:
    app: gandalf
  ports:
    - port: 80
      targetPort: 80
      name: http
```
```bash
kubectl apply -f gandalf-headless.yaml
```

### Step 2: Terraform variables (`variables.tf`)

```
variable "vpc_id" {}
variable "subnet_id" {} # Choose a subnet in the same VPC as your EKS cluster
variable "key_name" {}
variable "allow_ingress_cidrs_to_prom" {
  default = ["0.0.0.0/0"] # Change to restrict access
}
```
### Step 3: Terraform Main (`main.tf`)

```tf
provider "aws" {
  region = "eu-north-1"
}

resource "aws_security_group" "prom_sg" {
  name   = "prometheus-sg"
  vpc_id = var.vpc_id

  ingress {
    description = "Prometheus HTTP"
    from_port   = 9090
    to_port     = 9090
    protocol    = "tcp"
    cidr_blocks = var.allow_ingress_cidrs_to_prom
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_instance" "prometheus" {
  ami                    = "ami-0f326728ed51c4b5a" # Amazon Linux 2 latest
  instance_type          = "t3.micro"
  subnet_id              = var.subnet_id
  key_name               = var.key_name
  vpc_security_group_ids = [aws_security_group.prom_sg.id]

  user_data = <<-EOF
              #!/bin/bash
              yum update -y
              yum install -y wget tar

              cd /opt
              wget https://github.com/prometheus/prometheus/releases/download/v2.48.0/prometheus-2.48.0.linux-amd64.tar.gz
              tar xvf prometheus-2.48.0.linux-amd64.tar.gz
              cd prometheus-2.48.0.linux-amd64

              # Create Prometheus config
              cat > prometheus.yml <<EOL
              global:
                scrape_interval: 15s
              scrape_configs:
                - job_name: 'gandalf-app'
                  static_configs:
                    - targets:
                      - 'gandalf-headless.default.svc.cluster.local:80'
              EOL

              # Run Prometheus in background
              ./prometheus --config.file=prometheus.yml &
              EOF

  tags = {
    Name = "Prometheus-VM"
  }
}
```
### Step 4: Terraform Outputs (`outputs.tf`)
```tf
output "prometheus_public_ip" {
  value = aws_instance.prometheus.public_ip
}
```

### Step 5: Choose the Subnet for Prometheus VM

Terraform requires an explicit subnet. Pick one in the same VPC as your EKS cluster:
```bash
aws eks describe-cluster --name gandalf-cluster --query "cluster.resourcesVpcConfig.subnetIds" --output text
```
Select a subnet used by EKS nodes.

### Step 6: Initialize and Apply Terraform
```bash
cd terraform-prometheus
terraform init
terraform apply -var "vpc_id=<VPC_ID>" \
-var "subnet_id=<SUBNET_ID>" \
-var "key_name=<YOUR_KEYPAIR>" \
-var "allow_ingress_cidrs_to_prom=[\"0.0.0.0/0\"]"
```
Terraform will output the Prometheus VM public IP.

### Step 7: Optional Security Considerations

- Avoid using 0.0.0.0/0 for ingress in production. 
- Optionally, put a reverse proxy (Nginx, Traefik) with basic auth in front of Prometheus if exposing publicly.

### Step 8: Clean Up

Delete Prometheus VM and resources via Terraform:
```bash
terraform destroy -var "vpc_id=<VPC_ID>" \
-var "subnet_id=<SUBNET_ID>" \
-var "key_name=<YOUR_KEYPAIR>"
```
Delete the Headless Service:
```bash
kubectl delete -f gandalf-headless.yaml
```

## Advantages of Headless Service

- No kubeconfig or Kubernetes API credentials required.
- Provides per-pod metrics for accurate monitoring.
- DNS-based discovery automatically adapts to pod scaling.
- Fully automated, maintainable solution for Prometheus outside the cluster.