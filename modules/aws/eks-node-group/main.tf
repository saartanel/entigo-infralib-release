#https://registry.terraform.io/modules/terraform-aws-modules/eks/aws/latest
module "eks-managed-node-group" {
  source  = "terraform-aws-modules/eks/aws//modules/eks-managed-node-group"
  version = "20.36.0"
  use_name_prefix = true
  name                    = substr(var.prefix, 0, 35)
  iam_role_use_name_prefix = true
  iam_role_name           = substr(var.prefix, 0, 35)

#  create_launch_template   = var.launch_template_id != "" ? false : true
#  launch_template_id = var.launch_template_id

  key_name = var.key_name

  launch_template_name    = substr(var.prefix, 0, 35)

  cluster_name            = var.cluster_name
  cluster_version         = var.cluster_version
  subnet_ids              = var.subnets
  cluster_primary_security_group_id = var.cluster_primary_security_group_id
  cluster_service_cidr    = var.cluster_service_cidr
  vpc_security_group_ids = var.security_group_ids
  
  pre_bootstrap_user_data = var.pre_bootstrap_user_data
  use_custom_launch_template = length(var.remote_access) != 0 ? false : true
  remote_access = var.remote_access
  
  min_size     = var.min_size
  max_size     = var.max_size
  desired_size = var.desired_size

  instance_types = var.instance_types
  capacity_type  = var.capacity_type
  ami_type       = var.ami_type
  
  block_device_mappings = var.block_device_mappings != null ? var.block_device_mappings : {
    xvda = {
      device_name = "/dev/xvda"
      ebs = {
        volume_size           = var.volume_size
        volume_iops           = var.volume_iops
        volume_type           = var.volume_type
        encrypted             = var.encryption_kms_key_arn != "" ? true : false
        kms_key_id            = var.encryption_kms_key_arn != "" ? var.encryption_kms_key_arn : null
        delete_on_termination = true
      }
    }
  }
  
  labels = var.labels
  taints = var.taints
  launch_template_tags = {
    Terraform = "true"
    Prefix    = var.prefix
    created-by = "entigo-infralib"
  }
  tags = {
    Terraform = "true"
    Prefix    = var.prefix
    created-by = "entigo-infralib"
  }
}

#resource "aws_launch_template" "this" {
#  block_device_mappings = {
#    xvda = {
#      device_name = "/dev/xvda"
#      ebs = {
#        volume_size           = var.volume_size
#        volume_iops           = var.volume_iops
#        volume_type           = var.volume_type
#        encrypted             = var.encryption_kms_key_arn != "" ? true : false
#        kms_key_id            = var.encryption_kms_key_arn != "" ? var.encryption_kms_key_arn : null
#        delete_on_termination = true
#      }
#    }
#  }
#
#  name_prefix            = substr(var.prefix, 0, 35)
#  update_default_version = true
#  image_id = data.aws_ami.amazon-eks-node-ami.id
#  key_name = aws_key_pair.generated.key_name
#  metadata_options {
#    http_put_response_hop_limit = 2
#    http_endpoint = "enabled"
#  }
#
#  tag_specifications {
#    resource_type = "instance"
#    tags = {
#      Name = "${terraform.workspace}-eks-core-A"
#      map-migrated = "d-server-0149ovpcupxrqu"
#    }
#  }
#
#  vpc_security_group_ids = [aws_security_group.node.id, aws_security_group.allow_ssh_private.id,aws_security_group.efs.id]
#  user_data              = base64encode(local.ng-core)
#}
