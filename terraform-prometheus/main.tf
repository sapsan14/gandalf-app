provider "aws" {
  region = "eu-north-1"
}

resource "aws_security_group" "prom_sg" {
  name   = "prometheus-sg"
  vpc_id = var.vpc_id

  ingress {
    description = "Prometheus HTTP"
    from_port   = 9090
    to_port     = 9090
    protocol    = "tcp"
    cidr_blocks = var.allow_ingress_cidrs_to_prom
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_instance" "prometheus" {
  ami                    = "ami-0f326728ed51c4b5a" # Amazon Linux 2 latest
  instance_type          = "t3.micro"
  subnet_id              = var.subnet_id
  key_name               = var.key_name
  vpc_security_group_ids = [aws_security_group.prom_sg.id]

  user_data = <<-EOF
              #!/bin/bash
              yum update -y
              yum install -y wget tar

              cd /opt
              wget https://github.com/prometheus/prometheus/releases/download/v2.48.0/prometheus-2.48.0.linux-amd64.tar.gz
              tar xvf prometheus-2.48.0.linux-amd64.tar.gz
              cd prometheus-2.48.0.linux-amd64

              # Create Prometheus config
              cat > prometheus.yml <<EOL
              global:
                scrape_interval: 15s
              scrape_configs:
                - job_name: 'gandalf-app'
                  static_configs:
                    - targets:
                      - 'gandalf-headless.default.svc.cluster.local:80'
              EOL

              # Run Prometheus in background
              ./prometheus --config.file=prometheus.yml &
              EOF

  tags = {
    Name = "Prometheus-VM"
  }
}