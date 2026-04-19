# Autoscaling Behavior

ASG manages EC2 instances running Docker containers behind ALB. Each instance reads image tag + env vars from SSM at boot — all instances consistent even if SSM updated after last `terraform apply`.

## Scale-Out (Adding Instances)

When ASG desired capacity increases (manual or future scaling policy):

1. **ASG launches EC2** from launch template with pre-baked AMI.

2. **User data runs**:
   - Tags itself `<asg-name>-<last-4-of-instance-id>`
   - Authenticates to ECR
   - Reads image repo + tag from SSM
   - Reads all env vars from SSM (`SecureString`, decrypted)
   - Pulls + starts Docker container with env vars

3. **Health check grace period** (default 300s) — ASG ignores ALB health failures during this window.

4. **ALB health check probes**:
   - `GET` to configured health check path (default `/health`)
   - 3 consecutive `200` responses at 30s intervals
   - Min ~90s after app starts responding

5. **Instance goes InService** — ALB routes traffic.

## Scale-In (Removing Instances)

When ASG desired capacity decreases:

1. **ASG selects instance** via termination policies:
   - AZ with most instances first (balance)
   - Oldest launch template version
   - Instance closest to next billing hour

2. **ALB deregistration**:
   - Instance removed from target group
   - 300s delay — in-flight requests drain
   - No new requests routed during delay

3. **Instance terminates** after delay.

## AZ Rebalancing

ASG auto-maintains even distribution across AZs. If AZ unavailable or instances skewed:
- Launches in underrepresented AZs
- May terminate in overrepresented AZs
- Respects grace period + deregistration delay

## Instance Refresh (Rolling Updates)

Primary deploy mechanism. Replaces all instances in controlled rolling fashion.

When triggered:

1. ASG calculates batch size based on `min_healthy_percentage` (default 50%)
2. Terminates batch
3. Launches replacements from current launch template
4. Waits for replacements to pass health checks + warm up
5. Repeats until all instances replaced
6. Reports `Successful`

**Trigger:**

```bash
aws autoscaling start-instance-refresh \
  --auto-scaling-group-name <asg-name> \
  --preferences '{"MinHealthyPercentage": 50, "InstanceWarmup": 300}'
```

**Monitor:**

```bash
aws autoscaling describe-instance-refreshes \
  --auto-scaling-group-name <asg-name>
```

## Health Check Config

| Setting | Value | Purpose |
|---------|-------|---------|
| Health check type | ELB | Uses ALB check, not basic EC2 status |
| Grace period | 300s | Ignore failures after launch |
| Health check path | `/health` | ALB probes here |
| Healthy threshold | 3 | Consecutive successes needed |
| Unhealthy threshold | 3 | Consecutive failures before unhealthy |
| Check interval | 30s | Time between checks |
| Matcher | 200 | Only HTTP 200 = healthy |

## Self-Healing

If running instance fails (app crash, instance failure):

1. ALB detects 3 consecutive failures
2. ALB stops routing to instance
3. ASG marks instance unhealthy
4. ASG terminates instance
5. ASG launches replacement (follows scale-out process)

No human involvement needed.
