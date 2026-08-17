# Development image for this repository.
#
# Thin by construction: the packages, timezone, zsh configuration and commitizen setup
# that would otherwise live here are installed by the devbase Feature — the very
# Feature this repository ships. If you find yourself adding one of those back, that is
# a signal the Feature is missing something, not that this file needs a layer.

FROM mcr.microsoft.com/devcontainers/base:2-ubuntu-24.04

ENV DEBIAN_FRONTEND=noninteractive
ENV TERM=xterm-256color
