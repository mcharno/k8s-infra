#!/bin/bash
# Script to create database secrets in k3s

set -e

echo "Setting up database secrets for k3s cluster..."
echo ""

# Prompt for database credentials
read -p "Enter database username [default: charno_user]: " DB_USER
DB_USER=${DB_USER:-charno_user}

read -sp "Enter database password: " DB_PASSWORD
echo ""

# Create namespace if it doesn't exist
kubectl create namespace charno-web --dry-run=client -o yaml | kubectl apply -f -

# Create database secret
kubectl create secret generic charno-secrets \
  --from-literal=db_user="$DB_USER" \
  --from-literal=db_password="$DB_PASSWORD" \
  --namespace=charno-web \
  --dry-run=client -o yaml | kubectl apply -f -

echo ""
echo "==================================================================="
echo "Database secrets created successfully!"
echo "==================================================================="
echo ""
