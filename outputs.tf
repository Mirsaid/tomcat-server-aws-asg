output "lb_endpoint" {
  value = "https://${aws_lb.web-server-lb.dns_name}"
}

