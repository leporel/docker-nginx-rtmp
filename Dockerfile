ARG NGINX_VERSION=1.23.2
ARG NGINX_RTMP_VERSION=1.2.2
ARG FFMPEG_VERSION=6.1

##############################
# Build the NGINX-build image.
FROM alpine:3.18.4 as build-nginx
ARG NGINX_VERSION
ARG NGINX_RTMP_VERSION
ARG MAKEFLAGS="-j4"

# Build dependencies.
RUN apk add --no-cache \
  build-base \
  ca-certificates \
  curl \
  gcc \
  libc-dev \
  libgcc \
  linux-headers \
  make \
  musl-dev \
  openssl \
  openssl-dev \
  pcre \
  pcre-dev \
  pkgconf \
  pkgconfig \
  zlib-dev

WORKDIR /tmp

# Get nginx source.
RUN wget https://nginx.org/download/nginx-${NGINX_VERSION}.tar.gz && \
  tar zxf nginx-${NGINX_VERSION}.tar.gz && \
  rm nginx-${NGINX_VERSION}.tar.gz

# Get nginx-rtmp module.
RUN wget https://github.com/arut/nginx-rtmp-module/archive/v${NGINX_RTMP_VERSION}.tar.gz && \
  tar zxf v${NGINX_RTMP_VERSION}.tar.gz && \
  rm v${NGINX_RTMP_VERSION}.tar.gz

# Compile nginx with nginx-rtmp module.
WORKDIR /tmp/nginx-${NGINX_VERSION}
RUN \
  ./configure \
  --prefix=/usr/local/nginx \
  --add-module=/tmp/nginx-rtmp-module-${NGINX_RTMP_VERSION} \
  --conf-path=/etc/nginx/nginx.conf \
  --with-threads \
  --with-file-aio \
  --with-http_ssl_module \
  --with-debug \
  --with-http_stub_status_module \
  --with-cc-opt="-Wimplicit-fallthrough=0" && \
  make && \
  make install

###############################
# Build the FFmpeg-build image.
FROM alpine:3.18.4 as build-ffmpeg
ARG FFMPEG_VERSION
ARG PREFIX=/usr/local
ARG MAKEFLAGS="-j4"

# FFmpeg build dependencies.
RUN apk update && apk add --no-cache \
  build-base \
  clang \
  cmake \
  git \
  coreutils \
  freetype-dev \
  lame-dev \
  libogg-dev \
  libass \
  libass-dev \
  libvpx-dev \
  libvorbis-dev \
  libwebp-dev \
  libtheora-dev \
  openssl-dev \
  opus-dev \
  pkgconf \
  pkgconfig \
  rtmpdump-dev \
  wget \
  x264-dev \
  x265-dev \
  aom-dev \
  dav1d-dev \
  yasm

RUN echo http://dl-cdn.alpinelinux.org/alpine/edge/community >> /etc/apk/repositories
RUN apk add --no-cache fdk-aac-dev

WORKDIR /tmp

RUN \
  git clone --depth=1 https://gitlab.com/AOMediaCodec/SVT-AV1.git && \
  cd SVT-AV1 && \
  sed -i 's/picture_copy(/svt_av1_picture_copy(/g' \
    Source/Lib/Common/Codec/EbPictureOperators.c \
    Source/Lib/Common/Codec/EbPictureOperators.h \
    Source/Lib/Encoder/Codec/EbFullLoop.c \
    Source/Lib/Encoder/Codec/EbProductCodingLoop.c && \
  cd Build && \
  cmake .. -G"Unix Makefiles" -DCMAKE_INSTALL_LIBDIR=lib -DBUILD_SHARED_LIBS=OFF -DCMAKE_BUILD_TYPE=Release && \
  make -j$(nproc) install

# Get FFmpeg source.
RUN wget http://ffmpeg.org/releases/ffmpeg-${FFMPEG_VERSION}.tar.gz && \
  tar zxf ffmpeg-${FFMPEG_VERSION}.tar.gz && \
  rm ffmpeg-${FFMPEG_VERSION}.tar.gz

# Compile ffmpeg.
WORKDIR /tmp/ffmpeg-${FFMPEG_VERSION}
RUN \
  ./configure \
  --prefix=${PREFIX} \
  --enable-version3 \
  --enable-gpl \
  --enable-nonfree \
  --enable-libmp3lame \
  --enable-libx264 \
  --enable-libx265 \
  --enable-libsvtav1 \
  --enable-libaom \
  --enable-libdav1d \
  --enable-libvpx \
  --enable-libtheora \
  --enable-libvorbis \
  --enable-libopus \
  --enable-libfdk-aac \
  --enable-libass \
  --enable-libwebp \
  --enable-postproc \
  --enable-libfreetype \
  --enable-openssl \
  --disable-debug \
  --disable-doc \
  --disable-ffplay \
  --extra-libs="-lpthread -lm" && \
  make && \
  make install && \
  make distclean

# Cleanup.
RUN rm -rf /var/cache/* /tmp/*

##########################
# Build the release image.
FROM alpine:3.18.4

# Set default ports.
ENV HTTP_PORT 80
ENV HTTPS_PORT 443
ENV RTMP_PORT 1935

RUN apk update && apk add --no-cache \
  ca-certificates \
  gettext \
  openssl \
  pcre \
  freetype-dev \
  lame-dev \
  libogg-dev \
  libass \
  libass-dev \
  libvpx-dev \
  libvorbis-dev \
  libwebp-dev \
  libtheora-dev \
  libogg \
  opus-dev \
  curl \
  rtmpdump \
  x264-dev \
  x265-dev \
  aom-dev \
  dav1d-dev


RUN rm -rf /var/cache/apk/*

COPY --from=build-nginx /usr/local/nginx /usr/local/nginx
COPY --from=build-nginx /etc/nginx /etc/nginx
COPY --from=build-ffmpeg /usr/local /usr/local
COPY --from=build-ffmpeg /usr/lib/libfdk-aac.so.2 /usr/lib/libfdk-aac.so.2

# Add NGINX path, config and static files.
ENV PATH "${PATH}:/usr/local/nginx/sbin"
COPY nginx.conf /etc/nginx/nginx.conf
RUN mkdir -p /opt/data && mkdir /www
COPY static /www/static

RUN mkdir -p /var/log/nginx/ && \
	ln -sf /dev/stdout /var/log/nginx/access.log && \
    ln -sf /dev/stderr /var/log/nginx/error.log

EXPOSE 1935
EXPOSE 80

CMD ["nginx"]
