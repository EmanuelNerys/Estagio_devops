# Configuração do provider AWS, definindo a região onde os recursos serão criados.
provider "aws" {
  region = "us-east-1"
}

# Variável 'projeto' que define o nome do projeto. 
# A variável é do tipo string e possui um valor padrão de "VExpenses".
variable "projeto" {
  description = "Nome do projeto"
  type        = string
  default     = "VExpenses"
}

# Variável 'candidato' que define o nome do candidato.
# A variável é do tipo string e possui um valor padrão de "SeuNome".
variable "candidato" {
  description = "Nome do candidato"
  type        = string
  default     = "SeuNome"
}

# Recurso para gerar uma chave privada TLS RSA com 2048 bits.
# Esta chave será usada para configurar o acesso SSH à instância EC2.
resource "tls_private_key" "ec2_key" {
  algorithm = "RSA"
  rsa_bits  = 2048
}

# Recurso para criar um par de chaves no AWS.
# A chave é nomeada com base nas variáveis 'projeto' e 'candidato'.
# A chave pública é extraída da chave privada gerada acima.
resource "aws_key_pair" "ec2_key_pair" {
  key_name   = "${var.projeto}-${var.candidato}-key"
  public_key = tls_private_key.ec2_key.public_key_openssh
}

# Recurso para criar uma VPC (Virtual Private Cloud) com o bloco CIDR 10.0.0.0/16.
# A VPC habilita suporte a DNS e a nomes de host.
resource "aws_vpc" "main_vpc" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = {
    Name = "${var.projeto}-${var.candidato}-vpc"
  }
}

# Recurso para criar uma subnet dentro da VPC criada acima.
# O bloco CIDR é 10.0.1.0/24 e a subnet está na zona de disponibilidade 'us-east-1a'.
resource "aws_subnet" "main_subnet" {
  vpc_id            = aws_vpc.main_vpc.id
  cidr_block        = "10.0.1.0/24"
  availability_zone = "us-east-1a"

  tags = {
    Name = "${var.projeto}-${var.candidato}-subnet"
  }
}

# Recurso para criar um Internet Gateway (IGW) associado à VPC.
# O IGW permite que os recursos dentro da VPC se comuniquem com a internet.
resource "aws_internet_gateway" "main_igw" {
  vpc_id = aws_vpc.main_vpc.id

  tags = {
    Name = "${var.projeto}-${var.candidato}-igw"
  }
}

# Recurso para criar uma tabela de roteamento na VPC.
# A tabela define uma rota para permitir tráfego de saída para qualquer destino (0.0.0.0/0) via o Internet Gateway.
resource "aws_route_table" "main_route_table" {
  vpc_id = aws_vpc.main_vpc.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.main_igw.id
  }

  tags = {
    Name = "${var.projeto}-${var.candidato}-route_table"
  }
}

# Recurso para associar a tabela de roteamento à subnet criada anteriormente.
resource "aws_route_table_association" "main_association" {
  subnet_id      = aws_subnet.main_subnet.id
  route_table_id = aws_route_table.main_route_table.id

  tags = {
    Name = "${var.projeto}-${var.candidato}-route_table_association"
  }
}

# Recurso para criar um grupo de segurança na VPC.
# Este grupo permite o tráfego SSH (porta 22) de qualquer origem e todo o tráfego de saída.
resource "aws_security_group" "main_sg" {
  name        = "${var.projeto}-${var.candidato}-sg"
  description = "Permitir SSH de qualquer lugar e todo o tráfego de saída"
  vpc_id      = aws_vpc.main_vpc.id

  # Regras de entrada (Ingress) - Permite SSH de qualquer lugar.
  ingress {
    description      = "Allow SSH from anywhere"
    from_port        = 22
    to_port          = 22
    protocol         = "tcp"
    cidr_blocks      = ["0.0.0.0/0"]
    ipv6_cidr_blocks = ["::/0"]
  }

  # Regras de saída (Egress) - Permite todo tráfego de saída.
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

# Recurso para buscar a AMI mais recente do Debian 12 na AWS.
# A busca é feita com base no nome e tipo de virtualização.
data "aws_ami" "debian12" {
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

# Recurso para criar uma instância EC2 usando a AMI Debian 12.
# A instância é do tipo t2.micro e estará associada à subnet e grupo de segurança configurados anteriormente.
# A instância também será configurada para ter um endereço IP público e será inicializada com um script bash.
resource "aws_instance" "debian_ec2" {
  ami             = data.aws_ami.debian12.id
  instance_type   = "t2.micro"
  subnet_id       = aws_subnet.main_subnet.id
  key_name        = aws_key_pair.ec2_key_pair.key_name
  security_groups = [aws_security_group.main_sg.name]

  associate_public_ip_address = true

  # Configuração do volume de armazenamento para a instância EC2.
  # Volume de 20 GB com tipo 'gp2' e que será deletado ao término da instância.
  root_block_device {
    volume_size           = 20
    volume_type           = "gp2"
    delete_on_termination = true
  }

  # Script de user-data para atualização e upgrade do sistema Debian.
  user_data = <<-EOF
              #!/bin/bash
              apt-get update -y
              apt-get upgrade -y
              EOF

  tags = {
    Name = "${var.projeto}-${var.candidato}-ec2"
  }
}

# Output da chave privada para acesso SSH à instância EC2.
# Esta chave é sensível e será exibida como saída, sendo recomendada para uso imediato.
output "private_key" {
  description = "Chave privada para acessar a instância EC2"
  value       = tls_private_key.ec2_key.private_key_pem
  sensitive   = true
}

# Output do endereço IP público da instância EC2 criada.
# Esse IP permite acessar a instância via SSH.
output "ec2_public_ip" {
  description = "Endereço IP público da instância EC2"
  value       = aws_instance.debian_ec2.public_ip
}
