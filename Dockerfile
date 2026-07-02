FROM ubuntu:22.04

ARG GCOORDINATOR_REPO=https://github.com/tomohiron907/G-coordinator.git

ENV DEBIAN_FRONTEND=noninteractive
ENV PYTHONUNBUFFERED=1
ENV PYTHONDONTWRITEBYTECODE=1
ENV QT_X11_NO_MITSHM=1
ENV LIBGL_ALWAYS_SOFTWARE=1
ENV XDG_RUNTIME_DIR=/tmp/runtime-root

RUN apt-get -o Acquire::Check-Date=false update \
    && apt-get install -y --no-install-recommends \
        ca-certificates \
        git \
        python3 \
        python3-pip \
        python3-venv \
        xvfb \
        x11vnc \
        libdbus-1-3 \
        libfontconfig1 \
        libgl1 \
        libglib2.0-0 \
        libopengl0 \
        libsm6 \
        libxext6 \
        libxi6 \
        libxrender1 \
        libxkbcommon-x11-0 \
        libxcb-cursor0 \
        libxcb-icccm4 \
        libxcb-image0 \
        libxcb-keysyms1 \
        libxcb-randr0 \
        libxcb-render-util0 \
        libxcb-shape0 \
        libxcb-xfixes0 \
        libxcb-xinerama0 \
    && rm -rf /var/lib/apt/lists/*

RUN mkdir -p "$XDG_RUNTIME_DIR" /workspace /tmp/.X11-unix \
    && chmod 700 "$XDG_RUNTIME_DIR" \
    && chmod 1777 /tmp/.X11-unix

RUN git clone --depth 1 "$GCOORDINATOR_REPO" /opt/G-coordinator

WORKDIR /opt/G-coordinator

RUN python3 -m pip install --no-cache-dir --upgrade pip \
    && python3 -m pip install --no-cache-dir -r requirements.txt

RUN chmod -R a+rwX /opt/G-coordinator \
    && chmod -R a+rwX /usr/local/lib/python3.10/dist-packages/gcoordinator

COPY run-macos-container.sh /usr/local/bin/run-macos-container
RUN chmod 755 /usr/local/bin/run-macos-container

WORKDIR /opt/G-coordinator/src

CMD ["python3", "main.py"]
