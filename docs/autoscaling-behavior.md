# How Autoscaling Works in This Project

## Overview

This project uses an AWS Auto Scaling Group (ASG) to manage EC2 instances running containerized web applications behind an Application Load Balancer (ALB). Each instance pulls its Docker image tag and environment variables from AWS SSM Parameter Store at boot time, ensuring consistency across all instances.

## Scale-Out (Adding Instances)

When the ASG desired capacity increases (manually or via a future scaling policy):

1. **ASG launches a new EC2 instance** from the launch template, using the pre-baked AMI (Docker, AWS CLI, node_exporter pre-installed).

2. **User data script executes** on the new instance:
   - Tags itself with a Name following the format `<asg-name>-<last-4-digits-of-instance-id>`
   - Authenticates to Amazon ECR
   - Reads the current Docker image repository and tag from SSM Parameter Store
   - Reads all environment variables from SSM Parameter Store (SecureString, decrypted)
   - Pulls and starts the Docker container with all environment variables

3. **Health check grace period** (default: 300 seconds) begins. During this period, the ASG ignores health check failures from the ALB, giving the application time to start.

4. **ALB target group health check** probes the application:
   - Sends `GET` requests to the configured health check path (default: `/health`)
   - Requires 3 consecutive successful responses (HTTP 200) at 30-second intervals
   - Minimum time to become healthy: ~90 seconds after the app starts responding

5. **Instance becomes InService** once the ALB health check passes. The ALB begins routing traffic to the new instance.

**Key guarantee**: Because the new instance reads the image tag and environment variables from SSM Parameter Store at boot time (not from the Terraform configuration), it will always use the same configuration as existing instances -- even if SSM values were updated after the last `terraform apply`.

## Scale-In (Removing Instances)

When the ASG desired capacity decreases:

1. **ASG selects an instance for termination** based on the configured termination policies. The default policy:
   - First, selects the AZ with the most instances (to maintain balance)
   - Then, selects the instance with the oldest launch template version
   - Then, selects the instance closest to the next billing hour

2. **ALB deregistration begins**:
   - The instance is removed from the target group
   - A deregistration delay (default: 300 seconds) allows in-flight requests to complete
   - No new requests are routed to the instance during this period

3. **Instance is terminated** after the deregistration delay expires.

## Availability Zone Rebalancing

The ASG automatically maintains an even distribution of instances across the configured Availability Zones. If an AZ becomes unavailable or instances are unevenly distributed:

- The ASG launches new instances in underrepresented AZs
- It may terminate instances in overrepresented AZs
- This process respects the health check grace period and deregistration delay

## Instance Refresh (Rolling Updates)

Instance refresh replaces all instances in a controlled, rolling fashion. This is the primary mechanism for deploying new versions.

When triggered (via AWS CLI or Console):

1. ASG calculates how many instances can be replaced while maintaining the `min_healthy_percentage` (default: 50%)
2. Terminates a batch of instances
3. Launches replacement instances from the current launch template
4. Waits for replacements to pass health checks and warm up
5. Repeats until all instances are replaced
6. Reports `Successful` when complete

**Trigger an instance refresh:**

```bash
aws autoscaling start-instance-refresh \
  --auto-scaling-group-name <asg-name> \
  --preferences '{"MinHealthyPercentage": 50, "InstanceWarmup": 300}'
```

**Monitor progress:**

```bash
aws autoscaling describe-instance-refreshes \
  --auto-scaling-group-name <asg-name>
```

## Health Check Configuration

| Setting | Value | Purpose |
|---------|-------|---------|
| Health check type | ELB | Uses ALB health check instead of basic EC2 status |
| Grace period | 300s | Time to ignore failures after launch |
| Health check path | `/health` | HTTP endpoint the ALB probes |
| Healthy threshold | 3 | Consecutive successes needed |
| Unhealthy threshold | 3 | Consecutive failures before marking unhealthy |
| Check interval | 30s | Time between health checks |
| Matcher | 200 | Only HTTP 200 counts as healthy |

## What Happens When an Instance Fails

If a running instance becomes unhealthy (app crashes, instance fails):

1. ALB health check detects 3 consecutive failures
2. ALB stops routing traffic to the instance
3. ASG marks the instance as unhealthy
4. ASG terminates the unhealthy instance
5. ASG launches a replacement instance (following the scale-out process above)

This self-healing behavior maintains the desired capacity automatically.
