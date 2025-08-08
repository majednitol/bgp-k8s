

FROM ubuntu:24.04

# Install build and runtime dependencies
RUN apt-get update && apt-get install -y --no-install-recommends \
    git \
    libconfig-dev \
    uthash-dev \
    build-essential \
    wget \
    libssl-dev \
    automake \
    autoconf \
    pkg-config \
    iproute2 \
    iputils-ping \
    curl \
    ca-certificates \
    bash \
    coreutils \
    busybox \
    kmod \
    && rm -rf /var/lib/apt/lists/*

# Install Go
RUN mkdir -p /usr/local/go/bin
WORKDIR /root

# clone and install srx-crypto-api
RUN git clone https://github.com/usnistgov/NIST-BGP-SRx.git && \
    cd NIST-BGP-SRx/srx-crypto-api && \
    ./configure --prefix=/usr/local CFLAGS="-O0 -g" && \
    make -j && \
    make all install && \
    make clean

# install go
RUN wget https://go.dev/dl/go1.23.5.linux-amd64.tar.gz && tar -C /usr/local -xzf go1.23.5.linux-amd64.tar.gz && rm go1.23.5.linux-amd64.tar.gz
ENV PATH="$PATH:/usr/local/go/bin:/root/go/bin"
RUN go install google.golang.org/protobuf/cmd/protoc-gen-go@latest && go install google.golang.org/grpc/cmd/protoc-gen-go-grpc@latest

# install gobgpsrx
ENV CGO_LDFLAGS="-L/usr/local/lib64/srx/ -Wl,-rpath -Wl,/usr/local/lib64/srx/" CGO_CFLAGS="-I/usr/local/include/srx/"
RUN git clone https://github.com/usnistgov/gobgpsrx.git && \
    cd gobgpsrx && \
    go build -o /usr/local/go/bin ./...


ENV PATH="$PATH:/usr/local/go/bin" LD_LIBRARY_PATH="/usr/local/lib64/srx"

COPY gobgp-router/*.conf /etc/
COPY gobgp-router/srxcryptoapi.conf /usr/local/etc/srxcryptoapi.conf
COPY gobgp-router/run_routers.sh /etc/

COPY gobgp-router/bgpsec-keys /var/lib/bgpsec-keys
RUN sed -i 's/\r$//' /etc/run_routers.sh && chmod +x /etc/run_routers.sh

# Expose gRPC and BGP ports
EXPOSE 50051 50052 50053 50054 50055 50056 50057 50058 50059 50060 50061 50062 50063 50064 50065 50066 50067

# Entry point
CMD ["/bin/bash", "/etc/run_routers.sh"]


# run in docker 
# docker build -t image-name .
# docker run --rm -it --privileged --name router4 image-name




