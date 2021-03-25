provider "aws" {
  region  = "us-east-1"
  access_key = ""
  secret_key = ""
}

# VPC
resource "aws_vpc" "main" {
  cidr_block       = "11.0.0.0/16"
  
  tags = {
    Name = "Terraform"
  }
}

#IGW
resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name = "igw"
  }
}

#route-table
resource "aws_route_table" "route-table" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.igw.id
  }

  route {
    ipv6_cidr_block        = "::/0"
    gateway_id = aws_internet_gateway.igw.id
  }

  tags = {
    Name = "terraform route table"
  }
}

#subnet
resource "aws_subnet" "subnet1" {
  vpc_id     = aws_vpc.main.id
  cidr_block = "11.0.1.0/24"
  availability_zone = "us-east-1a"
  map_public_ip_on_launch = true 
  tags = {
    Name = "terraformsubnet"
  }
}

#associate route table to subnet
resource "aws_route_table_association" "a" {
  subnet_id      = aws_subnet.subnet1.id
  route_table_id = aws_route_table.route-table.id
}


#security group for indexer

resource "aws_security_group" "web" {
  name        = "web"
  description = "Allow TLS inbound traffic"
  vpc_id      = aws_vpc.main.id
 

  ingress {
    description = "HTTPS"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  
  ingress {
    description = "splunkd"
    from_port   = 8080
    to_port     = 8080
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "splunkd"
    from_port   = 8000
    to_port     = 8000
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
 
 ingress {
    description = "Peering"
    from_port   = 8089
    to_port     = 8089
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "forwarderingestion"
    from_port   = 9997
    to_port     = 9997
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }


  ingress {
    description = "SSH"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

   ingress {
    description = "HTTPS"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "allow_web"
  }
}

#Network interface for idx1
resource "aws_network_interface" "idx1-nic" {
  depends_on=[aws_subnet.subnet1,aws_security_group.web]
  subnet_id       = aws_subnet.subnet1.id
  private_ips     = ["11.0.1.50"]
  security_groups = [aws_security_group.web.id]
}

#Network interface for idx2
resource "aws_network_interface" "idx2-nic" {
  depends_on=[aws_subnet.subnet1,aws_security_group.web]
  subnet_id       = aws_subnet.subnet1.id
  private_ips     = ["11.0.1.51"]
  security_groups = [aws_security_group.web.id]
}

#Network interface for idx3
resource "aws_network_interface" "idx3-nic" {
  depends_on=[aws_subnet.subnet1,aws_security_group.web]
  subnet_id       = aws_subnet.subnet1.id
  private_ips     = ["11.0.1.52"]
  security_groups = [aws_security_group.web.id]
}

#Network interface for forwarder
resource "aws_network_interface" "forwarder-nic" {
  depends_on=[aws_subnet.subnet1,aws_security_group.web]
  subnet_id       = aws_subnet.subnet1.id
  private_ips     = ["11.0.1.53"]
  security_groups = [aws_security_group.web.id]
}

#Network interface for Cluster Master
resource "aws_network_interface" "cm-nic" {
  depends_on=[aws_subnet.subnet1,aws_security_group.web]
  subnet_id       = aws_subnet.subnet1.id
  private_ips     = ["11.0.1.54"]
  security_groups = [aws_security_group.web.id]
}

resource "aws_network_interface" "sh-nic" {
  depends_on=[aws_subnet.subnet1,aws_security_group.web]
  subnet_id       = aws_subnet.subnet1.id
  private_ips     = ["11.0.1.55"]
  security_groups = [aws_security_group.web.id]
}

resource "aws_instance" "sh" {

    ami =  "ami-0885b1f6bd170450c"
    instance_type ="t2.micro"
    availability_zone="us-east-1a"
    key_name = "Crest"
    depends_on = [aws_instance.cm]
    network_interface{
      device_index=0
      network_interface_id= aws_network_interface.sh-nic.id
    }
    user_data = <<-EOF
              #!/bin/bash
              sudo apt-get update
              sudo su
              wget -O splunk-8.1.1-08187535c166-Linux-x86_64.tgz 'https://www.splunk.com/bin/splunk/DownloadActivityServlet?architecture=x86_64&platform=linux&version=8.1.1&product=splunk&filename=splunk-8.1.1-08187535c166-Linux-x86_64.tgz&wget=true'
              tar -xvzf splunk-8.1.1-08187535c166-Linux-x86_64.tgz
              cd /splunk/etc/system/local/
              echo -e "\n[diskUsage]\nminFreeSpace = 500" >> server.conf
              cd /splunk/bin
              ./splunk start --accept-license --answer-yes --no-prompt --seed-passwd admin123
              ./splunk edit cluster-config -mode searchhead -master_uri https://${aws_instance.cm.public_ip}:8089  -auth admin:admin123 
              ./splunk restart 
              EOF   
}

output "sh_ip_addr" {
  value = aws_instance.sh.public_ip
}


resource "aws_instance" "cm" {

    ami =  "ami-0885b1f6bd170450c"
    instance_type ="t2.micro"
    availability_zone="us-east-1a"
    key_name = "Crest"

    network_interface{
      device_index=0
      network_interface_id= aws_network_interface.cm-nic.id
    }
    user_data = <<-EOF
              #!/bin/bash
              sudo apt-get update
              sudo su
              wget -O splunk-8.1.1-08187535c166-Linux-x86_64.tgz 'https://www.splunk.com/bin/splunk/DownloadActivityServlet?architecture=x86_64&platform=linux&version=8.1.1&product=splunk&filename=splunk-8.1.1-08187535c166-Linux-x86_64.tgz&wget=true'
              tar -xvzf splunk-8.1.1-08187535c166-Linux-x86_64.tgz
              cd /splunk/bin
              ./splunk start --accept-license --answer-yes --no-prompt --seed-passwd admin123
              cd /splunk/etc/system/local/
              echo -e "\n[diskUsage] \nminFreeSpace = 500" >> server.conf
              cd /splunk/bin/
              ./splunk edit cluster-config -mode manager -replication_factor 3 -search_factor 2  -cluster_label cluster_master  -auth admin:admin123
              ./splunk restart
              EOF
    
}

output "cm_ip_addr" {
  value = aws_instance.cm.public_ip
}

resource "aws_instance" "idx1" {

    ami =  "ami-0885b1f6bd170450c"
    instance_type ="t2.micro"
    availability_zone="us-east-1a"
    key_name = "Crest"
    depends_on = [aws_instance.cm]
    network_interface{
      device_index=0
      network_interface_id= aws_network_interface.idx1-nic.id
    }
    user_data = <<-EOF
              #!/bin/bash
              sudo apt-get update
              sudo su
              wget -O splunk-8.1.1-08187535c166-Linux-x86_64.tgz 'https://www.splunk.com/bin/splunk/DownloadActivityServlet?architecture=x86_64&platform=linux&version=8.1.1&product=splunk&filename=splunk-8.1.1-08187535c166-Linux-x86_64.tgz&wget=true'
              tar -xvzf splunk-8.1.1-08187535c166-Linux-x86_64.tgz
              cd /splunk/bin/
              ./splunk start --accept-license --answer-yes --no-prompt --seed-passwd admin123
              ./splunk enable listen 9997 -auth admin:admin123
              ./splunk edit cluster-config -mode peer -master_uri https://${aws_instance.cm.public_ip}:8089 -replication_port 8080 -auth admin:admin123
               cd /splunk/etc/system/local/
               echo -e "\n[diskUsage] \nminFreeSpace = 500" >> server.conf
              cd /splunk/bin/
              ./splunk restart 
              EOF
}

output "idx1_ip_addr" {
  value = aws_instance.idx1.public_ip
}


resource "aws_instance" "idx2" {

    ami =  "ami-0885b1f6bd170450c"
    instance_type ="t2.micro"
    availability_zone="us-east-1a"
    key_name = "Crest"
    depends_on = [aws_instance.cm]
    network_interface{
      device_index=0
      network_interface_id= aws_network_interface.idx2-nic.id
    }
  user_data = <<-EOF
              #!/bin/bash
              sudo apt-get update
              sudo su
              wget -O splunk-8.1.1-08187535c166-Linux-x86_64.tgz 'https://www.splunk.com/bin/splunk/DownloadActivityServlet?architecture=x86_64&platform=linux&version=8.1.1&product=splunk&filename=splunk-8.1.1-08187535c166-Linux-x86_64.tgz&wget=true'
              tar -xvzf splunk-8.1.1-08187535c166-Linux-x86_64.tgz
              cd /splunk/bin
              ./splunk start --accept-license --answer-yes --no-prompt --seed-passwd admin123
              ./splunk enable listen 9997 -auth admin:admin123
              cd /splunk/etc/system/local/
              echo -e "\n[diskUsage] \nminFreeSpace = 500" >> server.conf
              cd /splunk/bin/
              ./splunk edit cluster-config -mode peer -master_uri https://${aws_instance.cm.public_ip}:8089 -replication_port 8080 -auth admin:admin123
              ./splunk restart
              EOF 
    
}
output "idx2_ip_addr" {
  value = aws_instance.idx2.public_ip
}

resource "aws_instance" "idx3" {

    ami =  "ami-0885b1f6bd170450c"
    instance_type ="t2.micro"
    availability_zone="us-east-1a"
    key_name = "Crest"
    depends_on = [aws_instance.cm]
    network_interface{
      device_index=0
      network_interface_id= aws_network_interface.idx3-nic.id
    }
  user_data = <<-EOF
            #!/bin/bash
            sudo apt-get update
            sudo su
            wget -O splunk-8.1.1-08187535c166-Linux-x86_64.tgz 'https://www.splunk.com/bin/splunk/DownloadActivityServlet?architecture=x86_64&platform=linux&version=8.1.1&product=splunk&filename=splunk-8.1.1-08187535c166-Linux-x86_64.tgz&wget=true'
            tar -xvzf splunk-8.1.1-08187535c166-Linux-x86_64.tgz
            cd /splunk/bin
            ./splunk start --accept-license --answer-yes --no-prompt --seed-passwd admin123
            ./splunk enable listen 9997 -auth admin:admin123
            ./splunk edit cluster-config -mode peer -master_uri https://${aws_instance.cm.public_ip}:8089 -replication_port 8080 -auth admin:admin123
            cd /splunk/etc/system/local/
            echo -e "\n[diskUsage] \nminFreeSpace = 500" >> server.conf
            cd /splunk/bin/
            ./splunk restart
            EOF   
}

output "idx3_ip_addr" {
  value = aws_instance.idx3.public_ip
}

resource "aws_instance" "forwarder" {

    ami =  "ami-0885b1f6bd170450c"
    instance_type ="t2.micro"
    availability_zone="us-east-1a"
    key_name = "Crest"
    depends_on = [aws_instance.cm,aws_instance.idx1]
    network_interface{
      device_index=0
      network_interface_id= aws_network_interface.forwarder-nic.id
    }
   user_data = <<-EOF
    #!/bin/bash
    sudo apt-get update
    sudo su
    wget -O splunkforwarder-8.1.1-08187535c166-Linux-x86_64.tgz 'https://www.splunk.com/bin/splunk/DownloadActivityServlet?architecture=x86_64&platform=linux&version=8.1.1&product=universalforwarder&filename=splunkforwarder-8.1.1-08187535c166-Linux-x86_64.tgz&wget=true'
    tar -xvzf splunkforwarder-8.1.1-08187535c166-Linux-x86_64.tgz
    cd /splunkforwarder/bin
    ./splunk start --accept-license --answer-yes --no-prompt --seed-passwd admin123
    ./splunk enable boot-start
    ./splunk add forward-server ${aws_instance.idx1.public_ip}:9997 -auth admin:admin123
    ./splunk add monitor /var/log/syslog -auth admin:admin123
    ./splunk restart
    EOF
    
}

output "forwarder_ip_addr" {
  value = aws_instance.forwarder.public_ip
}



