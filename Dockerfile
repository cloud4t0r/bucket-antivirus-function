FROM amazonlinux:2

# Set up working directories
RUN mkdir -p /var/task/build
RUN mkdir -p /var/task/bin/

# Copy in the lambda source
WORKDIR /var/task
COPY ./*.py /var/task/
COPY requirements.txt /var/task/requirements.txt

# Install packages
RUN yum update -y && amazon-linux-extras enable python3.8 && yum clean metadata && yum install python3.8 -y && yum install -y cpio yum-utils zip unzip less libcurl-devel binutils openssl openssl-devel wget tar && yum groupinstall -y "Development Tools" 
RUN yum install -y cpio yum-utils zip unzip less git make autoconf automake libtool libtool-ltdl\* pkg-config gcc-c++ cmake3 wget check bzip2-\* libxml2-\* pcre2-\* json-c-\* ncurses-\* sendmail-milter\* 

# This had --no-cache-dir, tracing through multiple tickets led to a problem in wheel
RUN /usr/bin/pip3 --version
RUN rm -f /usr/bin/pip3 && ln -s /usr/bin/pip3.8 /usr/bin/pip3 && pip3 install -r requirements.txt && pip3 install pytest
RUN rm -rf /root/.cache/pip

# Download libraries we need to run in lambda
WORKDIR /tmp
RUN yumdownloader -x \*i686 --archlist=x86_64 json-c pcre2
RUN rpm2cpio json-c*.rpm | cpio -idmv
RUN rpm2cpio pcre*.rpm | cpio -idmv
RUN wget https://github.com/Kitware/CMake/archive/refs/tags/v3.21.3.tar.gz && \
    tar zxvf v3.21.3.tar.gz && cd CMake-3.21.3 && \
    mkdir build && cd build && cmake3 .. -DCMAKE_INSTALL_PREFIX=/usr/local && \
    make -j8 && make install
RUN wget https://github.com/libcheck/check/archive/refs/tags/0.15.2.tar.gz && \
    tar zxvf 0.15.2.tar.gz && \
    cd check-0.15.2 && \
    mkdir build && cd build && cmake .. && make && make check && make install
RUN git clone https://github.com/Cisco-Talos/clamav-devel.git && \
    cd clamav-devel && \
    git checkout $(git branch -r|grep rel|sort -V|tail -1) && \
    mkdir build && cd build && \
    ln -s /usr/lib64/libmilter.so.1.0 /usr/lib64/libmilter.so && ldconfig && \
    /usr/local/bin/cmake .. -DCMAKE_INSTALL_PREFIX=/usr/local/clamav && \ 
    make -j8 && make install
    #/usr/local/bin/cmake .. -DCMAKE_INSTALL_PREFIX=/usr/local/clamav -DENABLE_JSON_SHARED=OFF && \ 

# Copy over the binaries and libraries
RUN cp -Rp /usr/local/clamav/bin/clamscan /usr/local/clamav/bin/freshclam /usr/local/clamav/lib64/* /var/task/bin/ && rm -Rf /var/task/bin/pkgonfig \
    && cp -p /usr/bin/ld.bfd /var/task/bin/ld \
    && cp -p /usr/lib64/libbfd-2.29.1-30.amzn2.so /var/task/bin
RUN for i in $(ldd /var/task/bin/freshclam|awk '{print $1}'|grep -v "linux"|grep -v "clam"); do cp /lib64/$i /var/task/bin/; done 
RUN for i in $(ldd /var/task/bin/clamscan|awk '{print $1}'|grep -v "linux"|grep -v "clam"); do cp /lib64/$i /var/task/bin/; done 
RUN strip /var/task/bin/* 2>/dev/null || true 

# Fix the freshclam.conf settings
RUN echo "DatabaseMirror database.clamav.net" > /var/task/bin/freshclam.conf
RUN echo "CompressLocalDatabase yes" >> /var/task/bin/freshclam.conf

# Create the zip file
WORKDIR /var/task
RUN zip -r9 --exclude="*test*" /var/task/build/lambda.zip *.py bin

WORKDIR /usr/local/lib/python3.8/site-packages
RUN find . -name "*.py[co]" -o -name __pycache__ -exec rm -rf {} +
RUN zip -r9 /var/task/build/lambda.zip *

WORKDIR /var/task
