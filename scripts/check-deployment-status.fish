#!/usr/bin/env fish

echo "🔍 K8spocalypse Deployment Status Check"
echo "======================================"
echo ""

# Function to check command success
function check_status
    if test $status -eq 0
        echo "✅ $argv[1]"
    else
        echo "❌ $argv[1]"
    end
end

# 1. Infrastructure Status
echo "1️⃣ INFRASTRUCTURE STATUS"
echo "------------------------"

# Check EKS clusters
echo -n "Milan EKS Cluster: "
kubectl config use-context arn:aws:eks:eu-south-1:801971731812:cluster/k8s-dr-milan >/dev/null 2>&1
check_status "Connected"

echo -n "Dublin EKS Cluster: "
kubectl config use-context arn:aws:eks:eu-west-1:801971731812:cluster/k8s-dr-dublin >/dev/null 2>&1
check_status "Connected"

# Check VPC Peering
echo -n "VPC Peering: "
set peering_status (aws ec2 describe-vpc-peering-connections --query 'VpcPeeringConnections[?Status.Code==`active`]' --output json 2>/dev/null | jq length)
if test "$peering_status" = "1"
    check_status "Active"
else
    echo "❌ Not Active (found $peering_status)"
end

# Check Private Hosted Zone
echo -n "Private Hosted Zone: "
set phz_count (aws route53 list-hosted-zones --query 'HostedZones[?Config.PrivateZone==`true` && Name==`internal.k8sdr.com.`]' --output json 2>/dev/null | jq length)
if test "$phz_count" = "1"
    check_status "Exists"
else
    echo "❌ Not Found"
end

echo ""

# 2. Application Status
echo "2️⃣ APPLICATION STATUS"
echo "--------------------"

# Milan applications
kubectl config use-context arn:aws:eks:eu-south-1:801971731812:cluster/k8s-dr-milan >/dev/null 2>&1
echo "Milan (eu-south-1):"
kubectl get pods -n dev --no-headers | awk '{print "  - " $1 ": " $3}'
echo ""

# Dublin applications
kubectl config use-context arn:aws:eks:eu-west-1:801971731812:cluster/k8s-dr-dublin >/dev/null 2>&1
echo "Dublin (eu-west-1):"
kubectl get pods -n dev --no-headers | awk '{print "  - " $1 ": " $3}'
echo ""

# 3. Load Balancer Status
echo "3️⃣ LOAD BALANCER STATUS"
echo "----------------------"

# Milan ALB
kubectl config use-context arn:aws:eks:eu-south-1:801971731812:cluster/k8s-dr-milan >/dev/null 2>&1
set milan_alb (kubectl get ingress -n dev dadjokes-ingress -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null)
if test -n "$milan_alb"
    echo "✅ Milan ALB: $milan_alb"
    set milan_health (curl -s -o /dev/null -w "%{http_code}" http://$milan_alb/readyz 2>/dev/null)
    echo "   Health Check: $milan_health"
else
    echo "❌ Milan ALB: Not Found"
end

# Dublin ALB
kubectl config use-context arn:aws:eks:eu-west-1:801971731812:cluster/k8s-dr-dublin >/dev/null 2>&1
set dublin_alb (kubectl get ingress -n dev dadjokes-ingress -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null)
if test -n "$dublin_alb"
    echo "✅ Dublin ALB: $dublin_alb"
    set dublin_health (curl -s -o /dev/null -w "%{http_code}" http://$dublin_alb/readyz 2>/dev/null)
    echo "   Health Check: $dublin_health"
else
    echo "❌ Dublin ALB: Not Found"
end

echo ""

# 4. MongoDB Status
echo "4️⃣ MONGODB STATUS"
echo "-----------------"

# Check MongoDB configuration
kubectl config use-context arn:aws:eks:eu-south-1:801971731812:cluster/k8s-dr-milan >/dev/null 2>&1
echo -n "MongoDB Multi-Region: "
set mongo_members (kubectl get mongodbcommunity mongodb -n dev -o jsonpath='{.spec.members}' 2>/dev/null)
if test "$mongo_members" = "1"
    echo "❌ Single Region (members: $mongo_members)"
else
    echo "✅ Multi-Region (members: $mongo_members)"
end

# Check for MongoDB NLB services
echo -n "MongoDB NLB Services: "
set nlb_count (kubectl get svc -n dev -o json 2>/dev/null | jq '.items[] | select(.metadata.annotations."service.beta.kubernetes.io/aws-load-balancer-type" == "nlb") | .metadata.name' | wc -l)
if test $nlb_count -gt 0
    check_status "Found $nlb_count NLB services"
else
    echo "❌ No NLB services found"
end

echo ""

# 5. Global Accelerator Status
echo "5️⃣ GLOBAL ACCELERATOR STATUS"
echo "---------------------------"
set ga_count (aws globalaccelerator list-accelerators --region us-west-2 --query 'length(Accelerators)' --output text 2>/dev/null)
if test -n "$ga_count" -a "$ga_count" != "0"
    set ga_dns (aws globalaccelerator list-accelerators --region us-west-2 --query 'Accelerators[0].DnsName' --output text 2>/dev/null)
    echo "✅ Global Accelerator: $ga_dns"
    set ga_ips (aws globalaccelerator list-accelerators --region us-west-2 --query 'Accelerators[0].IpSets[0].IpAddresses' --output text 2>/dev/null)
    echo "   Static IPs: $ga_ips"
else
    echo "❌ Global Accelerator: Not Deployed"
end

echo ""

# 6. CoreDNS Configuration
echo "6️⃣ COREDNS CONFIGURATION"
echo "------------------------"

# Milan CoreDNS
kubectl config use-context arn:aws:eks:eu-south-1:801971731812:cluster/k8s-dr-milan >/dev/null 2>&1
echo -n "Milan CoreDNS Custom Config: "
kubectl get cm coredns-custom -n kube-system >/dev/null 2>&1
check_status "Applied"

# Dublin CoreDNS
kubectl config use-context arn:aws:eks:eu-west-1:801971731812:cluster/k8s-dr-dublin >/dev/null 2>&1
echo -n "Dublin CoreDNS Custom Config: "
kubectl get cm coredns-custom -n kube-system >/dev/null 2>&1
check_status "Applied"

echo ""

# 7. Backup Status
echo "7️⃣ BACKUP STATUS"
echo "----------------"
set backup_count (velero backup get --output json 2>/dev/null | jq '.items | length')
if test -n "$backup_count" -a $backup_count -gt 0
    echo "✅ Velero Backups: $backup_count found"
    velero backup get 2>/dev/null | head -5
else
    echo "❌ Velero Backups: None found"
end

echo ""
echo "======================================"
echo "📋 DEPLOYMENT CHECKLIST"
echo "======================================"
echo ""
echo "✅ Completed:"
echo "  - EKS clusters deployed in both regions"
echo "  - VPC peering established"
echo "  - Applications deployed (joke-server, MongoDB, Redis, NATS)"
echo "  - ALB created for joke-server in both regions"
echo "  - CoreDNS custom configuration applied"
echo "  - Velero backup system configured"
echo ""
echo "❌ TODO:"
echo "  1. Deploy Global Accelerator: ./scripts/deploy-global-accelerator.fish"
echo "  2. Configure MongoDB for multi-region replication"
echo "  3. Create MongoDB NLB services for cross-region access"
echo "  4. Add DNS records to private hosted zone"
echo ""
echo "🚀 Next Steps:"
echo "  1. Run: ./scripts/deploy-global-accelerator.fish"
echo "  2. Configure MongoDB multi-region setup"
echo "  3. Test failover scenarios" 