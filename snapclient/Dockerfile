ARG BUILD_FROM="ghcr.io/hassio-addons/base/amd64:15.0.2"
ARG BUILD_ARCH="amd64"

# based upon https://github.com/Saiyato/snapclient_docker
FROM $BUILD_FROM as snapcast

WORKDIR /root
# Dummy file is needed, because there's no conditional copy
COPY dummy qemu-*-static /usr/bin/

RUN apk -U add alsa-lib-dev avahi-dev bash build-base ccache cmake expat-dev flac-dev git libvorbis-dev opus-dev soxr-dev  \
 && git clone --recursive https://github.com/badaix/snapcast.git \
 && cd snapcast \
 && wget https://boostorg.jfrog.io/artifactory/main/release/1.78.0/source/boost_1_78_0.tar.bz2 && tar -xvjf boost_1_78_0.tar.bz2 \
 && cmake -S . -B build -DBOOST_ROOT=boost_1_78_0 -DCMAKE_CXX_COMPILER_LAUNCHER=ccache -DBUILD_WITH_PULSE=OFF -DCMAKE_BUILD_TYPE=Release -DBUILD_SERVER=OFF .. \
 && cmake --build build --parallel 3
 
# Final stage
FROM $BUILD_FROM
COPY dummy qemu-*-static /usr/bin/
LABEL maintainer="Koying"

RUN apk add alsa-lib avahi-libs expat flac libvorbis opus soxr \
 && rm -rf /etc/ssl /var/cache/apk/* /lib/apk/db/* /root/snapcast /usr/bin/dummy
 
COPY --from=snapcast /root/snapcast/bin/snapclient /usr/local/bin

# Copy data
COPY data/*.sh /

CMD [ "/run.sh" ]
