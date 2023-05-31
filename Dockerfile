FROM nvidia/cuda:12.1.0-base-ubuntu22.04

RUN apt-get update && \
    DEBIAN_FRONTEND=noninteractive apt-get install -yq --no-install-recommends \
    git \
    python-is-python3 \
    python3 \
    python3-cachecontrol \
    python3-pip \
    python3-venv\
    sudo \
    tmux \
    vim

COPY requirements.txt /

RUN pip install -r requirements.txt

# RUN pip install torch fastai jupyterlab
RUN pip install jupyterlab

EXPOSE 8888/udp

CMD [ "bash" ]
