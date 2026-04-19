# Updating Image Tag and Environment Variables with CI/CD

## Overview

This project uses AWS SSM Parameter Store as the single source of truth for the Docker image tag and environment variables. Deploying a new version does **not** require changes to Terraform -- you update the SSM parameter values and trigger an ASG instance refresh.

SSM parameters for each app live under the prefix `/<project_name>/<environment>/<app_name>`. The examples below use `/myproject/production/myapp` and an ASG named `myproject-production-myapp-asg`.

## How It Works

1. **SSM Parameter Store** holds the Docker image repository, tag, and all environment variables
2. **Terraform** creates these parameters initially but uses `lifecycle { ignore_changes = [value] }`, so CI/CD can update values without Terraform reverting them
3. **User data script** on each instance reads SSM parameters at boot time
4. **Instance refresh** replaces instances in a rolling fashion; new instances read the updated SSM values

## Deployment Workflow

### Step 1: Build and Push Docker Image

```bash
# Build the image
docker build -t myapp:v1.2.3 .

# Tag for ECR
docker tag myapp:v1.2.3 123456789012.dkr.ecr.ap-southeast-3.amazonaws.com/myapp:v1.2.3

# Authenticate to ECR
aws ecr get-login-password --region ap-southeast-3 | \
  docker login --username AWS --password-stdin 123456789012.dkr.ecr.ap-southeast-3.amazonaws.com

# Push
docker push 123456789012.dkr.ecr.ap-southeast-3.amazonaws.com/myapp:v1.2.3
```

### Step 2: Update SSM Parameter

```bash
# Update image tag
aws ssm put-parameter \
  --name "/myproject/production/myapp/docker-image-tag" \
  --value "v1.2.3" \
  --type String \
  --overwrite
```

### Step 3: Trigger Instance Refresh

```bash
aws autoscaling start-instance-refresh \
  --auto-scaling-group-name myproject-production-myapp-asg \
  --preferences '{"MinHealthyPercentage": 50, "InstanceWarmup": 300}'
```

### Step 4: Monitor Deployment

```bash
# Poll until status is "Successful"
aws autoscaling describe-instance-refreshes \
  --auto-scaling-group-name myproject-production-myapp-asg \
  --query 'InstanceRefreshes[0].{Status:Status,PercentageComplete:PercentageComplete}'
```

## Updating Environment Variables

```bash
# Update a single environment variable
aws ssm put-parameter \
  --name "/myproject/production/myapp/env/DATABASE_URL" \
  --value "postgresql://newhost:5432/db" \
  --type SecureString \
  --overwrite

# Then trigger instance refresh (same as above)
aws autoscaling start-instance-refresh \
  --auto-scaling-group-name myproject-production-myapp-asg \
  --preferences '{"MinHealthyPercentage": 50, "InstanceWarmup": 300}'
```

## Adding New Environment Variables

```bash
# Create a new SSM parameter under the /env/ path
aws ssm put-parameter \
  --name "/myproject/production/myapp/env/NEW_VARIABLE" \
  --value "some-value" \
  --type SecureString

# Trigger instance refresh to pick up the new variable
aws autoscaling start-instance-refresh \
  --auto-scaling-group-name myproject-production-myapp-asg \
  --preferences '{"MinHealthyPercentage": 50, "InstanceWarmup": 300}'
```

## Jenkins Pipeline Example

```groovy
pipeline {
    agent any

    environment {
        AWS_REGION       = 'ap-southeast-3'
        ECR_REGISTRY     = '123456789012.dkr.ecr.ap-southeast-3.amazonaws.com'
        ECR_REPO         = 'myapp'
        SSM_PREFIX       = '/myproject/production/myapp'
        ASG_NAME         = 'myproject-production-myapp-asg'
        IMAGE_TAG        = "${env.BUILD_NUMBER}-${env.GIT_COMMIT?.take(7)}"
    }

    stages {
        stage('Build') {
            steps {
                script {
                    docker.build("${ECR_REPO}:${IMAGE_TAG}")
                }
            }
        }

        stage('Push to ECR') {
            steps {
                sh """
                    aws ecr get-login-password --region ${AWS_REGION} | \
                        docker login --username AWS --password-stdin ${ECR_REGISTRY}
                    docker tag ${ECR_REPO}:${IMAGE_TAG} ${ECR_REGISTRY}/${ECR_REPO}:${IMAGE_TAG}
                    docker push ${ECR_REGISTRY}/${ECR_REPO}:${IMAGE_TAG}
                """
            }
        }

        stage('Update SSM') {
            steps {
                sh """
                    aws ssm put-parameter \
                        --name "${SSM_PREFIX}/docker-image-tag" \
                        --value "${IMAGE_TAG}" \
                        --type String \
                        --overwrite \
                        --region ${AWS_REGION}
                """
            }
        }

        stage('Deploy') {
            steps {
                sh """
                    aws autoscaling start-instance-refresh \
                        --auto-scaling-group-name ${ASG_NAME} \
                        --preferences '{"MinHealthyPercentage": 50, "InstanceWarmup": 300}' \
                        --region ${AWS_REGION}
                """
            }
        }

        stage('Wait for Deployment') {
            steps {
                script {
                    def status = ''
                    def maxRetries = 30
                    def retryCount = 0

                    while (status != 'Successful' && retryCount < maxRetries) {
                        sleep(30)
                        status = sh(
                            script: """
                                aws autoscaling describe-instance-refreshes \
                                    --auto-scaling-group-name ${ASG_NAME} \
                                    --region ${AWS_REGION} \
                                    --query 'InstanceRefreshes[0].Status' \
                                    --output text
                            """,
                            returnStdout: true
                        ).trim()

                        echo "Instance refresh status: ${status}"
                        retryCount++

                        if (status == 'Failed' || status == 'Cancelled') {
                            error("Instance refresh ${status}")
                        }
                    }

                    if (status != 'Successful') {
                        error("Instance refresh timed out")
                    }
                }
            }
        }
    }

    post {
        failure {
            echo 'Deployment failed. Check ASG instance refresh status and CloudWatch logs.'
        }
        success {
            echo "Successfully deployed ${IMAGE_TAG}"
        }
    }
}
```

## Important Notes

- **Update SSM before triggering instance refresh**: If you trigger the refresh before updating SSM, new instances will launch with the old image tag.
- **No Terraform changes needed**: The `lifecycle { ignore_changes = [value] }` block ensures Terraform does not revert SSM parameter values updated by CI/CD.
- **Rollback**: To rollback, update the SSM image tag to the previous version and trigger another instance refresh.
- **Concurrent refreshes**: Only one instance refresh can run at a time per ASG. A new refresh request while one is in progress will be rejected.
- **Image availability**: Ensure the Docker image is fully pushed to ECR before updating the SSM parameter, otherwise new instances will fail to pull.
