FROM ubuntu:25.10 AS build
ARG SEP_ROM_URL
ARG SEP_FIRMWARE_IV
ARG SEP_FIRMWARE_KEY

# installing dependencies
RUN apt update && apt upgrade -y
RUN apt-get install -y\
    git \
    build-essential\ 
    libtool\ 
    meson\ 
    ninja-build\ 
    pkg-config\ 
    libcapstone-dev\ 
    device-tree-compiler\ 
    libglib2.0-dev\ 
    gnutls-bin\ 
    libjpeg-turbo8-dev\ 
    libpng-dev\ 
    libslirp-dev\ 
    libssh-dev\ 
    libusb-1.0-0-dev\ 
    liblzo2-dev\ 
    libncurses5-dev\ 
    libpixman-1-dev\ 
    libsnappy-dev\ 
    vde2\ 
    zstd\ 
    libgnutls28-dev\ 
    libgmp10\ 
    libgmp3-dev\ 
    lzfse\ 
    liblzfse-dev\ 
    libgtk-3-dev\ 
    libsdl2-dev\ 
    python3\ 
    python3-venv\ 
    python3-pip \
    wget \
    unzip

# setting up repo
RUN git clone https://github.com/ChefKissInc/QEMUAppleSilicon /QEMUAppleSilicon
WORKDIR /QEMUAppleSilicon
RUN git submodule update --init

RUN mkdir build
WORKDIR /QEMUAppleSilicon/build

# building QEMU
RUN ../configure\ 
    --target-list=aarch64-softmmu,x86_64-softmmu\ 
    --enable-lzfse\ 
    --enable-slirp\ 
    --enable-capstone\ 
    --enable-curses\ 
    --enable-libssh\ 
    --enable-virtfs\ 
    --enable-zstd\ 
    --enable-nettle\ 
    --enable-gnutls\ 
    --enable-gtk\ 
    --enable-sdl\ 
    --disable-werror

RUN make -j$(nproc)

WORKDIR /
RUN pip3 install --break-system-packages pyasn1 pyasn1-modules

# creating disks
RUN ./QEMUAppleSilicon/build/qemu-img create -f raw nvme.1 16G
RUN ./QEMUAppleSilicon/build/qemu-img create -f raw nvme.2 8M
RUN ./QEMUAppleSilicon/build/qemu-img create -f raw nvme.3 128K
RUN ./QEMUAppleSilicon/build/qemu-img create -f raw nvme.4 8K
RUN ./QEMUAppleSilicon/build/qemu-img create -f raw nvram  8K
RUN ./QEMUAppleSilicon/build/qemu-img create -f raw nvme.6 4K
RUN ./QEMUAppleSilicon/build/qemu-img create -f raw nvme.7 1M
RUN ./QEMUAppleSilicon/build/qemu-img create -f raw nvme.8 3M
RUN ./QEMUAppleSilicon/build/qemu-img create -f raw sep_nvram 2K
RUN ./QEMUAppleSilicon/build/qemu-img create -f raw sep_ssc 128K

# downloading IPSW
RUN wget https://updates.cdn-apple.com/2020SummerSeed/fullrestores/001-35886/5FE9BE2E-17F8-41C8-96BB-B76E2B225888/iPhone11,8,iPhone12,1_14.0_18A5351d_Restore.ipsw

# iOS firmware stuff
RUN mkdir iPhone11_8_iPhone12_1_14.0_18A5351d_Restore
WORKDIR /iPhone11_8_iPhone12_1_14.0_18A5351d_Restore
RUN unzip ../iPhone11,8,iPhone12,1_14.0_18A5351d_Restore.ipsw

WORKDIR /

# creating AP ticket
RUN wget https://github.com/ChefKissInc/QEMUAppleSiliconTools/raw/refs/heads/master/create_apticket.py
RUN wget https://github.com/ChefKissInc/QEMUAppleSiliconTools/raw/refs/heads/master/ticket.shsh2

RUN python3 ./create_apticket.py n104ap ./iPhone11_8_iPhone12_1_14.0_18A5351d_Restore/BuildManifest.plist ticket.shsh2 root_ticket.der

# Fetching the SEP ROM
RUN wget $SEP_ROM_URL

# Preparing the SEP firmware
RUN wget https://github.com/ChefKissInc/QEMUAppleSiliconTools/raw/refs/heads/master/create_septicket.py

# install libgeneral
RUN git clone https://github.com/tihmstar/libgeneral.git
WORKDIR /libgeneral

RUN ./autogen.sh
RUN make
RUN make install

WORKDIR /

# installing libplist
RUN git clone https://github.com/libimobiledevice/libplist.git --recursive
WORKDIR /libplist

RUN ./autogen.sh
RUN make
RUN make install

WORKDIR /

# install img4tool
RUN git clone --recursive https://github.com/tihmstar/img4tool.git
WORKDIR /img4tool

RUN ./autogen.sh
RUN make
RUN make install

WORKDIR /

# install img4lib
RUN git clone https://github.com/xerub/img4lib.git
WORKDIR /img4lib

RUN make

WORKDIR /

# creating ticket
RUN python3 create_septicket.py n104ap iPhone11_8_iPhone12_1_14.0_18A5351d_Restore/BuildManifest.plist ticket.shsh2 sep_root_ticket.der

# downloading iOS 14.7.1 ipsw
RUN wget https://updates.cdn-apple.com/2021SummerFCS/fullrestores/071-73868/321919C4-1F21-4387-936D-B72374C39DD6/iPhone11,8,iPhone12,1_14.7.1_18G82_Restore.ipsw
WORKDIR /iPhone11,8,iPhone12,1_14.7.1_18G82_Restore
RUN unzip ../iPhone11,8,iPhone12,1_14.7.1_18G82_Restore.ipsw

WORKDIR /

# decrypting and repackaging firmware
RUN ldconfig
RUN img4tool -e --iv $SEP_FIRMWARE_IV --key $SEP_FIRMWARE_KEY -o sep-firmware.n104.RELEASE iPhone11,8,iPhone12,1_14.7.1_18G82_Restore/Firmware/all_flash/sep-firmware.n104.RELEASE.im4p
RUN img4tool -t rsep -d ff86cbb5e06c820266308202621604696d706c31820258ff87a3e8e0730e300c1604747a3073020407e78000ff868bc9da730e300c160461726d73020400d84000ff87a389da7382010e3082010a160474626d730482010036373166326665363234636164373234643365353332633464666361393732373734353966613362326232366635643962323032383061643961303037666635323834393936383138653962303461336434633034393061663833313630633464356330313832396536633635303836313230666133346539663263323165373237316265623231636139386237386464303064363037326530366464393962666163623262616362623261373830613465636161303363326361333930303931636334613461666231623737326238646234623865653566663365636437373135306531626566333633303034336637373665666265313130316538623433ff87a389da7282010e3082010a160474626d720482010034626631393164373134353637356364306264643131616166373734386138663933373363643865666234383830613130353237633938393833666636366538396438333330623730626237623561333530393864653735353265646635373762656166363137353235613831663161393838373838613865346665363734653936633439353066346136366136343231366561356438653333613833653530353962333536346564633533393664353539653337623030366531633637343633623736306336333164393163306339363965366662373130653962333061386131396338333166353565636365393835363331643032316134363361643030 -c sep-firmware.n104.RELEASE.im4p sep-firmware.n104.RELEASE
RUN /img4lib/img4 -F -o sep-firmware.n104.RELEASE.new.img4 -i sep-firmware.n104.RELEASE.im4p -M sep_root_ticket.der