# Instance Naming

Each EC2 instance launched by ASG self-tags with `Name`:

```
<asg-name>-<last-4-digits-of-instance-id>
```

**Example**: ASG `myproject-production-myapp-asg`, instance `i-0abc1234def56789`:

```
Name = myproject-production-myapp-asg-6789
```

## How It Works

User data script runs at boot. Steps:

1. **Get instance ID** via IMDSv2:
   ```bash
   TOKEN=$(curl -s -X PUT "http://169.254.169.254/latest/api/token" \
     -H "X-aws-ec2-metadata-token-ttl-seconds: 21600")

   INSTANCE_ID=$(curl -s -H "X-aws-ec2-metadata-token: $TOKEN" \
     http://169.254.169.254/latest/meta-data/instance-id)
   ```

2. **Extract last 4 chars**:
   ```bash
   SHORT_ID="${INSTANCE_ID: -4}"
   ```

3. **Tag instance**:
   ```bash
   aws ec2 create-tags \
     --region "$REGION" \
     --resources "$INSTANCE_ID" \
     --tags "Key=Name,Value=${ASG_NAME}-${SHORT_ID}"
   ```

## Required IAM Permissions

Defined in `terraform/modules/app/iam.tf`:

```json
{
  "Effect": "Allow",
  "Action": [
    "ec2:CreateTags",
    "ec2:DescribeTags"
  ],
  "Resource": "*"
}
```

## Viewing Names

AWS Console shows names after launch. Or via CLI:

```bash
aws ec2 describe-instances \
  --filters "Name=tag:aws:autoscaling:groupName,Values=myproject-production-myapp-asg" \
  --query 'Reservations[].Instances[].[InstanceId, Tags[?Key==`Name`].Value | [0], State.Name]' \
  --output table
```

## Collision Probability

Last 4 hex chars = 65,536 possible values. Negligible for typical ASG sizes:

| Instances | Collision Probability |
|-----------|-----------------------|
| 2         | 0.0015%               |
| 5         | 0.015%                |
| 10        | 0.069%                |

Collision is cosmetic only — instance ID stays unique.

## Customization

Modify `terraform/modules/app/templates/user-data.sh.tftpl`:

- **6 chars instead of 4**: `${INSTANCE_ID: -6}`
- **Custom prefix**: add identifier to format string
- **Different separator**: replace `-` between ASG name and short ID
