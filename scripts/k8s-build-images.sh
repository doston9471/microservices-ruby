#!/usr/bin/env bash
set -euo pipefail

docker build -t service1:local ./service1
docker build -t service2:local ./service2
kind load docker-image service1:local service2:local --name microservices
echo "Done. Images loaded into kind cluster 'microservices'."