terraform {
  required_providers {
    aws = {
      source = "hashicorp/aws"
      version = "4.11.0"
    }
    github = {
      source = "integrations/github"
      version = "4.23.0"
    }
  }
}

provider "aws" {
  # Configuration options
  region = "us-east-1"
  profile = "ben"
}

provider "github" {
  # Configuration options
  token = "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"
}

resource "github_repository" "my_repo" {
  name = "repo-bookstore"
  auto_init = true     # makes the first commit
  visibility = "private"
}

resource "github_branch_default" "my_def_branch" {
  branch     = "main"
  repository = github_repository.my_repo.name
}

variable "files" {
  default = ["bookstore-api.py", "docker-compose.yml", "Dockerfile", "requirements.txt"]
}

resource "github_repository_file" "my_github_content" {
  for_each = toset(var.files)
  content    = file(each.value)
  file       = each.value
  repository = github_repository.my_repo.name
  branch = "main"
  commit_message = "app-files added to repo"
  overwrite_on_create = true
}

data "aws_vpc" "default_vpc" {
  default = true
}

resource "aws_security_group" "sec_gr" {
  name        = "sec_gr_ssh"
  description = "Allow ssh"
  vpc_id      = data.aws_vpc.default_vpc.id

  ingress {
    description = "ssh"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "http"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port        = 0
    to_port          = 0
    protocol         = "-1"
    cidr_blocks      = ["0.0.0.0/0"]
  }

  tags = {
    Name = "sec_gr_ssh"
  }
}

data "aws_ami" "latest_ami" {
  owners  = ["amazon"]
  most_recent = true
  filter {
    name   = "name"
    values = ["amzn2-ami-kernel*"]
  }
}

resource "aws_instance" "docker_ec2" {
  ami = data.aws_ami.latest_ami.id
  instance_type = "t2.micro"
  key_name = "keyone"
  security_groups = [aws_security_group.sec_gr.name]
  tags = {
    Name = "bookstore_api_server_docker"
  }
  depends_on = [github_repository.my_repo, github_repository_file.my_github_content]
  user_data = <<EOF
    #!/bin/bash
    yum update -y
    amazon-linux-extras install docker -y
    systemctl start docker
    systemctl enable docker
    usermod -a -G docker ec2-user
    curl -L "https://github.com/docker/compose/releases/download/1.26.2/docker-compose-$(uname -s)-$(uname -m)" \
      -o /usr/local/bin/docker-compose
    chmod +x /usr/local/bin/docker-compose
    mkdir -p /home/ec2-user/bookstore-api
    TOKEN="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"
    FOLDER="https://$TOKEN@raw.githubusercontent.com/benjamin-02/repo-bookstore/main/"
    curl -s --create-dirs -o "/home/ec2-user/bookstore-api/app.py" -L "$FOLDER"bookstore-api.py
    curl -s --create-dirs -o "/home/ec2-user/bookstore-api/requirements.txt" -L "$FOLDER"requirements.txt
    curl -s --create-dirs -o "/home/ec2-user/bookstore-api/Dockerfile" -L "$FOLDER"Dockerfile
    curl -s --create-dirs -o "/home/ec2-user/bookstore-api/docker-compose.yml" -L "$FOLDER"docker-compose.yml
    cd /home/ec2-user/bookstore-api
    docker build -t benscompany/bookstoreapi:latest .
    docker-compose up -d
    EOF
}

output "website" {
  value = "http://${aws_instance.docker_ec2.public_dns}"
}