#!/bin/bash

mkdir -p manifests/prometheus
git clone --depth 1 --branch v0.13.0 \
  https://github.com/prometheus-operator/kube-prometheus.git \
  manifests/prometheus
