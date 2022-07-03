# Neo-MLAPI with GPU / TPU
![Status](https://img.shields.io/badge/Status-BETA-orange)

== I am Using GitHub Under Protest ==

This project is currently hosted on GitHub.  This is not ideal; GitHub is a
proprietary, trade-secret system that is not Free and Open Souce Software
(FOSS).  I am deeply concerned about using a proprietary system like GitHub
to develop my FOSS project. I urge you to read about the
[Give up GitHub](https://GiveUpGitHub.org) campaign from
[the Software Freedom Conservancy](https://sfconservancy.org) to understand
some of the reasons why GitHub is not a good place to host FOSS projects.

Any use of this project's code by GitHub Copilot, past or present, is done
without our permission.  We do not consent to GitHub's use of this project's
code in Copilot.

![Logo of the GiveUpGitHub campaign](https://sfconservancy.org/img/GiveUpGitHub.png)


# Learning
I am learning most of these workflows, Git, CI/CD and best practices as I go, no formal training. Please forgive the mess.
# Inspiration
[zoneminder-containers](https://github.com/zoneminder-containers) repo and [data machines](https://github.com/baudneo/cuda_tensorflow_opencv).
## Guided install
[Here](https://medium.com/@baudneo/install-neo-mlapi-docker-image-9b8786488528) is a medium article I wrote about setting up the mlapi_cudnn image.
# Has
- CUDA 11.4 + cuDNN 8 [Compiled with Compute Capability - 6.0, 6.1, 7.0, 7.5, 8.0, 8.6] (See Gotcha section for LXC info)
- DLib 19.x with face recognition libs
- ALPR via Cloud and local openALPR binary [GPU support] (In final testing stage)
- Coral USB TPU libs for Object and Face detection. [May be upgraded to a full TF2 - Pytorch workflow] (see Gotcha section for LXC info)
- OpenCV 4.5.4 with cuDNN [HOG, YOLO v3/4, TinyYOLO v3/4] (Confirmed working)

# Why
[Neo MLAPI](https://github.com/baudneo/mlapi) has quite the installation if you are building from scratch and wanting to use a GPU.
You need to compile OpenCV with CUDA/cuDNN support to run YOLO, DLib for the face recognition libs and compile 
openALPR with GPU support. If you wish to use a USB TPU as well, then you need to set that all up.
This container aims to be a one and done solution for these requirements.

Setup neo-eventserver-mlapi-base which houses ZoneMinder and a Neo ZMES instance configured to communicate with this image.
Configure a few things if starting from scratch, or move over your existing config, secrets, user DB (db.json) and faces.dat
 from an existing Neo MLAPI instance.

This container is built using s6-overlay with full support for all things containers.
 Based on nvidia/cuda:11.4.2-cudnn8-devel-ubuntu20.04 image as a base. 

If you opt to build the image yourself it may take a long time as it compiles OpenCV, DLib and ALPR with GPU support. 
OpenCV is compiled using 6x CUDA_ARCH_BIN, so it takes awhile to compile. OpenCV with all of those Compute 
Capabilities compiled for should allow most consumer GPU' to run detections without issue.

This container aims to follow all the best practices of being a container meaning that the software and persistent
data are separated, with the container remaining static. This means the container can easily be updated/restored provided
the persistent data volumes are backed up. For advanced users, there is a procedure to mount an upgraded version of 
Neo PYZM and/or Neo MLAPI, OpenCV libs won't change much, if at all. This allows for upgrading without rebuilding the 
detection libs.

Not only does this aim to follow all the best practices, but this also aims to be
the easiest container with nearly everything configurable through environment variables
or automatically/preconfigured for you! I am actively developing Neo ZMES/PYZM/MLAPI so integrations with Docker will 
be stream lined.


# How

1. Install [Docker](https://docs.docker.com/get-docker/) and [docker-compose](https://docs.docker.com/compose/install/)
2. Install [Docker Nvidia Toolkit](https://github.com/NVIDIA/nvidia-docker) - REQUIRED to use GPU
3. You must have NVIDIA GPU drivers installed on the host (compatible with CUDA 11.4+ - NOTE: you do not need CUDA installed on host)
4. For TPU, you may need to download the libs on the docker host (YMMV)
5. Download docker-compose.yml
6. Download .env
7. Place all these files in the same folder and configure .env and the yml files as you please.
8. Run `docker-compose up -d` to start.

# Gotchas
1. If you are using a TPU:
- You may need the [coral](https://coral.ai/docs/accelerator/get-started/#runtime-on-linux) libs installed on the host. 

2. If you are running this inside of an unprivileged LXC (Proxmox, etc.):
- zoneminder-* and eventserver-* images do not work inside of unprivileged LXC containers. Only the mlapi_cudnn-base image will work for doing detections with TPU and GPU.
- For TPU, you have to set some permissions on your bare metal host - /dev/bus/usb/BUS/DEVICE (See udev rule)
- For GPU, you have to pass through your GPU and set proper cgroup permissions (see example Proxmox LXC .conf)
# Udev rule
NOTE: sometimes TPU is shown as Global Unichip Corp. If so you need to initialize the TPU on the bare metal host.
Run the [parrot.jpg example](https://coral.ai/docs/accelerator/get-started/#3-run-a-model-on-the-edge-tpu) from the pycoral install docs, make a shell script to run that command and make a systemd 
service file to run that script on every boot so the TPU is initialized on boot of the bare metal host. This guarantees 
that the TPU will be ready to use inside the LXC/Docker containers.

If this file does not exist, create it: /etc/udev/rules.d/99-edgetpu-accelerator.rules

```
# Examples of TPU in lsusb
# Bus 003 Device 004: ID 1a6e:089a Global Unichip Corp.
# Bus 003 Device 003: ID 18d1:9302 Google Inc.

# These are from Coral lib install, sets group owner to plugdev, uncomment if you want/need
#SUBSYSTEM=="usb",ATTRS{idVendor}=="1a6e",GROUP="plugdev"
#SUBSYSTEM=="usb",ATTRS{idVendor}=="18d1",GROUP="plugdev"

# The important part is MODE=0666, it sets RW perms for owner, group and others for the TPU (18d1:9302) only,
# this allows use inside of an unpriv LXC. Also, a symlink will be created to the tpu @ /dev/tpu. 'others' having RW access is the important bit.
# NOTE: cannot pass symlinked /dev/tpu from host into LXC, it will be empty!

SUBSYSTEM=="usb", ATTRS{idVendor}=="18d1", ATTRS{idProduct}=="9302", SYMLINK+="tpu", MODE="0666"
```
# Example Proxmox unprivileged LXC .conf 
To enable NVIDIA GPU passthrough please see [Here](https://www.passbe.com/2020/02/19/gpu-nvidia-passthrough-on-proxmox-lxc-container/).

In the above article it shows cgroup rules designed for versions of Proxmox under 7.0.
If using Proxmox 7.0+ change the cgroup to cgroup2.
To see the cgroups use `ls -alhn /dev/<device path>` -> `crw-rw-rw- 1 0 0 195, 0 Dec  2 13:51 /dev/nvidia0` The 195 is the important bit.
```
# /etc/pve/lxc/<CT ID>.conf
# keyctl and nesting required to use docker in an unpriv LXC
features: keyctl=1,nesting=1
# 1 = on
unprivileged: 1
# .conf uses Proxmox 7.0+ cgroup2, if using < 7.0 replace cgroup2 with cgroup
# These are for the GPU (Your cgroup numbers may be different, so check them!)
lxc.cgroup2.devices.allow: c 195:* rwm
lxc.cgroup2.devices.allow: c 234:* rwm
lxc.cgroup2.devices.allow: c 237:* rwm
# These are for USB (TPU) passthrough (Your cgroup numbers may be different, so check them!)
lxc.cgroup2.devices.allow: c 189:* rwm
lxc.cgroup2.devices.allow: c 510:* rwm
# Proxmox 7.0+ seems to need these 2 cgroup settings for the TPU (YMMV)
lxc.mount.auto: cgroup:rw
lxc.cgroup2.devices.allow: a
# /dev/bus/usb for the TPU
lxc.mount.entry: /dev/bus/usb dev/bus/usb none bind,optional,create=dir 0,0
# Nvidia, your /dev devices may have more or less than these mappings (these are for a 1660ti)
lxc.mount.entry: /dev/nvidia0 dev/nvidia0 none bind,optional,create=file
lxc.mount.entry: /dev/nvidiactl dev/nvidiactl none bind,optional,create=file
lxc.mount.entry: /dev/nvidia-uvm dev/nvidia-uvm none bind,optional,create=file
lxc.mount.entry: /dev/nvidia-modeset dev/nvidia-modeset none bind,optional,create=file
lxc.mount.entry: /dev/nvidia-uvm-tools dev/nvidia-uvm-tools none bind,optional,create=file
lxc.mount.entry: /dev/dri dev/dri none bind,optional,create=dir
lxc.mount.entry: /dev/nvidia-caps dev/nvidia-caps none bind,optional,create=dir 0,0
```

# BREAKING ISSUES
If the docker host is an unprivileged LXC, the zoneminder-* and eventserver-* images will not work properly. HTTP 
requests timeout or are no response, in the logs it is an issue to do when Nginx attempts to use PHP-FPM or fcgiwrap. 
I am actively working on a solution as I run unprivileged LXC' in my environment.

Here is a log example:
```
[nginx] 2021/12/05 13:05:25 [error] 1344#1344: *3 upstream timed out (110: Connection timed out) while reading response header from upstream, client: 10.0.0.139, server: localhost, request: "GET / HTTP/2.0", upstream: "fastcgi://unix:/run/php/php7.4-fpm.sock", host: "10.0.0.2"
 ```
I have tried changing unix sockets to TCP sockets with the same results. I am assuming it is a permissions problem 
or something else I am overlooking. For now I run the zoneminder-* and eventserver-* images on a bare metal host that 
send the detections to mlapi_cudnn. This repo will be 'complete' once I can succcessfully run zoneminder and eventserver images alongside mlapi_cudnn in an unprivileged LXC.
