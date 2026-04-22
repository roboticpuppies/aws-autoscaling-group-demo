# Autoscaling Behavior

ASG manages EC2 instances running Docker containers. Each instance attaches to a per-app target group whose health checks drive ASG self-healing. No ALB is provisioned — the target group is there purely to give the ASG an `ELB` health-check source. Each instance reads its image tag + env vars from SSM at boot — all instances stay consistent even if SSM was updated after the last `terraform apply`.

## Scale-Out (Adding Instances)

When ASG desired capacity increases (manual or future scaling policy):

1. **ASG launches EC2** from launch template with pre-baked AMI.

2. **User data runs**:
   - Tags itself `<asg-name>-<last-4-of-instance-id>`
   - Authenticates to ECR
   - Reads image repo + tag from SSM
   - Reads all env vars from SSM (`SecureString`, decrypted)
   - Pulls + starts Docker container with env vars
   - Signals `CONTINUE` to the launch lifecycle hook

3. **ASG attaches instance to target group** (triggered by the `CONTINUE`).

4. **Health check grace period** (default 300s) — ASG ignores TG health failures during this window.

5. **Target group probes**:
   - `GET` to configured health check path (default `/health`) on `app_port`
   - 3 consecutive `200` responses at 30s intervals
   - Min ~90s after app starts responding

6. **Instance goes InService** — ASG considers it healthy.

## Scale-In (Removing Instances)

When ASG desired capacity decreases:

1. **ASG selects instance** via termination policies:
   - AZ with most instances first (balance)
   - Oldest launch template version
   - Instance closest to next billing hour

2. **Target-group deregistration**:
   - Instance removed from target group
   - 300s deregistration delay — in-flight health-check state settles
   - (No ALB, so there is no external traffic to drain — if/when one is added on top of the TG, this same delay drains user traffic too)

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
| Health check type | ELB | Uses target group check, not basic EC2 status |
| Grace period | 300s | Ignore failures after launch |
| Health check path | `/health` | Target group probes here |
| Healthy threshold | 3 | Consecutive successes needed |
| Unhealthy threshold | 3 | Consecutive failures before unhealthy |
| Check interval | 30s | Time between checks |
| Matcher | 200 | Only HTTP 200 = healthy |

## Self-Healing

If a running instance fails (app crash, instance failure):

1. Target group detects 3 consecutive health-check failures
2. ASG (reading TG state via `health_check_type = "ELB"`) marks instance unhealthy
3. ASG terminates instance
4. ASG launches replacement (follows scale-out process)

No human involvement needed.
