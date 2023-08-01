data "aws_ami" "app_ami" {
  most_recent = true

  filter {
    name   = "name"
    values = ["bitnami-tomcat-*-x86_64-hvm-ebs-nami"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }

  owners = ["979382823631"] # Bitnami
}

# Replace default vpc with a module copied from Terraform Registry
# data "aws_vpc" "default" {
#   default = true
# }
module "blog_vpc" {
  source = "terraform-aws-modules/vpc/aws"

  name = "dev"
  cidr = "10.0.0.0/16"

  azs             = ["us-west-2a","us-west-2b","us-west-2c"]
  public_subnets  = ["10.0.101.0/24", "10.0.102.0/24", "10.0.103.0/24"]
  private_subnets = ["10.0.1.0/24", "10.0.2.0/24", "10.0.3.0/24"]

  enable_nat_gateway = true

  tags = {
    Terraform = "true"
    Environment = "dev"
  }
}

# Replace instance resource with autoscaling module
# resource "aws_instance" "blog" {
#   ami                    = data.aws_ami.app_ami.id
#   instance_type          = var.instance_type
#   subnet_id              = module.blog_vpc.public_subnets[0]
#   vpc_security_group_ids = [module.blog_sg.security_group_id]

#   tags = {
#     Name = "Learning Terraform"
#   }
# }

# Module copied from TF Registry
# https://registry.terraform.io/modules/terraform-aws-modules/autoscaling/aws/latest
module "autoscaling" {
  source  = "terraform-aws-modules/autoscaling/aws"
  version = "6.10.0"

  name        = "blog"
  min_size    = 1
  max_size    = 2

  vpc_zone_identifier = module.blog_vpc.public_subnets
  target_group_arns   = module.blog_alb.target_group_arns
  security_groups     = [module.blog_sg.security_group_id]

  image_id      = data.aws_ami.app_ami.id
  instance_type = var.instance_type
}

# Module copied from TF Registry
# https://registry.terraform.io/modules/terraform-aws-modules/alb/aws/latest
module "blog_alb" {
  source  = "terraform-aws-modules/alb/aws"
  version = "~> 8.0"

  name = "blog-alb"

  load_balancer_type = "application"

  vpc_id             = module.blog_vpc.vpc_id
  subnets            = module.blog_vpc.public_subnets
  security_groups    = [module.blog_sg.security_group_id]

  # access_logs = {
  #   bucket = "my-alb-logs"
  # }

  target_groups = [
    {
      name_prefix      = "blog-"
      backend_protocol = "HTTP"
      backend_port     = 80
      target_type      = "instance"
      # Remove targets since specified in autoscaling module
      # targets = {
      #   my_target = {
      #     target_id = aws_instance.blog.id
      #     port = 80
      #   }
      # }
    }
  ]

  # https_listeners = [
  #   {
  #     port               = 443
  #     protocol           = "HTTPS"
  #     certificate_arn    = "arn:aws:iam::123456789012:server-certificate/test_cert-123456789012"
  #     target_group_index = 0
  #   }
  # ]

  http_tcp_listeners = [
    {
      port               = 80
      protocol           = "HTTP"
      target_group_index = 0
    }
  ]

  tags = {
    Environment = "dev"
  }
}

module "blog_sg" {
  source  = "terraform-aws-modules/security-group/aws"
  version = "4.13.0"

  vpc_id  = module.blog_vpc.vpc_id
  name    = "blog"
  ingress_rules = ["https-443-tcp","http-80-tcp"]
  ingress_cidr_blocks = ["0.0.0.0/0"]
  egress_rules = ["all-all"]
  egress_cidr_blocks = ["0.0.0.0/0"]
}

# resource "aws_security_group" "blog" {
#   name        = "blog"
#   description = "Allow http and https in; allow everything out."

#   vpc_id = data.aws_vpc.default.id
# }

# After switch to module and predefined rules, these no longer necessary
# resource "aws_security_group_rule" "blog_http_in" {
#   type          = "ingress"
#   from_port     = 80
#   to_port       = 80
#   protocol      = "tcp"
#   cidr_blocks   = ["0.0.0.0/0"]

#   security_group_id = aws_security_group.blog.id
# }

# resource "aws_security_group_rule" "blog_https_in" {
#   type          = "ingress"
#   from_port     = 443
#   to_port       = 443
#   protocol      = "tcp"
#   cidr_blocks   = ["0.0.0.0/0"]

#   security_group_id = aws_security_group.blog.id
# }

# resource "aws_security_group_rule" "blog_everything_out" {
#   type          = "egress"
#   from_port     = 0
#   to_port       = 0
#   protocol      = "-1"
#   cidr_blocks   = ["0.0.0.0/0"]

#   security_group_id = aws_security_group.blog.id
# }

