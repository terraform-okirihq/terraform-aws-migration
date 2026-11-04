# ============================================
# LANDING NETWORK: VPC, SITE-TO-SITE VPN, HYBRID DNS
# ============================================
# For teams with no AWS network yet: network.create builds the VPC; vpn connects it to the data centre;
# dns makes on-prem names resolvable from AWS (and AWS names from on-prem). Each part also works with an
# existing VPC or the platform module.

locals {
  az_count      = var.network.az_count
  nat_count     = !local.create_vpc || var.network.nat == "none" ? 0 : (var.network.nat == "single" ? 1 : local.az_count)
  endpoints_on  = local.create_vpc && coalesce(var.network.interface_endpoints, local.s.interface_endpoints)
  vpn_on        = var.vpn != null
  vpn_tgw       = local.vpn_on && try(var.vpn.attach, "vgw") == "tgw"
  vpn_vgw       = local.vpn_on && !local.vpn_tgw
  tgw_create    = local.vpn_tgw && try(var.vpn.transit_gateway_id, null) == null
  dns_on        = var.dns != null && length(local.subnet_ids) >= 2
  resolver_subs = slice(local.subnet_ids, 0, min(length(local.subnet_ids), 2))

  interface_endpoint_services = ["dms", "mgn", "secretsmanager", "kms", "logs", "sts", "ssm", "ssmmessages", "ec2messages", "ec2", "ecr.api", "ecr.dkr"]
}

# --------------------------------------------
# VPC
# --------------------------------------------
data "aws_availability_zones" "available" {
  count = local.create_vpc ? 1 : 0
  state = "available"

  filter {
    name   = "opt-in-status"
    values = ["opt-in-not-required"]
  }
}

resource "aws_vpc" "this" {
  count                = local.create_vpc ? 1 : 0
  cidr_block           = var.network.cidr
  enable_dns_support   = true
  enable_dns_hostnames = true
  tags                 = merge(local.tags, { Name = "${local.prefix}-vpc", Lifecycle = "keep" })
}

# CIS: the default security group allows nothing.
resource "aws_default_security_group" "this" {
  count  = local.create_vpc ? 1 : 0
  vpc_id = aws_vpc.this[0].id
  tags   = merge(local.tags, { Name = "${local.prefix}-default-locked" })
}

resource "aws_internet_gateway" "this" {
  count  = local.create_vpc && var.network.nat != "none" ? 1 : 0
  vpc_id = aws_vpc.this[0].id
  tags   = merge(local.tags, { Name = "${local.prefix}-igw" })
}

resource "aws_subnet" "public" {
  count             = local.create_vpc && var.network.nat != "none" ? local.az_count : 0
  vpc_id            = aws_vpc.this[0].id
  cidr_block        = cidrsubnet(var.network.cidr, 4, count.index)
  availability_zone = data.aws_availability_zones.available[0].names[count.index]
  tags              = merge(local.tags, { Name = "${local.prefix}-public-${data.aws_availability_zones.available[0].names[count.index]}", Tier = "public" })
}

resource "aws_subnet" "private" {
  count             = local.create_vpc ? local.az_count : 0
  vpc_id            = aws_vpc.this[0].id
  cidr_block        = cidrsubnet(var.network.cidr, 4, count.index + 8)
  availability_zone = data.aws_availability_zones.available[0].names[count.index]
  tags              = merge(local.tags, { Name = "${local.prefix}-private-${data.aws_availability_zones.available[0].names[count.index]}", Tier = "private" })
}

resource "aws_eip" "nat" {
  count  = local.nat_count
  domain = "vpc"
  tags   = merge(local.tags, { Name = "${local.prefix}-nat-${count.index + 1}" })
}

resource "aws_nat_gateway" "this" {
  count         = local.nat_count
  allocation_id = aws_eip.nat[count.index].id
  subnet_id     = aws_subnet.public[count.index].id
  tags          = merge(local.tags, { Name = "${local.prefix}-nat-${count.index + 1}" })

  depends_on = [aws_internet_gateway.this]
}

resource "aws_route_table" "public" {
  count  = length(aws_internet_gateway.this)
  vpc_id = aws_vpc.this[0].id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.this[0].id
  }

  tags = merge(local.tags, { Name = "${local.prefix}-public-rt" })
}

resource "aws_route_table_association" "public" {
  count          = length(aws_subnet.public)
  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public[0].id
}

resource "aws_route_table" "private" {
  count  = local.create_vpc ? local.az_count : 0
  vpc_id = aws_vpc.this[0].id
  tags   = merge(local.tags, { Name = "${local.prefix}-private-rt-${count.index + 1}" })
}

resource "aws_route" "private_nat" {
  count                  = local.nat_count > 0 ? local.az_count : 0
  route_table_id         = aws_route_table.private[count.index].id
  destination_cidr_block = "0.0.0.0/0"
  nat_gateway_id         = aws_nat_gateway.this[local.nat_count == 1 ? 0 : count.index].id
}

resource "aws_route_table_association" "private" {
  count          = length(aws_subnet.private)
  subnet_id      = aws_subnet.private[count.index].id
  route_table_id = aws_route_table.private[count.index].id
}

resource "aws_vpc_endpoint" "gateway" {
  for_each          = local.create_vpc ? toset(["s3", "dynamodb"]) : toset([])
  vpc_id            = aws_vpc.this[0].id
  service_name      = "com.amazonaws.${local.region}.${each.key}"
  vpc_endpoint_type = "Gateway"
  route_table_ids   = aws_route_table.private[*].id
  tags              = merge(local.tags, { Name = "${local.prefix}-${each.key}" })
}

resource "aws_security_group" "endpoints" {
  count       = local.endpoints_on ? 1 : 0
  name        = "${local.prefix}-endpoints"
  description = "HTTPS to AWS service endpoints from the VPC and on-prem"
  vpc_id      = aws_vpc.this[0].id
  tags        = merge(local.tags, { Name = "${local.prefix}-endpoints" })
}

resource "aws_vpc_security_group_ingress_rule" "endpoints" {
  for_each          = local.endpoints_on ? toset(concat([var.network.cidr], var.onprem_cidrs)) : toset([])
  security_group_id = aws_security_group.endpoints[0].id
  description       = "HTTPS from ${each.value}"
  ip_protocol       = "tcp"
  from_port         = 443
  to_port           = 443
  cidr_ipv4         = each.value
}

resource "aws_vpc_endpoint" "interface" {
  for_each            = local.endpoints_on ? toset(local.interface_endpoint_services) : toset([])
  vpc_id              = aws_vpc.this[0].id
  service_name        = "com.amazonaws.${local.region}.${each.key}"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = aws_subnet.private[*].id
  security_group_ids  = [aws_security_group.endpoints[0].id]
  private_dns_enabled = true
  tags                = merge(local.tags, { Name = "${local.prefix}-${each.key}" })
}

resource "aws_cloudwatch_log_group" "flow" {
  count             = local.create_vpc ? 1 : 0
  name              = "/${local.prefix}/vpc-flow-logs"
  retention_in_days = local.s.log_retention
  kms_key_id        = local.kms_key_arn
  tags              = local.tags
}

resource "aws_iam_role" "flow" {
  count = local.create_vpc ? 1 : 0
  name  = "${local.prefix}-flow-logs"

  assume_role_policy = jsonencode({
    Version   = "2012-10-17"
    Statement = [{ Effect = "Allow", Principal = { Service = "vpc-flow-logs.amazonaws.com" }, Action = "sts:AssumeRole" }]
  })

  tags = local.tags
}

resource "aws_iam_role_policy" "flow" {
  count = length(aws_iam_role.flow)
  name  = "write-flow-logs"
  role  = aws_iam_role.flow[0].id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["logs:CreateLogStream", "logs:PutLogEvents", "logs:DescribeLogGroups", "logs:DescribeLogStreams"]
      Resource = [aws_cloudwatch_log_group.flow[0].arn, "${aws_cloudwatch_log_group.flow[0].arn}:*"]
    }]
  })
}

resource "aws_flow_log" "this" {
  count           = local.create_vpc ? 1 : 0
  vpc_id          = aws_vpc.this[0].id
  traffic_type    = "ALL"
  iam_role_arn    = aws_iam_role.flow[0].arn
  log_destination = aws_cloudwatch_log_group.flow[0].arn
  tags            = merge(local.tags, { Name = "${local.prefix}-flow-logs" })
}

# --------------------------------------------
# Site-to-Site VPN
# --------------------------------------------
resource "aws_customer_gateway" "onprem" {
  count      = local.vpn_on ? 1 : 0
  bgp_asn    = var.vpn.bgp_asn
  ip_address = var.vpn.customer_gateway_ip
  type       = "ipsec.1"
  tags       = merge(local.tags, { Name = "${local.prefix}-onprem" })
}

resource "aws_vpn_gateway" "this" {
  count           = local.vpn_vgw ? 1 : 0
  vpc_id          = local.vpc_id
  amazon_side_asn = var.vpn.amazon_side_asn
  tags            = merge(local.tags, { Name = "${local.prefix}-vgw" })
}

resource "aws_vpn_gateway_route_propagation" "private" {
  count          = local.vpn_vgw ? length(local.route_table_ids) : 0
  vpn_gateway_id = aws_vpn_gateway.this[0].id
  route_table_id = local.route_table_ids[count.index]
}

resource "aws_ec2_transit_gateway" "this" {
  count                           = local.tgw_create ? 1 : 0
  description                     = "${local.prefix} hub for on-prem connectivity"
  amazon_side_asn                 = var.vpn.amazon_side_asn
  default_route_table_association = "enable"
  default_route_table_propagation = "enable"
  dns_support                     = "enable"
  vpn_ecmp_support                = "enable"
  tags                            = merge(local.tags, { Name = "${local.prefix}-tgw" })
}

data "aws_ec2_transit_gateway" "existing" {
  count = local.vpn_tgw && !local.tgw_create ? 1 : 0
  id    = var.vpn.transit_gateway_id
}

locals {
  tgw_id       = local.tgw_create ? try(aws_ec2_transit_gateway.this[0].id, null) : try(var.vpn.transit_gateway_id, null)
  tgw_route_tb = local.tgw_create ? try(aws_ec2_transit_gateway.this[0].association_default_route_table_id, null) : try(data.aws_ec2_transit_gateway.existing[0].association_default_route_table_id, null)
}

resource "aws_ec2_transit_gateway_vpc_attachment" "this" {
  count              = local.vpn_tgw ? 1 : 0
  transit_gateway_id = local.tgw_id
  vpc_id             = local.vpc_id
  subnet_ids         = local.subnet_ids
  dns_support        = "enable"
  tags               = merge(local.tags, { Name = "${local.prefix}-vpc" })
}

resource "aws_route" "to_onprem_via_tgw" {
  for_each               = local.vpn_tgw ? { for pair in setproduct(range(length(local.route_table_ids)), var.onprem_cidrs) : "${pair[0]}|${pair[1]}" => pair } : {}
  route_table_id         = local.route_table_ids[each.value[0]]
  destination_cidr_block = each.value[1]
  transit_gateway_id     = local.tgw_id

  depends_on = [aws_ec2_transit_gateway_vpc_attachment.this]
}

resource "aws_cloudwatch_log_group" "vpn" {
  count             = local.vpn_on ? 1 : 0
  name              = "/aws/vpn/${local.prefix}"
  retention_in_days = local.s.log_retention
  kms_key_id        = local.kms_key_arn
  tags              = local.tags
}

resource "aws_vpn_connection" "onprem" {
  count               = local.vpn_on ? 1 : 0
  customer_gateway_id = aws_customer_gateway.onprem[0].id
  type                = "ipsec.1"
  vpn_gateway_id      = local.vpn_vgw ? aws_vpn_gateway.this[0].id : null
  transit_gateway_id  = local.vpn_tgw ? local.tgw_id : null
  static_routes_only  = var.vpn.routing == "static"

  # Strong ciphers only, on both tunnels.
  tunnel1_ike_versions                 = ["ikev2"]
  tunnel1_phase1_encryption_algorithms = ["AES256", "AES256-GCM-16"]
  tunnel1_phase2_encryption_algorithms = ["AES256", "AES256-GCM-16"]
  tunnel1_phase1_integrity_algorithms  = ["SHA2-256", "SHA2-384", "SHA2-512"]
  tunnel1_phase2_integrity_algorithms  = ["SHA2-256", "SHA2-384", "SHA2-512"]
  tunnel1_phase1_dh_group_numbers      = [14, 15, 16, 17, 18, 19, 20, 21]
  tunnel1_phase2_dh_group_numbers      = [14, 15, 16, 17, 18, 19, 20, 21]
  tunnel2_ike_versions                 = ["ikev2"]
  tunnel2_phase1_encryption_algorithms = ["AES256", "AES256-GCM-16"]
  tunnel2_phase2_encryption_algorithms = ["AES256", "AES256-GCM-16"]
  tunnel2_phase1_integrity_algorithms  = ["SHA2-256", "SHA2-384", "SHA2-512"]
  tunnel2_phase2_integrity_algorithms  = ["SHA2-256", "SHA2-384", "SHA2-512"]
  tunnel2_phase1_dh_group_numbers      = [14, 15, 16, 17, 18, 19, 20, 21]
  tunnel2_phase2_dh_group_numbers      = [14, 15, 16, 17, 18, 19, 20, 21]

  tunnel1_log_options {
    cloudwatch_log_options {
      log_enabled       = true
      log_group_arn     = aws_cloudwatch_log_group.vpn[0].arn
      log_output_format = "json"
    }
  }

  tunnel2_log_options {
    cloudwatch_log_options {
      log_enabled       = true
      log_group_arn     = aws_cloudwatch_log_group.vpn[0].arn
      log_output_format = "json"
    }
  }

  tags = merge(local.tags, { Name = "${local.prefix}-onprem" })

  depends_on = [aws_ec2_transit_gateway_vpc_attachment.this]
}

# Static routing: VGW routes per on-prem CIDR, or TGW routes to the VPN attachment.
resource "aws_vpn_connection_route" "onprem" {
  for_each               = local.vpn_vgw && try(var.vpn.routing, "") == "static" ? toset(var.onprem_cidrs) : toset([])
  vpn_connection_id      = aws_vpn_connection.onprem[0].id
  destination_cidr_block = each.value
}

resource "aws_ec2_transit_gateway_route" "onprem" {
  for_each                       = local.vpn_tgw && try(var.vpn.routing, "") == "static" ? toset(var.onprem_cidrs) : toset([])
  destination_cidr_block         = each.value
  transit_gateway_attachment_id  = aws_vpn_connection.onprem[0].transit_gateway_attachment_id
  transit_gateway_route_table_id = local.tgw_route_tb
}

# Both tunnels down = no path to the data centre.
resource "aws_cloudwatch_metric_alarm" "vpn_down" {
  count               = local.vpn_on ? 1 : 0
  alarm_name          = "${local.prefix}-vpn-down"
  alarm_description   = "Both VPN tunnels to the data centre are down: replication and transfers are stalled."
  namespace           = "AWS/VPN"
  metric_name         = "TunnelState"
  dimensions          = { VpnId = aws_vpn_connection.onprem[0].id }
  statistic           = "Maximum"
  period              = 300
  evaluation_periods  = 2
  threshold           = 1
  comparison_operator = "LessThanThreshold"
  treat_missing_data  = "breaching"
  alarm_actions       = [aws_sns_topic.alerts.arn]
  ok_actions          = [aws_sns_topic.alerts.arn]
  tags                = local.tags
}

# --------------------------------------------
# Hybrid DNS (Route 53 Resolver)
# --------------------------------------------
resource "aws_security_group" "resolver" {
  count       = local.dns_on ? 1 : 0
  name        = "${local.prefix}-resolver"
  description = "Route 53 Resolver endpoints: DNS between the VPC and on-prem"
  vpc_id      = local.vpc_id
  tags        = merge(local.tags, { Name = "${local.prefix}-resolver" })
}

resource "aws_vpc_security_group_ingress_rule" "resolver" {
  for_each          = local.dns_on ? { for pair in setproduct(concat([local.vpc_cidr], var.onprem_cidrs), ["tcp", "udp"]) : "${pair[0]}|${pair[1]}" => pair } : {}
  security_group_id = aws_security_group.resolver[0].id
  description       = "DNS from ${each.value[0]}"
  ip_protocol       = each.value[1]
  from_port         = 53
  to_port           = 53
  cidr_ipv4         = each.value[0]
}

resource "aws_vpc_security_group_egress_rule" "resolver" {
  for_each          = local.dns_on ? { for pair in setproduct(var.dns.onprem_dns_servers, ["tcp", "udp"]) : "${pair[0]}|${pair[1]}" => pair } : {}
  security_group_id = aws_security_group.resolver[0].id
  description       = "DNS to on-prem server ${each.value[0]}"
  ip_protocol       = each.value[1]
  from_port         = 53
  to_port           = 53
  cidr_ipv4         = "${each.value[0]}/32"
}

resource "aws_route53_resolver_endpoint" "outbound" {
  count              = local.dns_on ? 1 : 0
  name               = "${local.prefix}-outbound"
  direction          = "OUTBOUND"
  security_group_ids = [aws_security_group.resolver[0].id]

  dynamic "ip_address" {
    for_each = local.resolver_subs
    content {
      subnet_id = ip_address.value
    }
  }

  tags = local.tags
}

resource "aws_route53_resolver_rule" "forward" {
  for_each             = local.dns_on ? toset(var.dns.forward_domains) : toset([])
  name                 = "${local.prefix}-${replace(each.value, ".", "-")}"
  domain_name          = each.value
  rule_type            = "FORWARD"
  resolver_endpoint_id = aws_route53_resolver_endpoint.outbound[0].id

  dynamic "target_ip" {
    for_each = var.dns.onprem_dns_servers
    content {
      ip   = target_ip.value
      port = 53
    }
  }

  tags = local.tags
}

resource "aws_route53_resolver_rule_association" "forward" {
  for_each         = aws_route53_resolver_rule.forward
  resolver_rule_id = each.value.id
  vpc_id           = local.vpc_id
}

resource "aws_route53_resolver_endpoint" "inbound" {
  count              = local.dns_on && try(var.dns.inbound, true) ? 1 : 0
  name               = "${local.prefix}-inbound"
  direction          = "INBOUND"
  security_group_ids = [aws_security_group.resolver[0].id]

  dynamic "ip_address" {
    for_each = local.resolver_subs
    content {
      subnet_id = ip_address.value
    }
  }

  tags = local.tags
}

locals {
  network_summary = {
    vpc       = local.vpc_id
    cidr      = local.vpc_cidr
    created   = local.create_vpc
    nat_ips   = aws_eip.nat[*].public_ip
    endpoints = local.endpoints_on ? local.interface_endpoint_services : []
    vpn = local.vpn_on ? {
      connection_id = aws_vpn_connection.onprem[0].id
      tunnel_ips    = [aws_vpn_connection.onprem[0].tunnel1_address, aws_vpn_connection.onprem[0].tunnel2_address]
      routing       = var.vpn.routing
      attached_to   = local.vpn_tgw ? "transit gateway ${local.tgw_id}" : "virtual private gateway ${aws_vpn_gateway.this[0].id}"
      router_config = "aws ec2 get-vpn-connection-device-types --region ${local.region}   # find your router's type id, then:\naws ec2 get-vpn-connection-device-sample-configuration --region ${local.region} --vpn-connection-id ${aws_vpn_connection.onprem[0].id} --vpn-connection-device-type-id <type-id> --internet-key-exchange-version ikev2 --output text > router-config.txt"
    } : null
    dns = local.dns_on ? {
      forwards_to_onprem = { for d in var.dns.forward_domains : d => var.dns.onprem_dns_servers }
      inbound_ips        = try([for ip in aws_route53_resolver_endpoint.inbound[0].ip_address : ip.ip], [])
      onprem_setup       = "On your DNS servers, add conditional forwarders for amazonaws.com / your private hosted zones to the inbound IPs."
    } : null
  }
}
