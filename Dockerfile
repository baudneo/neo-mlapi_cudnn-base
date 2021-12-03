# syntax=docker/dockerfile:experimental
ARG S6_ARCH=amd64
ARG MLAPI_VERSION=master
ARG OPENCV_VERSION=4.5.4
# I think a minimum of 6.1 Compute Cabability required - these are GeForce cards
# CHECK https://developer.nvidia.com/cuda-gpus#compute
# 6.1 = 1050 thru to 1080ti includes TITAN X and TITAN XP
# 7.0 = TITAN V
# 7.5 = 1650 thru to 2080ti including TITAN RTX
# 8.6 = 3050 thru to 3090
ARG CUDA_ARCH_BIN="6.1 7.5"
ARG MLAPI_PORT=5000
#####################################################################
#                                                                   #
# Convert rootfs to LF using dos2unix                               #
# Alleviates issues when git uses CRLF on Windows                   #
#                                                                   #
#####################################################################
FROM alpine:latest as rootfs-converter
WORKDIR /rootfs

RUN set -x \
    && apk add --repository=http://dl-cdn.alpinelinux.org/alpine/edge/community/ \
        dos2unix

COPY rootfs .
RUN set -x \
    && find . -type f -print0 | xargs -0 -n 1 -P 4 dos2unix

#####################################################################
#                                                                   #
# Download and extract s6 overlay                                   #
#                                                                   #
#####################################################################
FROM alpine:latest as s6downloader
# Required to persist build arg
ARG S6_ARCH
WORKDIR /s6downloader

RUN set -x \
    && wget -O /tmp/s6-overlay.tar.gz "https://github.com/just-containers/s6-overlay/releases/latest/download/s6-overlay-${S6_ARCH}.tar.gz" \
    && mkdir -p /tmp/s6 \
    && tar zxvf /tmp/s6-overlay.tar.gz -C /tmp/s6 \
    && cp -r /tmp/s6/* .

RUN set -x \
    && wget -O /tmp/socklog-overlay.tar.gz "https://github.com/just-containers/socklog-overlay/releases/latest/download/socklog-overlay-${S6_ARCH}.tar.gz" \
    && mkdir -p /tmp/socklog \
    && tar zxvf /tmp/socklog-overlay.tar.gz -C /tmp/socklog \
    && cp -r /tmp/socklog/* .

#####################################################################
#                                                                   #
# Neo MLAPI with GPU and TPU support                                   #
#                                                                   #
#####################################################################

FROM  nvidia/cuda:11.4.2-cudnn8-devel-ubuntu20.04 as base_image
ARG DEBIAN_FRONTEND=noninteractive
ARG OPENCV_VERSION
ARG CUDA_ARCH_BIN

RUN apt-get update && apt-get upgrade -y &&\
    # Install build tools, build dependencies and python
    apt-get install -y \
	python3-pip \
        build-essential \
        cmake \
        git \
        wget \
        unzip \
        yasm \
        pkg-config \
        libswscale-dev \
        libtbb2 \
        libtbb-dev \
        libjpeg-dev \
        libpng-dev \
        libtiff-dev \
        libavformat-dev \
        libpq-dev \
        libxine2-dev \
        libglew-dev \
        libtiff5-dev \
        zlib1g-dev \
        libjpeg-dev \
        libavcodec-dev \
        libavformat-dev \
        libavutil-dev \
        libpostproc-dev \
        libswscale-dev \
        libeigen3-dev \
        libtbb-dev \
        libgtk2.0-dev \
        pkg-config \
        gfortran \
        libatlas-base-dev \
        libopenblas-dev \
        liblapack-dev \
        libblas-dev \
        libev-dev \
        libevdev2 \
        libgeos-dev \
        ## Python
        python3-dev \
        python3-numpy \
    && rm -rf /var/lib/apt/lists/*

RUN mkdir /config
# https://github.com/opencv/opencv/archive/refs/tags/4.5.4.zip
    # OpenCV with cuDNN - cuDNN is supplied by the nvidia cuda container
RUN cd /opt/ &&\
    # Download and unzip OpenCV and opencv_contrib and delete zip files
    wget https://github.com/opencv/opencv/archive/${OPENCV_VERSION}.zip &&\
    unzip ${OPENCV_VERSION}.zip &&\
    rm ${OPENCV_VERSION}.zip &&\
    wget https://github.com/opencv/opencv_contrib/archive/${OPENCV_VERSION}.zip &&\
    unzip ${OPENCV_VERSION}.zip &&\
    rm ${OPENCV_VERSION}.zip &&\
    # Create build folder and switch to it
    mkdir -p /opt/opencv-${OPENCV_VERSION}/build && cd /opt/opencv-${OPENCV_VERSION}/build &&\
    # Cmake configure
   cmake -D CMAKE_BUILD_TYPE=RELEASE \
		-D OPENCV_EXTRA_MODULES_PATH=/opt/opencv_contrib-${OPENCV_VERSION}/modules \
        -D CMAKE_INSTALL_PREFIX=/usr/local \
        -D INSTALL_PYTHON_EXAMPLES=OFF \
        -D INSTALL_C_EXAMPLES=OFF \
        -D OPENCV_ENABLE_NONFREE=ON \
        -D WITH_CUDA=ON \
        -D WITH_CUDNN=ON \
        -D OPENCV_DNN_CUDA=ON \
        -D CUDA_ARCH_BIN=${CUDA_ARCH_BIN} \
        -D ENABLE_FAST_MATH=1 \
        -D CUDA_FAST_MATH=1 \
        -D WITH_CUBLAS=1 \
        -D HAVE_opencv_python3=ON \
        -D PYTHON_EXECUTABLE=/usr/bin/python3 \
        -D BUILD_EXAMPLES=OFF .. > /config/opencv-cmake.log && \
    make -j${nproc} && \
    # Install to /usr/local/lib
    make -j${nproc} install && \
    ldconfig &&\
    # Remove OpenCV sources and build folder
    rm -rf /opt/opencv-${OPENCV_VERSION} && rm -rf /opt/opencv_contrib-${OPENCV_VERSION}

# Install coral usb libraries
RUN 	echo "deb https://packages.cloud.google.com/apt coral-edgetpu-stable main" | \
            tee /etc/apt/sources.list.d/coral-edgetpu.list && \
		curl https://packages.cloud.google.com/apt/doc/apt-key.gpg | apt-key add - && \
		apt-get update && apt-get -y install gasket-dkms libedgetpu1-std python3-pycoral

# neo-pyzm
RUN   python3 -m pip install git+https://github.com/baudneo/pyzm.git
RUN   mkdir /mlapi

RUN   cd /mlapi && git clone https://github.com/baudneo/mlapi.git . && \
      git checkout ${MLAPI_VERSION} \
      python3 -m pip install -r ./requirements.txt

# ALPR with GPU
# Install prerequisites
# this includes all the ones missing from OpenALPR's guide.
RUN   apt-get -y install libtesseract-dev libleptonica-dev liblog4cplus-dev libcurl3-dev libleptonica-dev && \
      apt-get -y install libcurl4-openssl-dev liblog4cplus-dev \
# Clone the repo, copy config and enable gpu detections in config
RUN   cd /opt && git clone https://github.com/openalpr/openalpr.git && cd ./openalpr/src && mkdir build && cd build \
      && cp /opt/openalpr/config/openalpr.conf.defaults /config/alpr.conf && \
       sed -i 's/detector = lbpcpu/detector = lbpgpu/g' /config/alpr.conf \
      && rm -rf /opt/alpr

# setup the compile environment and compile
RUN   cmake " \
      -D CMAKE_INSTALL_PREFIX:PATH=/usr \
      -D CMAKE_INSTALL_SYSCONFDIR:PATH=/etc \
       –D COMPILE_GPU=1 \
       -D WITH_GPU_DETECTOR=ON \
       .." && \
      make -j"$(nproc)" && make install \
# Copy config file with gpu detetcions active to /etc/openalpr/
RUN   mv /config/alpr.conf /etc/openalpr/ && rm -rf /opt/openalpr

# Make sure face_recognition and DLib are installed
RUN   python3 -m pip install face_recognition

## Create www-data user
RUN set -x \
    && groupmod -o -g 911 www-data \
    && usermod -o -u 911 www-data
# Create plugdev user/group for TPU and add www-data to its group (add plugdev to www-data?)
RUN set -x \
    && groupmod -o -g 901 plugdev \
    && usermod -o -u 901 plugdev \
    && usermod -aG plugdev www-data #\
#    && usermod -aG www-data plugdev


RUN set -x && \
    mkdir -p /config/models && \
    cp /mlapi/mlapi_dbuser.py /config && \
    cp /mlapi/mlapi_face_train.py /config && \
    cp /mlapi/get_encryption_key.py /config && \
    cp /mlapi/images/ /config && \
    cp /mlapi/known_faces/ /config && \
    cp /mlapi/unknown_faces/ /config && \
    cp /mlapi/tools/ /config && \
    cp /mlapi/logs/ /config && \
    cp /mlapi/db/ /config && \
    cp /mlapi/examples/ /config && \
    cp /mlapi/tools/ /config && \
    cp /mlapi/get_models.sh /config && \
    cp /mlapi/mlapiconfig.yml /config && \
    cp /mlapi/mlapisecrets.yml /config



RUN set -x \
    && mkdir -p \
        /log \
    && chown -R www-data:www-data \
        /config \
        /mlapi \
        /log \
    && chmod -R 755 \
        /config \
        /mlapi \
        /log \
    && chown -R nobody:nogroup \
        /log
# download ML models
RUN set -x \
    && cd /config \
    && chmod +x /config/get_models.sh \
    && TARGET_DIR=/config/models \
    INSTALL_YOLOV3=yes \
    INSTALL_YOLOV4=yes \
    INSTALL_CORAL_EDGETPU=yes \
    ./get_models.sh

# Install s6 overlay
COPY --from=s6downloader /s6downloader /
# Copy rootfs
COPY --from=rootfs-converter /rootfs /

# System Variables
ENV \
    S6_FIX_ATTRS_HIDDEN=1 \
    S6_BEHAVIOUR_IF_STAGE2_FAILS=2 \
    SOCKLOG_TIMESTAMP_FORMAT="" \
    MAX_LOG_SIZE_BYTES=1000000 \
    MAX_LOG_NUMBER=10

# User default variables
ENV     \
        PUID=911\
        PGID=911\
        TZ="America/Chicago"\
        USE_SECURE_RANDOM_ORG=1

EXPOSE 5000/tcp

CMD ["/init"]