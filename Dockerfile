# syntax=docker/dockerfile:experimental
ARG S6_ARCH=amd64
ARG MLAPI_VERSION=master
ARG PYZM_VERSION=master
ARG OPENCV_VERSION=4.5.4
# I think a minimum of 6.1 Compute Cabability required - these are GeForce cards
# CHECK https://developer.nvidia.com/cuda-gpus#compute
# 6.1 = 1050 thru to 1080ti includes TITAN X and TITAN XP
# 7.0 = TITAN V
# 7.5 = 1650 thru to 2080ti including TITAN RTX
# 8.6 = 3050 thru to 3090
#ARG CUDA_ARCH_BIN=6.1,7.5
ARG CUDA_ARCH_BIN=6.0,6.1,7.0,7.5,8.0,8.6
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
FROM alpine:latest AS s6downloader
# Required to persist build arg
ARG S6_ARCH
WORKDIR /s6downloader

RUN set -x \
    && wget -O /tmp/s6-overlay.tar.gz "https://github.com/just-containers/s6-overlay/releases/download/v2.2.0.3/s6-overlay-amd64.tar.gz" \
    && mkdir -p /tmp/s6 \
    && tar zxvf /tmp/s6-overlay.tar.gz -C /tmp/s6 \
    && cp -r /tmp/s6/* .

RUN set -x \
    && wget -O /tmp/socklog-overlay.tar.gz "https://github.com/just-containers/socklog-overlay/releases/download/v3.1.0-2/socklog-overlay-amd64.tar.gz" \
    && mkdir -p /tmp/socklog \
    && tar zxvf /tmp/socklog-overlay.tar.gz -C /tmp/socklog \
    && cp -r /tmp/socklog/* .
#####################################################################
#                                                                   #
# Build OpenCV and DLib from source                                 #
#                                                                   #
#####################################################################

FROM  nvidia/cuda:11.4.2-cudnn8-devel-ubuntu20.04 as build-env
ARG DEBIAN_FRONTEND=noninteractive
ARG OPENCV_VERSION
ARG CUDA_ARCH_BIN


# Update, Locale, apt-utils, ca certs and Upgrade
RUN set -x \
  && apt-get update -y --fix-missing\
  && apt-get install -y \
    apt-utils \
    locales \
    ca-certificates \
  && apt-get upgrade -y \
  && apt-get clean

# Set Locale to en_US.UTF-8
RUN set -x \
    && localedef \
        -i en_US \
        -c -f UTF-8 \
        -A /usr/share/locale/locale.alias \
        en_US.UTF-8
ENV LANG en_US.utf8

# Install system packages
RUN set -x \
    && apt-get install -y \
      x264 \
      v4l-utils \
      curl \
      git \
      perl \
      rsync \
      unzip \
      wget \
      zip \
          build-essential \
          checkinstall \
          cmake \
          g++ \
          gcc \
          pkg-config \
          protobuf-compiler \
          zlib1g-dev \
    && apt-get clean

# Python and libs
RUN set -x \
    && apt-get install -y \
        python3-pip \
        python3-dev \
        python3-numpy \
        doxygen \
            file \
            gfortran \
            gnupg \
            gstreamer1.0-plugins-good \
            imagemagick \
            libatk-adaptor \
            libatlas-base-dev \
            libavcodec-dev \
            libavformat-dev \
            libavutil-dev \
            libboost-all-dev \
            libcanberra-gtk-module \
            libdc1394-22-dev \
            libeigen3-dev \
            libfaac-dev \
            libfreetype6-dev \
            libgflags-dev \
            libglew-dev \
            libglu1-mesa \
            libglu1-mesa-dev \
            libgoogle-glog-dev \
            libgphoto2-dev \
            libgstreamer1.0-dev \
            libgstreamer-plugins-bad1.0-0 \
            libgstreamer-plugins-base1.0-dev \
            libgtk2.0-dev \
            libgtk-3-dev \
            libhdf5-dev \
            libhdf5-serial-dev \
            libjpeg-dev \
            liblapack-dev \
            libmp3lame-dev \
            libopenblas-dev \
            libopencore-amrnb-dev \
            libopencore-amrwb-dev \
            libopenjp2-7 \
            libopenjp2-7-dev \
            libopenjp2-tools \
            libopenjpip-server \
            libpng-dev \
            libpostproc-dev \
            libprotobuf-dev \
            libswscale-dev \
            libtbb2 \
            libtbb-dev \
            libtheora-dev \
            libtiff5-dev \
            libv4l-dev \
            libvorbis-dev \
            libx264-dev \
            libxi-dev \
            libxine2-dev \
            libxmu-dev \
            libxvidcore-dev \
            libzmq3-dev \
            x11-apps \
            yasm \
            libatlas-base-dev \
            libopenblas-dev \
            liblapack-dev \
            libblas-dev \
            libev-dev \
            libevdev2 \
            libgeos-dev \
            libssl-dev \
            libtesseract-dev \
            libleptonica-dev \
            liblog4cplus-dev \
            libcurl3-dev \
            libleptonica-dev \
            libcurl4-openssl-dev \
            liblog4cplus-dev \
            time \
    && cd /opt/ \
    && wget https://github.com/opencv/opencv/archive/${OPENCV_VERSION}.zip \
    && unzip ${OPENCV_VERSION}.zip \
    && rm ${OPENCV_VERSION}.zip \
    && wget https://github.com/opencv/opencv_contrib/archive/${OPENCV_VERSION}.zip \
    && unzip ${OPENCV_VERSION}.zip \
    && rm ${OPENCV_VERSION}.zip \
    && apt-get clean


RUN set -x \
    && mkdir -p /tmp/opencv_export \
    && mkdir -p /tmp/opencv_python_bindings \
    && mkdir -p /opt/opencv-${OPENCV_VERSION}/build \
    && cd /opt/opencv-${OPENCV_VERSION}/build \
    && cd /opt/opencv-${OPENCV_VERSION}/build \
    && time cmake \
        -D BUILD_DOCS=OFF \
        -D BUILD_EXAMPLES=OFF \
        -D BUILD_PERF_TESTS=OFF \
        -D BUILD_TESTS=OFF \
        -D BUILD_opencv_python2=OFF \
        -D BUILD_opencv_python3=ON \
        -D HAVE_opencv_python3=ON \
        -D HAVE_opencv_python2=OFF \
        -D CMAKE_BUILD_TYPE=RELEASE \
        -D OPENCV_PYTHON3_INSTALL_PATH=/tmp/opencv_python_bindings \
#        -D CMAKE_INSTALL_PREFIX=/usr/local/ \
        -D CMAKE_INSTALL_PREFIX=/tmp/opencv_export \
        -D PYTHON3_NUMPY_INCLUDE_DIR=/usr/lib/python3/dist-packages/numpy/core/include \
        -D CMAKE_INSTALL_TYPE=RELEASE \
        -D FORCE_VTK=ON \
        -D INSTALL_C_EXAMPLES=OFF \
        -D INSTALL_PYTHON_EXAMPLES=OFF \
        -D OPENCV_GENERATE_PKGCONFIG=ON \
        -D WITH_CSTRIPES=ON \
        -D WITH_EIGEN=ON \
        -D WITH_GDAL=ON \
        -D WITH_GSTREAMER=ON \
        -D WITH_GSTREAMER_0_10=OFF \
        -D WITH_GTK=ON \
        -D WITH_IPP=ON \
        -D WITH_OPENCL=ON \
        -D WITH_OPENMP=ON \
        -D WITH_TBB=ON \
        -D WITH_V4L=ON \
        -D WITH_WEBP=ON \
        -D WITH_XINE=ON \
        -D OPENCV_EXTRA_MODULES_PATH=/opt/opencv_contrib-${OPENCV_VERSION}/modules \
        -D OPENCV_ENABLE_NONFREE=ON \
        -D CUDA_ARCH_BIN=${CUDA_ARCH_BIN} \
        -D WITH_CUDA=ON \
        -D WITH_CUDNN=ON \
        -D OPENCV_DNN_CUDA=ON \
        -D ENABLE_FAST_MATH=1 \
        -D CUDA_FAST_MATH=1 \
        -D WITH_CUBLAS=1 \
        -D PYTHON_EXECUTABLE=/usr/bin/python3 \
        .. && \
    time make -j${nproc} install

# DLib
ARG DLIB_BRANCH=v19.22
RUN wget -c -q https://github.com/davisking/dlib/archive/$DLIB_BRANCH.tar.gz \
    && tar xf $DLIB_BRANCH.tar.gz \
    && mv dlib-* dlib \
    && cd dlib/dlib \
    && mkdir build \
    && cd build \
    && mkdir -p /tmp/dlib_export \
    && cmake \
      -D CMAKE_INSTALL_PREFIX=/tmp/dlib_export \
#      -D BUILD_SHARED_LIBS=ON \
      -D DLIB_USE_CUDA_COMPUTE_CAPABILITIES=${CUDA_ARCH_BIN} \
      -D LIB_USE_CUDA=1 \
      --config Release .. \
    && time make -j${nproc} && \
    make -j${nproc} install && \
    cd /dlib && \
    python3 setup.py install


# openALPR
RUN   set -x \
      && mkdir -p \
          /tmp/alpr_export \
          /tmp/etc/openalpr \
      && cd /opt \
      && git clone https://github.com/openalpr/openalpr.git \
      && cd /opt/openalpr/src \
      && mkdir build \
      && cd build \
      && cd /opt/openalpr/src/build \
      && cp /opt/openalpr/config/openalpr.conf.defaults /tmp/etc/openalpr/openalpr.conf.gpu \
      && sed -i 's/detector = lbpcpu/detector = lbpgpu/g' /tmp/etc/openalpr/openalpr.conf.gpu \
      && cmake \
          -D CMAKE_INSTALL_PREFIX:PATH=/tmp/alpr_export \
          -D CMAKE_PREFIX_PATH=/tmp/opencv_export \
          -D CMAKE_INSTALL_SYSCONFDIR:PATH=/tmp/etc \
          -D COMPILE_GPU=1 \
          -D WITH_GPU_DETECTOR=ON \
           .. \
      && time make -j"$(nproc)" \
      && make install

################################################################################
#
#   Last stage
#
################################################################################

FROM nvidia/cuda:11.4.2-cudnn8-runtime-ubuntu20.04 as final_image
# Install OpenCV, DLib, openALPR
COPY --from=build-env /tmp/opencv_export /opt/opencv
COPY --from=build-env /tmp/opencv_python_bindings/cv2 /usr/local/lib/python3.8/dist-packages/cv2


ARG DEBIAN_FRONTEND=noninteractive
RUN set -x \
  && apt-get update -y --fix-missing\
  && apt-get install -y \
    apt-utils \
    locales \
    ca-certificates \
  && apt-get upgrade -y \
  && apt-get clean

# Set Locale to en_US.UTF-8
RUN set -x \
    && localedef \
        -i en_US \
        -c -f UTF-8 \
        -A /usr/share/locale/locale.alias \
        en_US.UTF-8 \
    && apt-get install -y python3-pip

COPY  --from=build-env /tmp/dlib_export /usr/local
COPY  --from=build-env /usr/local/lib/python3.8/dist-packages /usr/local/lib/python3.8/dist-packages
RUN set -x \
    && apt-get -y install \
      build-essential \
      curl \
      cmake \
      pkg-config \
    && sh -c 'echo "/opt/opencv/lib" >> /etc/ld.so.conf.d/opencv.conf' \
    && ldconfig \
    && echo "deb https://packages.cloud.google.com/apt coral-edgetpu-stable main" | \
                  tee /etc/apt/sources.list.d/coral-edgetpu.list \
	&& curl https://packages.cloud.google.com/apt/doc/apt-key.gpg | apt-key add - \
	&& apt-get update \
	&& apt-get -y install \
	    gasket-dkms \
	    libedgetpu1-std \
	    python3-pycoral \
    && python3 -m pip install face_recognition \
    && apt-get purge -y \
      build-essential \
      curl \
      cmake \
      pkg-config \
    && apt-get autoremove -y \
    && rm -rf /root/cache/pip && \
    apt clean




## Create www-data user, add to plugdev group in case of TPU perms issuea
RUN set -x \
    && groupmod -o -g 911 www-data \
    && usermod -o -u 911 www-data \
    && usermod -aG nogroup www-data \
    && usermod -aG plugdev www-data
COPY --from=build-env /tmp/alpr_export /usr

#COPY --from=build-env /tmp/dlib_export /opt/dlib
ARG PYZM_VERSION
ARG MLAPI_VERSION

COPY --from=build-env /tmp/etc /etc

# Fix cv2 python config
RUN set -x \
    && sed -i "s|/tmp/opencv_python_bindings/|/usr/local/lib/python3.8/dist-packages/|g" /usr/local/lib/python3.8/dist-packages/cv2/config-3.8.py \
    && sed -i "s|/tmp/opencv_export|/opt/opencv|" /usr/local/lib/python3.8/dist-packages/cv2/config.py \
    && cp /etc/openalpr/openalpr.conf.gpu /etc/openalpr/openalpr.conf \
    && apt-get install -y \
      libhdf5-serial-dev \
      libharfbuzz-dev \
      libpng-dev \
      libjpeg-dev \
      libgif-dev \
      libopenblas-dev \
      libtbb-dev \
      libgoogle-glog-dev \
      libtesseract-dev \
      libgtk-3-dev \
      libxine2-dev \
      libdc1394-22-dev \
      libgstreamer1.0-dev \
      libgstreamer-plugins-base1.0-dev \
      libavcodec-dev \
      libavformat-dev \
      libswscale-dev && \
    sed -i "s|\${CMAKE_INSTALL_PREFIX}|/usr|" /etc/openalpr/openalpr.conf

RUN   set -x \
      && apt-get install -y \
         git wget curl \
         libev-dev \
         libevdev2 \
         libgeos-dev \
      && python3 -m pip install "git+https://github.com/baudneo/pyzm.git@${PYZM_VERSION}" \
      && mkdir /mlapi_default \
      && mkdir /mlapi \
      && cd /mlapi_default \
      && git clone https://github.com/baudneo/mlapi.git . \
      && git checkout ${MLAPI_VERSION} \
      && python3 -m pip install -r ./requirements.txt \
      && mkdir -p ./models \
      && \
          TARGET_DIR=./models \
          INSTALL_CORAL_EDGETPU=yes \
          INSTALL_TINYYOLOV4=yes \
          INSTALL_TINYYOLOV3=yes \
          INSTALL_YOLOV4=yes \
          INSTALL_YOLOV3=yes \
          WGET=/usr/bin/wget \
        ./get_models.sh > /dev/null 2>&1 \
      && pip install bjoern \
      && cp ./mlapi.py /mlapi/mlapi.py \
      && mkdir /tpu_test \
      && git clone https://github.com/google-coral/pycoral.git \
      && cd pycoral \
      && bash examples/install_requirements.sh classify_image.py \
      && cp examples/classify_image.py /tpu_test/ \
      && cp test_data/mobilenet_v2_1.0_224_inat_bird_quant_edgetpu.tflite /tpu_test/ \
      && cp test_data/inat_bird_labels.txt /tpu_test/ \
      && cp test_data/parrot.jpg /tpu_test/ \
      && echo "python3 /tpu_test/classify_image.py \
--model /tpu_test/mobilenet_v2_1.0_224_inat_bird_quant_edgetpu.tflite \
--labels /tpu_test/inat_bird_labels.txt \
--input /tpu_test/parrot.jpg" > ./tpu_test \
      && chmod +x ./tpu_test \
      && cp ./tpu_test /usr/bin \
      && cd / \
      && wget "http://plates.openalpr.com/h786poj.jpg" -O /tpu_test/lp.jpg \
      && echo "alpr /tpu_test/lp.jpg" > /alpr_test \
      && chmod +x /alpr_test \
      && mv /alpr_test /usr/bin \
      && apt-get purge -y git \
      && apt-get autoremove -y \
      && apt clean && \
      rm -rf /pycoral

## Log dir and perms
RUN set -x \
    && mkdir -p \
        /log \
        /config/images \
    && chown -R www-data:www-data \
        /config \
        /mlapi \
        /mlapi_default \
        /log \
    && chmod -R 765 \
        /config \
        /mlapi \
        /mlapi_default \
    && chmod -R 766 \
       /log \
    && chown -R nobody:nogroup \
        /log

COPY ./extras/gpu_test.py /usr/bin/gpu_test
COPY ./extras/person_test.jpg /tpu_test/
COPY ./extras/biden.jpg /tpu_test/
COPY ./extras/face_gpu_test.py /usr/bin/face_gpu_test

RUN  set -x \
     && chmod +x /usr/bin/gpu_test \
     && chmod +x /usr/bin/face_gpu_test


# Install s6 overlay
COPY --from=s6downloader /s6downloader /
# Copy rootfs
COPY --from=rootfs-converter /rootfs /

# System Variables
ENV \
    S6_FIX_ATTRS_HIDDEN=1 \
    S6_BEHAVIOUR_IF_STAGE2_FAILS=2 \
    SOCKLOG_TIMESTAMP_FORMAT="" \
    MAX_LOG_SIZE_BYTES=50000000 \
    MAX_LOG_NUMBER=10

# User default variables
ENV \
    PUID=911\
    PGID=911\
    TZ="America/Chicago"\
    USE_SECURE_RANDOM_ORG=1\
    MLAPI_CONTAINER=mlapi\
    MLAPIDB_USER=mlapi_user\
    MLAPIDB_PASS=ZoneMinder\
    MLAPI_DEBUG_ENABLED=1\
    NVIDIA_VISIBLE_DEVICES=all\
    NVIDIA_DRIVER_CAPABILITIES=compute,utility,video\
    OPENALPR_CONFIG_FILE=/etc/openalpr/openalpr.conf

LABEL com.github.baudneo.mlapi_version=${MLAPI_VERSION}
EXPOSE 5000
CMD ["/init"]
