# Frappe v17 develop stack: Python 3.14 + Node 24
#
# Base image: official frappe/bench (tags follow bench CLI versioning v5.x,
# NOT Frappe framework version). There is no frappe/bench:v17 image — framework
# version comes from your bind-mounted src/frappe checkout (17.0.0-dev).
# Pin BENCH_IMAGE_TAG in .env (default: v5.31.0, latest bench release on Docker Hub).
ARG BENCH_IMAGE_TAG=v5.31.0
FROM frappe/bench:${BENCH_IMAGE_TAG}

USER root

RUN apt-get update \
	&& apt-get install -y --no-install-recommends \
		mariadb-client \
		wait-for-it \
		curl \
		gosu \
	&& rm -rf /var/lib/apt/lists/*

USER frappe
WORKDIR /home/frappe

# Bench runtime lives on a persistent volume; app source is bind-mounted separately.
ENV FRAPPE_BENCH_ROOT=/home/frappe/frappe-bench
ENV BENCH_DIR=/home/frappe/frappe-bench
ENV WORKSPACE_SRC=/workspace/src

COPY --chown=frappe:frappe init.sh /workspace/docker/init.sh
COPY --chown=frappe:frappe scripts/ /workspace/docker/scripts/

RUN chmod +x /workspace/docker/init.sh /workspace/docker/scripts/*.sh

ENTRYPOINT ["/workspace/docker/scripts/entrypoint.sh"]
