# Updating with CI/CD

SSM Parameter Store = single source of truth for image tag + env vars. Deploy = update SSM + trigger instance refresh. No Terraform needed.

SSM prefix: `/<project_name>/<environment>/<app_name>`. Examples use `/myproject/production/myapp` and ASG `myproject-production-myapp-asg`.

## How It Works

1. **SSM** holds Docker image repo, tag, all env vars.
2. `app` module creates SSM params with `lifecycle { ignore_changes = [value] }` — CI/CD updates won't get reverted by `terragrunt apply`.
3. **User data** reads SSM at boot.
4. **Instance refresh** rolls new instances that read updated SSM values.

## Deployment Steps

### Step 1: Build + Push Image

```bash
docker build -t myapp:v1.2.3 .
docker tag myapp:v1.2.3 123456789012.dkr.ecr.ap-southeast-3.amazonaws.com/myapp:v1.2.3

aws ecr get-login-password --region ap-southeast-3 | \
  docker login --username AWS --password-stdin 123456789012.dkr.ecr.ap-southeast-3.amazonaws.com

docker push 123456789012.dkr.ecr.ap-southeast-3.amazonaws.com/myapp:v1.2.3
```

### Step 2: Update SSM

```bash
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

### Step 4: Monitor

```bash
aws autoscaling describe-instance-refreshes \
  --auto-scaling-group-name myproject-production-myapp-asg \
  --query 'InstanceRefreshes[0].{Status:Status,PercentageComplete:PercentageComplete}'
```

## Update Env Vars

```bash
aws ssm put-parameter \
  --name "/myproject/production/myapp/env/DATABASE_URL" \
  --value "postgresql://newhost:5432/db" \
  --type SecureString \
  --overwrite

aws autoscaling start-instance-refresh \
  --auto-scaling-group-name myproject-production-myapp-asg \
  --preferences '{"MinHealthyPercentage": 50, "InstanceWarmup": 300}'
```

## Add New Env Var

```bash
aws ssm put-parameter \
  --name "/myproject/production/myapp/env/NEW_VARIABLE" \
  --value "some-value" \
  --type SecureString

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

- **Update SSM before refresh** — refresh before SSM update = new instances pull old image.
- **No Terraform changes** — `lifecycle { ignore_changes = [value] }` blocks revert.
- **Rollback** — set SSM image tag to previous version, trigger refresh.
- **Concurrent refreshes** — one at a time per ASG. New request while one runs = rejected.
- **Image must exist in ECR** before updating SSM param — new instances fail to pull otherwise.
