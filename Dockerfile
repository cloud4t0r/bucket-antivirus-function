FROM amazonlinux:2

# Set up working directories
RUN mkdir -p /opt/app/build
RUN mkdir -p /opt/app/bin/

# Copy in the lambda source
WORKDIR /opt/app
COPY ./*.py /opt/app/
COPY requirements.txt /opt/app/requirements.txt

# Install packages
RUN yum update -y && amazon-linux-extras enable python3.8 && yum clean metadata && yum install python3.8 -y 
RUN yum install -y cpio yum-utils zip unzip less git make autoconf automake libtool libtool-ltdl\* pkg-config gcc-c++ openssl-devel openssl libcurl-devel

# This had --no-cache-dir, tracing through multiple tickets led to a problem in wheel
RUN ln -s /usr/bin/pip3.8 /usr/bin/pip3 && pip3 install -r requirements.txt
RUN rm -rf /root/.cache/pip

# Download libraries we need to run in lambda
WORKDIR /tmp
RUN yumdownloader -x \*i686 --archlist=x86_64 json-c pcre2
RUN rpm2cpio json-c*.rpm | cpio -idmv
RUN rpm2cpio pcre*.rpm | cpio -idmv
RUN git clone https://github.com/Cisco-Talos/clamav-devel.git && \
    cd clamav-devel && \
    git checkout $(git branch -r|grep rel|sort -V|tail -1) && \
    ./autogen.sh && ./configure --prefix=/usr/local/clamav && \
    make && make install

# Copy over the binaries and libraries
RUN cp -Rp /usr/local/clamav/bin/clamscan /usr/local/clamav/bin/freshclam /usr/local/clamav/lib64/* /opt/app/bin/ && rm -Rf /opt/app/bin/pkgonfig \
    && cp -p /usr/bin/ld.bfd /opt/app/bin/ld \
    && cp -p /usr/lib64/libbfd-2.29.1-30.amzn2.so /opt/app/bin
RUN for i in $(ldd /opt/app/bin/freshclam|awk '{print $1}'|grep -v "linux"|grep -v "clam"); do cp /lib64/$i /opt/app/bin/; done 
RUN for i in $(ldd /opt/app/bin/clamscan|awk '{print $1}'|grep -v "linux"|grep -v "clam"); do cp /lib64/$i /opt/app/bin/; done 
RUN strip /opt/app/bin/* 2>/dev/null || true 

# Fix the freshclam.conf settings
RUN echo "DatabaseMirror database.clamav.net" > /opt/app/bin/freshclam.conf
RUN echo "CompressLocalDatabase yes" >> /opt/app/bin/freshclam.conf

# Create the zip file
WORKDIR /opt/app
RUN zip -r9 --exclude="*test*" /opt/app/build/lambda.zip *.py bin

WORKDIR /usr/local/lib/python3.8/site-packages
RUN find . -name "*.py[co]" -o -name __pycache__ -exec rm -rf {} +
RUN zip -r9 /opt/app/build/lambda.zip *

WORKDIR /opt/app
