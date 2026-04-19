# Automatic Instance Naming

## Overview

Each EC2 instance launched by the Auto Scaling Group automatically tags itself with a human-readable `Name` tag following the format:

```
<asg-name>-<last-4-digits-of-instance-id>
```

**Example**: For ASG `myproject-production-myapp-asg` and instance `i-0abc1234def56789`:

```
Name = myproject-production-myapp-asg-6789
```

## How It Works

The instance naming is handled by the **user data script** that runs at boot time on every new instance.

### Step-by-step process:

1. **Retrieve instance metadata** using IMDSv2 (Instance Metadata Service v2):
   ```bash
   # Get a session token (IMDSv2 requires token-based access)
   TOKEN=$(curl -s -X PUT "http://169.254.169.254/latest/api/token" \
     -H "X-aws-ec2-metadata-token-ttl-seconds: 21600")

   # Get the instance ID
   INSTANCE_ID=$(curl -s -H "X-aws-ec2-metadata-token: $TOKEN" \
     http://169.254.169.254/latest/meta-data/instance-id)
   ```

2. **Extract the last 4 characters** of the instance ID:
   ```bash
   SHORT_ID="${INSTANCE_ID: -4}"
   ```

3. **Tag the instance** using AWS CLI:
   ```bash
   aws ec2 create-tags \
     --region "$REGION" \
     --resources "$INSTANCE_ID" \
     --tags "Key=Name,Value=${ASG_NAME}-${SHORT_ID}"
   ```

## Required IAM Permissions

The EC2 instance profile includes the following permissions to allow self-tagging:

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

These permissions are defined in `terraform/modules/app/iam.tf`.

## Viewing Instance Names

After launch, instances are visible in the AWS Console with their assigned names:

```
myproject-production-myapp-asg-6789
myproject-production-myapp-asg-a3b2
myproject-production-myapp-asg-f1e0
```

Or via AWS CLI:

```bash
aws ec2 describe-instances \
  --filters "Name=tag:aws:autoscaling:groupName,Values=myproject-production-myapp-asg" \
  --query 'Reservations[].Instances[].[InstanceId, Tags[?Key==`Name`].Value | [0], State.Name]' \
  --output table
```

## Collision Probability

Instance IDs are hexadecimal strings (e.g., `i-0abc1234def56789`). Using only the last 4 hex characters means 65,536 possible values. For typical ASG sizes (2-10 instances), the probability of a name collision is negligible:

| Instances | Collision Probability |
|-----------|-----------------------|
| 2         | 0.0015%               |
| 5         | 0.015%                |
| 10        | 0.069%                |

If a collision occurs, it is purely cosmetic and does not affect instance functionality -- the instance ID remains unique.

## Customization

To change the naming format, modify the user data template at `terraform/modules/app/templates/user-data.sh.tftpl`. For example:

- **Use 6 characters instead of 4**: Change `${INSTANCE_ID: -4}` to `${INSTANCE_ID: -6}`
- **Add a custom prefix**: Change the format string to include additional identifiers
- **Use a different separator**: Replace the `-` between ASG name and short ID
