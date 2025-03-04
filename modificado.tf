# Provider AWS
provider "aws" {
  region = "us-east-1"0
}

# Variáveis
variable "projeto" {
  description = "Nome do Projeto. O valor padrão é VExpenses."
  type        = string
  default     = "VExpenses"
}

variable "candidato" {
  description = "Nome do Candidato. O valor padrão é Emanuel Neemias Nerys Frutuoso."
  type        = string
  default     = "Emanuel Neemias Nerys Frutuoso"
}

variable "cidr_vpc" {
  description = "CIDR block da VPC. O valor padrão é 10.0.0.0/16."
  type        = string
  default     = "10.0.0.0/16"
}

variable "cidr_subnet" {
  description = "CIDR block da Subnet. O valor padrão é 10.0.1.0/24."
  type        = string
  default     = "10.0.1.0/24"
}

variable "zone" {
  description = "Zona de Disponibilidade. O valor padrão é us-east-1a."
  type        = string
  default     = "us-east-1a"
}

variable "ssh_allowed_ip" {
  description = "IP autorizado para SSH (Exemplo: 0.0.0.0/0 para permitir qualquer IP). O valor padrão é 0.0.0.0/0."
  type        = string
  default     = "0.0.0.0/0"  # Permitir qualquer IP, para testes
}

# Gerando chave privada RSA
resource "tls_private_key" "ec2_key" {
  description = "Gera uma chave privada RSA para ser usada no acesso SSH à instância EC2."
  algorithm = "RSA"
  rsa_bits  = 2048
}

# Criando o par de chaves para a EC2
resource "aws_key_pair" "ec2_key_pair" {
  description = "Cria um par de chaves para a EC2, utilizando a chave pública gerada anteriormente."
  key_name   = "${var.projeto}-${var.candidato}-key"
  public_key = tls_private_key.ec2_key.public_key_openssh
}

# Criando a VPC
resource "aws_vpc" "main_vpc" {
  description = "Cria uma Virtual Private Cloud (VPC) com suporte a DNS e resolução de nomes de host."
  cidr_block           = var.cidr_vpc
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = {
    Name = "${var.projeto}-${var.candidato}-vpc"
  }
}

# Criando a Subnet
resource "aws_subnet" "main_subnet" {
  description = "Cria uma Subnet dentro da VPC, associada à zona de disponibilidade configurada."
  vpc_id            = aws_vpc.main_vpc.id
  cidr_block        = var.cidr_subnet
  availability_zone = var.zone

  tags = {
    Name = "${var.projeto}-${var.candidato}-subnet"
  }
}

# Criando o Internet Gateway (IGW)
resource "aws_internet_gateway" "main_igw" {
  description = "Ceria um gateway de intrnet para a VPC, permitindo comunicação com a internet."
  vpc_id = aws_vpc.main_vpc.id

  tags = {
    Name = "${var.projeto}-${var.candidato}-igw"
  }
}

# Criando a Tabela de Roteamento
resource "aws_route_table" "main_route_table" {
  description = "Cria uma tabela de roteamento que define como o tráfego será roteado dentro da VPC."
  vpc_id = aws_vpc.main_vpc.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.main_igw.id
  }

  tags = {
    Name = "${var.projeto}-${var.candidato}-route_table"
  }
}

# Associando a Tabela de Roteamento à Subnet
resource "aws_route_table_association" "main_association" {
  description = "Associa a tabela de roteamento à subnet, garantindo que o tráfego seja roteado corretamente."
  subnet_id      = aws_subnet.main_subnet.id
  route_table_id = aws_route_table.main_route_table.id
}

# Criando o Security Group
resource "aws_security_group" "main_sg" {
  description = "Cria um grupo de segurança que permite SSH do IP autorizado e todo o tráfego de saída."
  name        = "${var.projeto}-${var.candidato}-sg"
  description = "Permitir SSH do IP específico e todo o tráfego de saída"
  vpc_id      = aws_vpc.main_vpc.id

  # Regras de entrada: SSH restrito ao IP configurado
  ingress {
    description      = "Allow SSH from any IP"
    from_port        = 22
    to_port          = 22
    protocol         = "tcp"
    cidr_blocks      = [var.ssh_allowed_ip]
    ipv6_cidr_blocks = ["::/0"]
  }

  # Regras de saída: Permitir todo tráfego de saída
  egress {
    description      = "Allow all outbound traffic"
    from_port        = 0
    to_port          = 0
    protocol         = "-1"
    cidr_blocks      = ["0.0.0.0/0"]
    ipv6_cidr_blocks = ["::/0"]
  }

  tags = {
    Name = "${var.projeto}-${var.candidato}-sg"
  }
}

# Buscando a AMI mais recente do Debian 12
data "aws_ami" "debian12" {
  description = "Busca a AMI mais recente do Debian 12, para ser utilizada na criação da instância EC2."
  most_recent = true

  filter {
    name   = "name"
    values = ["debian-12-amd64-*"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }

  owners = ["679593333241"]
}

# Criando a Instância EC2
resource "aws_instance" "debian_ec2" {
  description = "Cria uma instância EC2 com a AMI Debian 12, associada ao par de chaves e ao security group."
  ami             = data.aws_ami.debian12.id
  instance_type   = "t2.micro"
  subnet_id       = aws_subnet.main_subnet.id
  key_name        = aws_key_pair.ec2_key_pair.key_name
  security_groups = [aws_security_group.main_sg.name]

  # Configuração para associar IP público à instância
  associate_public_ip_address = true

  # Configuração do volume de armazenamento
  root_block_device {
    volume_size           = 20
    volume_type           = "gp2"
    delete_on_termination = true
  }

  # Script de inicialização da instância (Instalação do Nginx e desabilitação de login como root via SSH)
  user_data = <<-EOF
              #!/bin/bash
              apt-get update -y
              apt-get upgrade -y
              apt-get install -y nginx
              systemctl start nginx
              systemctl enable nginx
              echo "PermitRootLogin no" >> /etc/ssh/sshd_config
              service sshd restart
              EOF

  tags = {
    Name = "${var.projeto}-${var.candidato}-ec2"
  }
}

# Saídas do Terraform

# A chave privada gerada para acessar a instância EC2 será retornada como uma saída sensível.
output "private_key" {
  description = "Chave privada para acessar a instância EC2"
  value       = tls_private_key.ec2_key.private_key_pem
  sensitive   = true
}

# O IP público da instância EC2 será retornado como uma saída.
output "ec2_public_ip" {
  description = "Endereço IP público da instância EC2"
  value       = aws_instance.debian_ec2.public_ip
}

# MODIFICAÇÃO E MELHORIA DO CODIGO TERRAFORM, a descrição técnica solicitada na Tarefa 2, explicando as melhorias implementadas e justificando suas escolhas.

# Provider AWS
provider "aws" {
  description = "Provider da AWS que configura a região para provisionar os recursos."
  region = "us-east-1"  # A região foi configurada para 'us-east-1' com base em sua proximidade geográfica e performance adequada.
}

# Variáveis

variable "projeto" {
  description = "Nome do Projeto. O valor padrão é VExpenses."
  type        = string
  default     = "VExpenses"
}

variable "candidato" {
  description = "Nome do Candidato. O valor padrão é Emanuel Neemias Nerys Frutuoso."
  type        = string
  default     = "Emanuel Neemias Nerys Frutuoso"
}

variable "cidr_vpc" {
  description = "CIDR block da VPC. O valor padrão é 10.0.0.0/16."
  type        = string
  default     = "10.0.0.0/16"
}

variable "cidr_subnet" {
  description = "CIDR block da Subnet. O valor padrão é 10.0.1.0/24."
  type        = string
  default     = "10.0.1.0/24"
}

variable "zone" {
  description = "Zona de Disponibilidade. O valor padrão é us-east-1a."
  type        = string
  default     = "us-east-1a"
}

variable "ssh_allowed_ip" {
  description = "IP autorizado para SSH (Exemplo: 0.0.0.0/0 para permitir qualquer IP). O valor padrão é 0.0.0.0/0."
  type        = string
  default     = "0.0.0.0/0"  # Permitir qualquer IP, para testes. Em produção, deve ser restrito a um IP específico por segurança.
}