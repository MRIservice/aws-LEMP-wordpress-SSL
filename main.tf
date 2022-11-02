# Create variables from terraform.tfvars
variable vpc_az {
  type        = string
  default     = ""
  description = "availibility zone"
}


# vpc
resource "aws_vpc" "vpc1" {
  cidr_block       = "10.0.0.0/16"
  instance_tenancy = "default"

  tags = {
    Name = "vpc1"
  }
}

# gateway
resource "aws_internet_gateway" "igw-web1" {
  vpc_id = aws_vpc.vpc1.id

  tags = {
    Name = "igw-web1"
  }
}

# Route table
resource "aws_route_table" "PublicRT" {
  vpc_id = aws_vpc.vpc1.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.igw-web1.id
  }

  route {
    ipv6_cidr_block        = "::/0"
    gateway_id = aws_internet_gateway.igw-web1.id
  }

  tags = {
    Name = "PublicRT"
  }
}

# Subnet
resource "aws_subnet" "PublicSN" {
  vpc_id     = aws_vpc.vpc1.id
  cidr_block = "10.0.1.0/24"
  availability_zone = var.vpc_az

  tags = {
    Name = "PublicSN"
  }
}

# Associate subnet with route table
resource "aws_route_table_association" "a" {
  subnet_id      = aws_subnet.PublicSN.id
  route_table_id = aws_route_table.PublicRT.id
}

# security group ports 22, 80, 443
resource "aws_security_group" "webSG" {
  name        = "allow_web"
  description = "Allow web traffic"
  vpc_id      = aws_vpc.vpc1.id

  ingress {
    description      = "SSH"
    from_port        = 22
    to_port          = 22
    protocol         = "tcp"
    cidr_blocks      = ["0.0.0.0/0"]
    ipv6_cidr_blocks = ["::/0"]
  }

  ingress {
    description      = "HTTP"
    from_port        = 80
    to_port          = 80
    protocol         = "tcp"
    cidr_blocks      = ["0.0.0.0/0"]
    ipv6_cidr_blocks = ["::/0"]
  }

  ingress {
    description      = "HTTPS"
    from_port        = 443
    to_port          = 443
    protocol         = "tcp"
    cidr_blocks      = ["0.0.0.0/0"]
    ipv6_cidr_blocks = ["::/0"]
  }

  egress {
    from_port        = 0
    to_port          = 0
    protocol         = "-1"
    cidr_blocks      = ["0.0.0.0/0"]
    ipv6_cidr_blocks = ["::/0"]
  }

  tags = {
    Name = "allow_web_traffic"
  }
}

# Create network interface with an IP in the subnet 
resource "aws_network_interface" "NIC-1" {
  subnet_id       = aws_subnet.PublicSN.id
  private_ips     = ["10.0.1.100"]
  security_groups = [aws_security_group.webSG.id]

}

# assign elastic IP to the NIC
resource "aws_eip" "one" {
  vpc                       = true
  network_interface         = aws_network_interface.NIC-1.id
  associate_with_private_ip = "10.0.1.100"

  depends_on = [aws_internet_gateway.igw-web1]
}

output "server_public_ip" {
  value       = aws_eip.one.public_ip
  
}


# create ubuntu server install and enable NGINX

data "aws_ami" "ubuntu" {
  most_recent = true

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-focal-20.04-amd64-server-*"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
  
  owners = ["099720109477"] # Canonical
}

resource "aws_instance" "web" {
  ami           = data.aws_ami.ubuntu.id
  instance_type = "t2.micro"
  availability_zone = var.vpc_az
  key_name = "aws-kp1"

  network_interface {wordpress.conf
  network_interface_id = aws_network_interface.NIC-1.id
  device_index         = 0
   }

provisioner "file" {
    source      = "wordpress.conf"

    destination = "/tmp/wordpress.conf"

    connection {
      type        = "ssh"
      user        = "ubuntu"
      private_key = "${file("~/.aws/aws-kp1.pem")}"
      host        = self.public_ip
    }
  }
  credit_specification {
     cpu_credits = "unlimited"
   }


# boot strap user data for server build
user_data = <<EOF
#! /bin/bash
sudo -s
apt update && apt -y upgrade
apt install -y nginx mariadb-server php-fpm php-mysql php-curl php-dom php-mbstring php-imagick php-zip unzip memcached libmemcached-tools php-memcached
cp /tmp/wordpress.conf /etc/nginx/sites-available/
ln -s /etc/nginx/sites-available/wordpress.conf /etc/nginx/sites-enabled/
cd /var/www/
wget https://wordpress.org/latest.tar.gz
tar -xzvf latest.tar.gz
rm latest.tar.gz
chown -R www-data:www-data wordpress/
find wordpress/ -type d -exec chmod 755 {} \;
find wordpress/ -type f -exec chmod 644 {} \;
systemctl enable nginx
#
# Let's Encrypt
snap install core;
snap refresh core
snap install --classic certbot
ln -s /snap/bin/certbot /usr/bin/certbot
#
# Make sure that NOBODY can access the server without a password
mysql -e "UPDATE mysql.user SET Password = PASSWORD('1#4zupquif7&546JJ') WHERE User = 'root'"
# Remove the anonymous users
mysql -e "DROP USER ''@'localhost'"
# Because our hostname varies we'll use some Bash magic here.
mysql -e "DROP USER ''@'$(hostname)'"
# Remove the demo database
mysql -e "DROP DATABASE test"
# Make db changes take effect
mysql -e "FLUSH PRIVILEGES"
# Any subsequent tries to run queries this way will get access denied because lack of usr/pwd param
mysql -e "CREATE DATABASE wordpress"
# Wordpress database
mysql -e "CREATE USER 'wpuser'@'localhost' IDENTIFIED BY '1#zwhip&&ZIP*#'"
# Wordpres user
mysql -e "GRANT ALL PRIVILEGES ON wordpress.* TO 'wpuser'@'localhost'"
# 
mysql -e "FLUSH PRIVILEGES"

reboot

EOF

  tags = {
    Name = "WebServ-WP1"
  }
}

