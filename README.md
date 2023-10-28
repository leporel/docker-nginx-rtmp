# docker-nginx-rtmp fork
A Dockerfile installing NGINX, nginx-rtmp-module and FFmpeg from source with
default settings for HLS live streaming. Built on Alpine Linux (Ubuntu for cuda).

* Nginx 1.23.2 (Mainline version compiled from source)
* nginx-rtmp-module 1.2.2 (compiled from source)
* ffmpeg 6.0 (compiled from source + support  flv rtmp h265/hevc/av1 via [patch](https://github.com/runner365/ffmpeg_rtmp_h265))
* Default HLS settings (See: [nginx.conf](nginx.conf))

## Usage

### Server

* Build and run container from source:
```
docker build -t nginx-rtmp .
docker run -it -p 1935:1935 -p 8080:80 --rm nginx-rtmp
```

* Stream live content to:
```
rtmp://localhost:1935/stream/$STREAM_NAME
```

### SSL 
To enable SSL, see [nginx.conf](nginx.conf) and uncomment the lines:
```
listen 443 ssl;
ssl_certificate     /opt/certs/example.com.crt;
ssl_certificate_key /opt/certs/example.com.key;
```

This will enable HTTPS using a self-signed certificate supplied in [/certs](/certs). If you wish to use HTTPS, it is **highly recommended** to obtain your own certificates and update the `ssl_certificate` and `ssl_certificate_key` paths.

I recommend using [Certbot](https://certbot.eff.org/docs/install.html) from [Let's Encrypt](https://letsencrypt.org).

### Custom `nginx.conf`
If you wish to use your own `nginx.conf`, mount it as a volume in your `docker-compose` or `docker` command as `nginx.conf.template`:
```yaml
volumes:
  - ./nginx.conf:/etc/nginx/nginx.conf
```

### OBS Configuration
* Stream Type: `Custom Streaming Server`
* URL: `rtmp://localhost:1935/stream`
* Stream Key: `hello`

### Watch Stream
* Load up the example hls.js player in your browser:
```
http://localhost:8080/player.html?url=http://localhost:8080/live/hello.m3u8
```

* Or in Safari, VLC or any HLS player, open:
```
http://localhost:8080/live/$STREAM_NAME.m3u8
```
* Example Playlist: `http://localhost:8080/live/hello.m3u8`
* [HLS.js Player](https://hls-js.netlify.app/demo/?src=http%3A%2F%2Flocalhost%3A8080%2Flive%2Fhello.m3u8)
* FFplay: `ffplay -fflags nobuffer rtmp://localhost:1935/stream/hello`

### Restream to multiple destination

#### H264

example nginx.conf

```nginx
rtmp {
	access_log /var/log/nginx/access.log;

    server {
                listen 1935; # Listen on standard RTMP port
                chunk_size 4000; 

                # This application is to accept incoming stream
				application push_live_60fps_m {
					allow publish 127.0.0.1;
					allow publish 192.168.1.0/24;
					deny publish all;
					
					meta copy;
					
				    live on; # Allows live input
				    drop_idle_publisher 15s; 
					
					exec_push  /usr/local/bin/ffmpeg -i rtmp://localhost:1935/$app/$name 
					 -c:v libx264 -preset medium -b:v 6000k -maxrate 6000k -bufsize 12000k
					 -r 60 -profile:v high -level 5.1 
					 -x264opts nal-hrd=cbr:bframes=2:keyint=120:no-scenecut
					 -c:a aac -b:a 192k 
					 -f flv rtmp://localhost:1935/restream/$name;
				}

				application restream {
					allow publish 127.0.0.1;
					allow publish 192.168.1.0/24;
					deny publish all;
					
					live on;
					meta copy;
					record off;
					push_reconnect 500ms;

					push rtmp://fra05.contribute.live-video.net/app/my_stream_key;
					push rtmp://a.rtmp.youtube.com/live2/my_stream_key;
					push rtmp://b.rtmp.youtube.com/live2?backup=1/my_stream_key;
				}
		}
}
```

#### h265

> if you want push rtmp h265/av1 stream - add `-f flv -flvflags ext_header`

example nginx.conf
```nginx
rtmp {
	access_log /var/log/nginx/access.log;

    server {
                listen 1935; # Listen on standard RTMP port
                chunk_size 4000; 

                # This application is to accept incoming stream
				application push_live_60fps_h265 {
					allow publish 127.0.0.1;
					allow publish 192.168.1.0/24;
					deny publish all;
					
					meta copy;
					
				    live on; # Allows live input
				    drop_idle_publisher 15s; 

					exec_push  /usr/local/bin/ffmpeg -i rtmp://localhost:1935/$app/$name 
					 -c:v libx265 -preset fast
					 -r 60 -profile:v main -level 5.1 
					 -x265-params bitrate=4500:vbv-maxrate=4500:vbv-bufsize=9000:strict-cbr:bframes=2:keyint=120:scenecut=0
					 -c:a aac -b:a 192k
					 -f flv rtmp://localhost:1936/restream/$name;
					
					exec_push  /usr/local/bin/ffmpeg -listen 1 -i rtmp://localhost:1936/restream/$name 
						-c copy -f flv -flvflags ext_header rtmp://a.rtmp.youtube.com/live2/my_stream_key
						-c copy -f flv -flvflags ext_header rtmp://a.rtmp.youtube.com/live2/my_stream_key;
				}	
		}
}
```

it seems the tee muxer don't work with runner365/ffmpeg_rtmp_h265 patch, so i found working solution with `ffmpeg -listen 1`


### FFmpeg Build
```
$ ffmpeg -buildconf

ffmpeg version 6.0 Copyright (c) 2000-2023 the FFmpeg developers
  built with gcc 11 (Ubuntu 11.4.0-1ubuntu1~22.04)
  configuration: --pkg-config-flags=--static --prefix=/usr/local --enable-version3 --enable-gpl --enable-nonfree --enable-libfdk-aac --enable-openssl --enable-libnpp --enable-cuda --enable-ffnvcodec --enable-cuda-llvm --enable-libx264 --enable-libx265 --enable-libaom --enable-libdav1d --enable-libvpx --enable-libopus --enable-cuvid --enable-nvenc --enable-libnpp --disable-debug --disable-doc --disable-ffplay --extra-cflags=-I/usr/local/cuda/include --extra-ldflags=-L/usr/local/cuda/lib64 --extra-libs='-lpthread -lm'
  libavutil      58.  2.100 / 58.  2.100
  libavcodec     60.  3.100 / 60.  3.100
  libavformat    60.  3.100 / 60.  3.100
  libavdevice    60.  1.100 / 60.  1.100
  libavfilter     9.  3.100 /  9.  3.100
  libswscale      7.  1.100 /  7.  1.100
  libswresample   4. 10.100 /  4. 10.100
  libpostproc    57.  1.100 / 57.  1.100

  configuration:
    --pkg-config-flags=--static
    --prefix=/usr/local
    --enable-version3
    --enable-gpl
    --enable-nonfree
    --enable-libfdk-aac
    --enable-openssl
    --enable-libnpp
    --enable-cuda
    --enable-ffnvcodec
    --enable-cuda-llvm
    --enable-libx264
    --enable-libx265
    --enable-libaom
    --enable-libdav1d
    --enable-libsvtav1
    --enable-libvpx
    --enable-libopus
    --enable-cuvid
    --enable-nvenc
    --enable-libnpp
    --disable-debug
    --disable-doc
    --disable-ffplay
    --extra-cflags=-I/usr/local/cuda/include
    --extra-ldflags=-L/usr/local/cuda/lib64
    --extra-libs='-lpthread -lm'
```


### FFmpeg Hardware Acceleration
A `Dockerfile.cuda` image is available to enable FFmpeg hardware acceleration via the [NVIDIA's CUDA](https://trac.ffmpeg.org/wiki/HWAccelIntro#CUDANVENCNVDEC).

```
docker build -t nginx-ffmpeg-cuda -f .\Dockerfile.cuda .
docker run -it -p 1935:1935 -p 8080:80 --rm nginx-ffmpeg-cuda
```

change codec in nginx.conf   
for example:  `libx264` to `h264_nvenc` 

You must have a supported platform and driver to run this image.

* https://github.com/NVIDIA/nvidia-docker
* https://docs.nvidia.com/datacenter/cloud-native/container-toolkit/install-guide.html#docker
* https://docs.docker.com/docker-for-windows/wsl/
* https://trac.ffmpeg.org/wiki/HWAccelIntro#CUDANVENCNVDEC

## Resources
* https://alpinelinux.org/
* http://nginx.org
* https://github.com/arut/nginx-rtmp-module
* https://www.ffmpeg.org
* https://obsproject.com
